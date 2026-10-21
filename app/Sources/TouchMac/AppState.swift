import AppKit
import CoreGraphics
import Observation
import ServiceManagement
import SwiftUI
import TouchMacCore

/// Confined to `SensorClient.queue`: every feed and setting change runs there.
extension TapEngine: @unchecked Sendable {}

struct TapEvent: Identifiable {
    enum Kind { case action, unmatched, error, info }
    let id = UUID()
    let date = Date()
    let kind: Kind
    let text: String
    var zoneID: String?
}

struct CalibrationResult {
    let zoneID: String
    let kept: Int
    let dropped: Int
    let accuracy: Double?  // this zone's leave-one-out score; nil while it is the only calibrated zone
    let confusedWith: String?  // name of the zone its taps are mistaken for
}

/// Recent signal peaks for the live meter. Main thread only; not observed (the meter polls it).
final class SignalHistory {
    static let length = 150  // 7.5 s at 20 Hz
    private(set) var values = [Double](repeating: 0, count: length)
    private(set) var threshold = 0.04
    private(set) var noiseFloor = 0.0

    func push(_ v: Double, threshold: Double, noise: Double) {
        values.removeFirst()
        values.append(v)
        self.threshold = threshold
        noiseFloor = noise
    }
}

@Observable @MainActor
final class AppState {
    var config: AppConfig {
        didSet { if config != oldValue { configChanged(from: oldValue) } }
    }
    var enabled = true
    var testMode = false
    var sensorAlive = false
    var helperStatus = Helper.status
    var helperBusy = false
    let hardwarePresent = SensorClient.hardwarePresent
    var flashZone: String?
    var events: [TapEvent] = []
    /// A problem the user should see until they dismiss it.
    var notice: String?
    var quality: Classifier.Report?
    var launchAtLogin = SMAppService.mainApp.status == .enabled

    var calibratingZone: String?
    var calibrationTaps = 0
    var calibrationResult: CalibrationResult?
    var calibrationQueue: [String] = []
    var calibrationIndex = 0  // 1-based position in the current run
    var calibrationCount = 0
    let calibrationTarget = 10

    @ObservationIgnored let signal = SignalHistory()
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored var didLaunch = false
    @ObservationIgnored private let client = SensorClient()
    @ObservationIgnored private let engine: TapEngine
    @ObservationIgnored private var classifier: Classifier
    @ObservationIgnored private var grouper = TapGrouper()
    @ObservationIgnored private var pendingCalibration: [[Double]] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var lastPoll = 0.0

    init() {
        let (cfg, warning) = AppConfig.load()
        config = cfg
        notice = warning
        engine = TapEngine(thresholdG: cfg.thresholdG, adaptive: cfg.adaptiveThreshold)
        classifier = Self.makeClassifier(cfg)
        quality = Self.makeQuality(cfg)

        engine.onTap = { [weak self] feature in
            DispatchQueue.main.async { self?.handleTap(feature) }
        }
        Self.wire(client, to: engine)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    /// Non-isolated on purpose: these closures run on the sensor queue, not the main actor.
    nonisolated private static func wire(_ client: SensorClient, to engine: TapEngine) {
        client.onAccel = { t, x, y, z in engine.feedAccel(t: t, x: x, y: y, z: z) }
        client.onGyro = { t, x, y, z in engine.feedGyro(t: t, x: x, y: y, z: z) }
    }

    private func tick() {
        guard Snapshot.directory == nil else { return }  // never take the sensor from the running app
        client.connectIfNeeded()
        sensorAlive = client.isAlive
        if !sensorAlive { helperStatus = Helper.status }
    }

    private static func makeClassifier(_ cfg: AppConfig) -> Classifier {
        Classifier(samplesByZone: samplesByZone(cfg), maxDistance: cfg.maxDistance)
    }

    private static func makeQuality(_ cfg: AppConfig) -> Classifier.Report? {
        let samples = samplesByZone(cfg)
        return samples.count >= 2 ? Classifier.crossValidate(samples, maxDistance: cfg.maxDistance) : nil
    }

    private static func samplesByZone(_ cfg: AppConfig) -> [String: [[Double]]] {
        // uniquing: a hand-edited file with a repeated id must not crash the app
        Dictionary(cfg.zones.filter(\.isCalibrated).map { ($0.id, $0.samples) }, uniquingKeysWith: { a, _ in a })
    }

    private func configChanged(from old: AppConfig) {
        let t = config.thresholdG, adaptive = config.adaptiveThreshold
        client.queue.async { [engine] in
            engine.thresholdG = t
            engine.adaptive = adaptive
        }
        classifier = Self.makeClassifier(config)
        if config.maxDistance != old.maxDistance || config.zones.map(\.samples) != old.zones.map(\.samples) {
            quality = Self.makeQuality(config)
        }
        guard Snapshot.directory == nil else { return }  // demo data must not reach the real settings file
        // debounce: a slider drag changes the config dozens of times a second
        saveWork?.cancel()
        let snapshot = config
        let work = DispatchWorkItem { [weak self] in
            do { try snapshot.save() } catch { self?.notice = "Could not save settings: \(error.localizedDescription)" }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func zone(_ id: String) -> ZoneConfig {
        config.zones.first { $0.id == id } ?? ZoneConfig(id: id, name: id)
    }

    func update(_ zone: ZoneConfig) {
        if let i = config.zones.firstIndex(where: { $0.id == zone.id }) {
            config.zones[i] = zone
        }
    }

    /// Latest peak and threshold into the meter history, at most 25 times a second.
    func pollSignal() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPoll > 0.04, Snapshot.directory == nil else { return }
        lastPoll = now
        let (peak, threshold, noise) = client.queue.sync { (engine.readPeak(), engine.effectiveThreshold, engine.noiseFloor) }
        signal.push(peak, threshold: threshold, noise: noise)
    }

    // MARK: taps

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Keystrokes and trackpad clicks shake the chassis too. Reading idle time needs no permission.
    nonisolated static func userJustTypedOrClicked(within seconds: Double = 0.35) -> Bool {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        return types.contains { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < seconds }
    }

    private func handleTap(_ feature: TapFeature) {
        if config.ignoreWhileTyping && Self.userJustTypedOrClicked() { return }
        if let zoneID = calibratingZone {
            guard calibrationResult == nil else { return }  // result card is showing
            pendingCalibration.append(feature.vector)
            calibrationTaps = pendingCalibration.count
            flash(zoneID)
            if calibrationTaps >= calibrationTarget { finishZoneCalibration() }
            return
        }
        guard enabled else { return }
        guard let match = classifier.classify(feature.vector) else {
            log(.unmatched, "Tap did not match any zone")
            return
        }
        flash(match.zone)
        let z = zone(match.zone)
        fire(grouper.tap(zone: z.id, at: now, wantsDouble: z.doubleAction != .none))
        if grouper.isWaiting {
            DispatchQueue.main.asyncAfter(deadline: .now() + grouper.gap + 0.02) { [weak self] in
                guard let self else { return }
                self.fire(self.grouper.flush(at: self.now))
            }
        }
    }

    private func fire(_ gestures: [TapGrouper.Gesture]) {
        for gesture in gestures {
            let (z, action, name): (ZoneConfig, TapAction, String)
            switch gesture {
            case .single(let id): z = zone(id); action = z.action; name = z.name
            case .double(let id): z = zone(id); action = z.doubleAction; name = "\(z.name) ×2"
            }
            if testMode {
                log(.action, "\(name) → \(action.label)  (test mode)", zone: z.id)
            } else {
                run(action, from: name, zone: z.id)
            }
        }
    }

    func run(_ action: TapAction, from name: String, zone: String? = nil) {
        ActionRunner.run(action) { [weak self] error in
            if let error {
                self?.log(.error, "\(name): \(error)", zone: zone)
            } else {
                self?.log(.action, "\(name) → \(action.label)", zone: zone)
            }
        }
    }

    private func flash(_ id: String) {
        flashZone = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            if self?.flashZone == id { self?.flashZone = nil }
        }
    }

    func log(_ kind: TapEvent.Kind, _ text: String, zone: String? = nil) {
        events.insert(TapEvent(kind: kind, text: text, zoneID: zone), at: 0)
        if events.count > 100 { events.removeLast() }
    }

    // MARK: calibration

    func calibrate(_ zoneIDs: [String]) {
        guard let first = zoneIDs.first else { return }
        calibrationQueue = Array(zoneIDs.dropFirst())
        calibrationCount = zoneIDs.count
        calibrationIndex = 1
        beginZone(first)
    }

    private func beginZone(_ id: String) {
        pendingCalibration = []
        calibrationTaps = 0
        calibrationResult = nil
        calibratingZone = id
    }

    private func finishZoneCalibration() {
        guard let id = calibratingZone, var z = config.zones.first(where: { $0.id == id }) else { return }
        let kept = Classifier.pruneOutliers(pendingCalibration)
        z.samples = kept
        update(z)  // recomputes `quality`
        calibrationResult = CalibrationResult(
            zoneID: id, kept: kept.count, dropped: pendingCalibration.count - kept.count,
            accuracy: quality?.perZone[id],
            confusedWith: quality?.confusedWith[id].map { zone($0).name })
    }

    func redoCalibration() {
        if let id = calibratingZone { beginZone(id) }
    }

    func nextCalibration() {
        guard !calibrationQueue.isEmpty else { return endCalibration() }
        calibrationIndex += 1
        beginZone(calibrationQueue.removeFirst())
    }

    /// Stops calibrating. Zones finished so far keep their new taps; the current unfinished one keeps its old taps.
    func endCalibration() {
        calibratingZone = nil
        calibrationQueue = []
        calibrationResult = nil
        pendingCalibration = []
        calibrationTaps = 0
    }

    func clearCalibration(zoneIDs: [String]) {
        for id in zoneIDs {
            if var z = config.zones.first(where: { $0.id == id }) {
                z.samples = []
                update(z)
            }
        }
    }

    // MARK: helper, login item

    func installHelper() {
        helperBusy = true
        Helper.install { [weak self] in self?.helperDone($0, "Sensor helper installed. It now starts with your Mac.") }
    }

    func restartHelper() {
        helperBusy = true
        Helper.restart { [weak self] in self?.helperDone($0, "Sensor helper restarted.") }
    }

    func uninstallHelper() {
        helperBusy = true
        Helper.uninstall { [weak self] in self?.helperDone($0, "Sensor helper removed.") }
    }

    private func helperDone(_ error: String?, _ success: String) {
        helperBusy = false
        helperStatus = Helper.status
        if let error {
            log(.error, "Helper: \(error)")
            if error != "Cancelled." { notice = "Sensor helper: \(error)" }
        } else {
            log(.info, success)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            notice = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

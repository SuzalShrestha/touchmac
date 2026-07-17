import Foundation
import SwiftUI
import TouchMacCore

struct TapEvent: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig {
        didSet { config.save(); rebuild() }
    }
    @Published var enabled = true
    @Published var testMode = false
    @Published var sensorAlive = false
    @Published var helperStarting = false
    @Published var flashZone: String?
    @Published var events: [TapEvent] = []
    @Published var calibratingZone: String?
    @Published var calibrationTaps = 0
    let calibrationTarget = 10

    private let client = SensorClient()
    private let engine: TapEngine
    private var classifier: Classifier
    private var pendingCalibration: [[Double]] = []
    private var statusTimer: Timer?

    init() {
        let cfg = AppConfig.load()
        engine = TapEngine(thresholdG: cfg.thresholdG)
        classifier = Classifier(samplesByZone: Dictionary(uniqueKeysWithValues: cfg.zones.map { ($0.id, $0.samples) }),
                                maxDistance: cfg.maxDistance)
        config = cfg

        engine.onTap = { [weak self] feature in
            DispatchQueue.main.async { self?.handleTap(feature) }
        }
        client.onAccel = { [weak self] t, x, y, z in self?.engine.feedAccel(t: t, x: x, y: y, z: z) }
        client.onGyro = { [weak self] t, x, y, z in self?.engine.feedGyro(t: t, x: x, y: y, z: z) }
        client.start()

        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.sensorAlive = self.client.isAlive
            }
        }
    }

    private func rebuild() {
        engine.thresholdG = config.thresholdG
        classifier = Classifier(samplesByZone: Dictionary(uniqueKeysWithValues: config.zones.map { ($0.id, $0.samples) }),
                                maxDistance: config.maxDistance)
    }

    func zone(_ id: String) -> ZoneConfig {
        config.zones.first { $0.id == id } ?? ZoneConfig(id: id, name: id)
    }

    func update(_ zone: ZoneConfig) {
        if let i = config.zones.firstIndex(where: { $0.id == zone.id }) {
            config.zones[i] = zone
        }
    }

    // MARK: taps

    private func handleTap(_ feature: TapFeature) {
        if let zoneID = calibratingZone {
            pendingCalibration.append(feature.vector)
            calibrationTaps = pendingCalibration.count
            flash(zoneID)
            if calibrationTaps >= calibrationTarget { finishCalibration(save: true) }
            return
        }
        guard enabled else { return }
        guard let match = classifier.classify(feature.vector) else {
            log("Unmatched tap (no zone close enough)")
            return
        }
        let zone = zone(match.zone)
        flash(zone.id)
        log("\(zone.name)  d=\(String(format: "%.1f", match.distance))  →  \(zone.action.label)")
        if !testMode { ActionRunner.run(zone.action) }
    }

    private func flash(_ id: String) {
        flashZone = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            if self?.flashZone == id { self?.flashZone = nil }
        }
    }

    private func log(_ text: String) {
        events.insert(TapEvent(date: Date(), text: text), at: 0)
        if events.count > 6 { events.removeLast() }
    }

    // MARK: calibration

    func startCalibration(zoneID: String) {
        pendingCalibration = []
        calibrationTaps = 0
        calibratingZone = zoneID
    }

    func finishCalibration(save: Bool) {
        if save, let id = calibratingZone, var z = config.zones.first(where: { $0.id == id }) {
            z.samples = pendingCalibration
            update(z)
        }
        calibratingZone = nil
        pendingCalibration = []
        calibrationTaps = 0
    }

    func clearCalibration(zoneID: String) {
        if var z = config.zones.first(where: { $0.id == zoneID }) {
            z.samples = []
            update(z)
        }
    }

    // MARK: helper

    func startHelper() {
        helperStarting = true
        let helper = Bundle.main.executableURL!
            .deletingLastPathComponent()
            .appendingPathComponent("touchmacd").path
        let escaped = helper.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"'\(escaped)' >/var/log/touchmacd.log 2>&1 &\" with administrator privileges"
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async { self.helperStarting = false }
        }
    }
}

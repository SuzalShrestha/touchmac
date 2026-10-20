// Engine, classifier, gesture and config checks. No hardware needed.
// Run: swift run selftest   (and: swift run -c release selftest)
import Foundation
import TouchMacCore

// precondition, not assert: assert is compiled out of release builds
func check(_ ok: Bool, _ msg: @autoclosure () -> String) {
    precondition(ok, msg())
}

var clock = 0.0
let dt = 1.0 / 400

func feed(_ engine: TapEngine, seconds: Double, spikeX: Double = 0, spikeSamples: Int = 0, noise: Double = 0) {
    let n = Int(seconds * 400)
    for i in 0..<n {
        clock += dt
        let ax = (i < spikeSamples ? spikeX : 0) + (i % 2 == 0 ? noise : -noise)
        engine.feedAccel(t: clock, x: ax, y: 0, z: 1)
        engine.feedGyro(t: clock, x: 0, y: 0, z: 0)
    }
}

func run(_ name: String, _ body: () -> Void) {
    body()
    print("ok \(name)")
}

func tapCounter(_ engine: TapEngine) -> () -> Int {
    var count = 0
    engine.onTap = { _ in count += 1 }
    return { count }
}

run("onset_detection") {
    var taps: [[Double]] = []
    let engine = TapEngine(thresholdG: 0.04)
    engine.onTap = { taps.append($0.vector) }
    feed(engine, seconds: 1.0)
    feed(engine, seconds: 0.6, spikeX: 0.5, spikeSamples: 8)
    feed(engine, seconds: 0.6, spikeX: 0.01, spikeSamples: 8)  // sub-threshold
    check(taps.count == 1, "expected 1 tap, got \(taps.count)")
    check(taps[0].count == 7, "expected 7-dim feature")
    check(taps[0][0] > 0.9, "spike on +x should dominate: \(taps[0])")
}

run("refractory_and_double_tap_spacing") {
    let engine = TapEngine(thresholdG: 0.04)
    let count = tapCounter(engine)
    feed(engine, seconds: 1.0)
    feed(engine, seconds: 0.1, spikeX: 0.5, spikeSamples: 8)
    feed(engine, seconds: 0.1, spikeX: 0.5, spikeSamples: 8)  // 100 ms later: desk ringing, ignored
    feed(engine, seconds: 0.6)
    check(count() == 1, "refractory failed: \(count()) taps")
    feed(engine, seconds: 0.2, spikeX: 0.5, spikeSamples: 8)
    feed(engine, seconds: 0.6, spikeX: 0.5, spikeSamples: 8)  // 200 ms later: a real double tap
    check(count() == 3, "double tap spacing lost a tap: \(count())")
}

run("gyro_stall") {
    let engine = TapEngine(thresholdG: 0.04)
    let count = tapCounter(engine)
    for _ in 0..<400 { clock += dt; engine.feedAccel(t: clock, x: 0, y: 0, z: 1) }
    for i in 0..<400 { clock += dt; engine.feedAccel(t: clock, x: i < 8 ? 0.5 : 0, y: 0, z: 1) }
    check(count() == 1, "gyro stall killed detection: \(count())")
}

run("adaptive_threshold") {
    // quiet desk: a modest tap fires
    let quiet = TapEngine(thresholdG: 0.04)
    let quietCount = tapCounter(quiet)
    feed(quiet, seconds: 3)
    feed(quiet, seconds: 0.6, spikeX: 0.06, spikeSamples: 8)
    check(quietCount() == 1, "adaptive blocked a tap on a quiet desk")
    check(quiet.effectiveThreshold == 0.04, "quiet threshold should stay at the floor")

    // noisy desk (constant 0.02 g buzz): the bar rises, the same modest bump is ignored
    let noisy = TapEngine(thresholdG: 0.04)
    let noisyCount = tapCounter(noisy)
    feed(noisy, seconds: 6, noise: 0.02)
    check(noisy.effectiveThreshold > 0.08, "noise floor did not raise the bar: \(noisy.effectiveThreshold)")
    feed(noisy, seconds: 0.6, spikeX: 0.06, spikeSamples: 8, noise: 0.02)
    check(noisyCount() == 0, "bump inside noise fired: \(noisyCount())")
    feed(noisy, seconds: 0.6, spikeX: 0.5, spikeSamples: 8, noise: 0.02)
    check(noisyCount() == 1, "a firm tap must still fire in noise")

    // adaptive off: fixed bar
    let fixed = TapEngine(thresholdG: 0.04, adaptive: false)
    feed(fixed, seconds: 6, noise: 0.02)
    check(fixed.effectiveThreshold == 0.04, "adaptive=false must keep the fixed threshold")
}

run("classifier_synthetic") {
    func sample(_ dir: [Double], mag: Double) -> [Double] {
        let n = (dir.reduce(0) { $0 + $1 * $1 }).squareRoot()
        return dir.map { $0 / n } + [log10(mag)]
    }
    var zones: [String: [[Double]]] = [:]
    zones["L1"] = (0..<8).map { _ in sample([1, 0.1, 0, 0, 0.2, 0], mag: 0.30) }
    zones["L2"] = (0..<8).map { _ in sample([1, 0.1, 0, 0, 0.2, 0], mag: 0.06) }  // same direction, weaker = farther
    zones["R1"] = (0..<8).map { _ in sample([-1, 0.1, 0, 0, -0.2, 0], mag: 0.30) }
    let c = Classifier(samplesByZone: zones, maxDistance: 6.0)
    check(c.classify(sample([1, 0.1, 0, 0, 0.2, 0], mag: 0.28))?.zone == "L1", "L1")
    check(c.classify(sample([1, 0.1, 0, 0, 0.2, 0], mag: 0.07))?.zone == "L2", "L2")
    check(c.classify(sample([-1, 0.1, 0, 0, -0.2, 0], mag: 0.3))?.zone == "R1", "R1")
    check(c.classify(sample([0, 0, 1, 1, 0, 0], mag: 5.0)) == nil, "outlier should be rejected")
}

run("real_taps_m1pro") {
    guard let r = Classifier.crossValidate(fixtureM1Pro, maxDistance: 6.0) else { return check(false, "no report") }
    print(String(format: "   leave-one-out accuracy %.0f%%, worst zone %@", r.accuracy * 100,
                 r.perZone.min { $0.value < $1.value }.map { "\($0.key) \(Int($0.value * 100))%" } ?? "-"))
    check(r.accuracy >= 0.80, "accuracy regressed below the v0.1.0 baseline: \(r.accuracy)")
    check(r.confusedWith["R2"] == "F2", "known confusion R2->F2 not reported: \(r.confusedWith)")
    let pruned = fixtureM1Pro.mapValues { Classifier.pruneOutliers($0) }
    let rp = Classifier.crossValidate(pruned, maxDistance: 6.0)!
    print(String(format: "   after outlier pruning %.0f%% (%d of 60 taps kept)", rp.accuracy * 100,
                 pruned.values.reduce(0) { $0 + $1.count }))
    check(rp.accuracy >= r.accuracy, "pruning made real data worse")
}

run("prune_outliers") {
    let good = (0..<8).map { i in [1.0, 0.01 * Double(i), 0, 0, 0, 0, -1.0] }
    let slip = [0.0, 0, 1, 0, 0, 0, 0.5]  // a keystroke during calibration
    let kept = Classifier.pruneOutliers(good + [slip])
    check(kept.count == 8 && !kept.contains(slip), "outlier not removed: \(kept.count)")
    check(Classifier.pruneOutliers(Array(good.prefix(4)) + [slip]).count == 5, "sets at the 5-tap floor stay untouched")
}

run("tap_grouper") {
    var g = TapGrouper(gap: 0.45)
    check(g.tap(zone: "A", at: 0, wantsDouble: false) == [.single("A")], "no double action: fire at once")
    check(g.tap(zone: "B", at: 1, wantsDouble: true) == [], "double-capable zone waits")
    check(g.flush(at: 1.2) == [], "too early to flush")
    check(g.tap(zone: "B", at: 1.3, wantsDouble: true) == [.double("B")], "second tap -> double")
    check(g.tap(zone: "B", at: 2, wantsDouble: true) == [], "waits again")
    check(g.flush(at: 2.5) == [.single("B")], "gap expired -> single")
    _ = g.tap(zone: "B", at: 3, wantsDouble: true)
    check(g.tap(zone: "A", at: 3.1, wantsDouble: false) == [.single("B"), .single("A")], "other zone releases pending")
    check(!g.isWaiting, "nothing pending")
}

run("config_compat") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("touchmac-selftest-\(getpid())")
    try? FileManager.default.removeItem(at: dir)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("config.json")

    // v0.1.0 file: no adaptive/typing/doubleAction keys, one action from a future version
    let old = """
    {"thresholdG":0.05,"maxDistance":5,"zones":[
      {"id":"L1","name":"Left Near","action":{"openApp":{"_0":"/Applications/Safari.app"}},"samples":[[1,0,0,0,0,0,-1]]},
      {"id":"R1","name":"Right Near","action":{"teleport":{}},"samples":[[0,1,0,0,0,0,-1]]}]}
    """
    try! old.write(to: url, atomically: true, encoding: .utf8)
    let (cfg, warning) = AppConfig.load(from: url)
    check(warning == nil, "old file should load cleanly")
    check(cfg.thresholdG == 0.05 && cfg.adaptiveThreshold, "missing keys must take defaults")
    check(cfg.zones.first { $0.id == "L1" }?.samples.count == 1, "calibration lost on upgrade")
    check(cfg.zones.first { $0.id == "L1" }?.action == .openApp("/Applications/Safari.app"), "action lost")
    check(cfg.zones.first { $0.id == "R1" }?.action == TapAction.none, "unknown action must fall back to none")
    check(cfg.zones.first { $0.id == "R1" }?.samples.count == 1, "unknown action must not drop samples")
    check(cfg.zones.count == 6, "default zones must be merged in")

    // round trip
    var edited = cfg
    edited.zones[0].doubleAction = .shortcut("Focus")
    try! edited.save(to: url)
    check(AppConfig.load(from: url).0 == edited, "save/load round trip")

    // corrupt file: moved aside, never overwritten
    try! "{ not json".write(to: url, atomically: true, encoding: .utf8)
    let (fresh, warn2) = AppConfig.load(from: url)
    check(warn2 != nil && fresh == AppConfig(), "corrupt file should warn and use defaults")
    let names = try! FileManager.default.contentsOfDirectory(atPath: dir.path)
    check(names.contains { $0.hasPrefix("config.broken-") }, "corrupt file was not backed up: \(names)")
}

run("action_kind_round_trip") {
    for kind in TapAction.Kind.allCases {
        let a = TapAction(kind: kind, text: "x")
        check(a.kind == kind, "kind round trip failed for \(kind)")
    }
    check(TapAction(kind: .shell, text: "  ") == TapAction.none, "empty text must give none")
}

run("sensor_wire") {
    var buf = [UInt8](repeating: 0, count: 3 * SensorWire.recordLen)
    let sent: [(UInt8, Double, Double, Double, Double)] = [(0, 0.010, 0.5, -0.25, 1.0), (1, 0.005, 12.5, 0, -3), (0, 0, 0, 0, 1)]
    buf.withUnsafeMutableBytes { raw in
        for (i, s) in sent.enumerated() {
            SensorWire.write(kind: s.0, x: s.2, y: s.3, z: s.4, into: raw, at: i * SensorWire.recordLen)
            SensorWire.stampAge(s.1, into: raw, at: i * SensorWire.recordLen)
        }
    }
    var got: [(UInt8, Double, Double, Double, Double)] = []
    buf.withUnsafeBytes { SensorWire.decode($0, count: buf.count, now: 100) { got.append(($0, $1, $2, $3, $4)) } }
    check(got.count == 3, "batch size: \(got.count)")
    for (s, g) in zip(sent, got) {
        check(s.0 == g.0 && abs(100 - s.1 - g.1) < 1e-6 && abs(s.2 - g.2) < 1e-6 && abs(s.3 - g.3) < 1e-6 && abs(s.4 - g.4) < 1e-6,
              "round trip mismatch: \(s) vs \(g)")
    }
    check(got[0].1 < got[1].1 && got[1].1 < got[2].1, "older samples must get earlier times")
    // a stream read can end mid-record: only whole records are decoded
    var partial = 0
    buf.withUnsafeBytes { SensorWire.decode($0, count: SensorWire.recordLen + 9, now: 0) { _, _, _, _, _ in partial += 1 } }
    check(partial == 1, "half a record must not be decoded: \(partial)")
}

print("all pass")

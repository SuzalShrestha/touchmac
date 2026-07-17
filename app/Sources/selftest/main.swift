// Synthetic-stream checks for TapEngine + Classifier. Run: swift run selftest
import Foundation
import TouchMacCore

var clock = 0.0
let dt = 1.0 / 400

func feed(_ engine: TapEngine, seconds: Double, spikeX: Double = 0, spikeSamples: Int = 0) {
    let n = Int(seconds * 400)
    for i in 0..<n {
        clock += dt
        let ax = i < spikeSamples ? spikeX : 0
        engine.feedAccel(t: clock, x: ax, y: 0, z: 1)
        engine.feedGyro(t: clock, x: 0, y: 0, z: 0)
    }
}

func run(_ name: String, _ body: () -> Void) {
    body()
    print("ok \(name)")
}

// -- 1. taps above threshold detected, below ignored
run("onset_detection") {
    var taps: [[Double]] = []
    let engine = TapEngine(thresholdG: 0.04)
    engine.onTap = { taps.append($0.vector) }
    feed(engine, seconds: 1.0)
    taps = []
    feed(engine, seconds: 0.6, spikeX: 0.5, spikeSamples: 8)
    feed(engine, seconds: 0.6, spikeX: 0.01, spikeSamples: 8)  // sub-threshold
    assert(taps.count == 1, "expected 1 tap, got \(taps.count)")
    assert(taps[0].count == 7, "expected 7-dim feature")
    assert(taps[0][0] > 0.9, "spike on +x should dominate: \(taps[0])")
}

// -- 2. refractory suppresses ringing
run("refractory") {
    var taps: [[Double]] = []
    let engine = TapEngine(thresholdG: 0.04)
    engine.onTap = { taps.append($0.vector) }
    feed(engine, seconds: 1.0)
    taps = []
    feed(engine, seconds: 0.1, spikeX: 0.5, spikeSamples: 8)
    feed(engine, seconds: 0.1, spikeX: 0.5, spikeSamples: 8)  // 100ms later: inside refractory
    feed(engine, seconds: 0.6)
    assert(taps.count == 1, "refractory failed: \(taps.count) taps")
}

// -- 3. gyro stream dead: still detects (fallback)
run("gyro_stall") {
    var taps: [[Double]] = []
    let engine = TapEngine(thresholdG: 0.04)
    engine.onTap = { taps.append($0.vector) }
    for _ in 0..<400 { clock += dt; engine.feedAccel(t: clock, x: 0, y: 0, z: 1) }
    taps = []
    for i in 0..<400 { clock += dt; engine.feedAccel(t: clock, x: i < 8 ? 0.5 : 0, y: 0, z: 1) }
    assert(taps.count == 1, "gyro stall killed detection: \(taps.count)")
}

// -- 4. classifier separates zones, includes magnitude dim, rejects outliers
run("classifier") {
    func sample(_ dir: [Double], mag: Double) -> [Double] {
        let n = (dir.reduce(0) { $0 + $1 * $1 }).squareRoot()
        return dir.map { $0 / n } + [log10(mag)]
    }
    var zones: [String: [[Double]]] = [:]
    zones["L1"] = (0..<8).map { _ in sample([1, 0.1, 0, 0, 0.2, 0], mag: 0.30) }
    zones["L2"] = (0..<8).map { _ in sample([1, 0.1, 0, 0, 0.2, 0], mag: 0.06) }  // same direction, weaker = farther
    zones["R1"] = (0..<8).map { _ in sample([-1, 0.1, 0, 0, -0.2, 0], mag: 0.30) }
    let c = Classifier(samplesByZone: zones, maxDistance: 6.0)
    assert(c.classify(sample([1, 0.1, 0, 0, 0.2, 0], mag: 0.28))?.zone == "L1")
    assert(c.classify(sample([1, 0.1, 0, 0, 0.2, 0], mag: 0.07))?.zone == "L2")
    assert(c.classify(sample([-1, 0.1, 0, 0, -0.2, 0], mag: 0.3))?.zone == "R1")
    assert(c.classify(sample([0, 0, 1, 1, 0, 0], mag: 5.0)) == nil, "outlier should be rejected")
}

print("all pass")

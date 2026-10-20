import Foundation

/// One raw tap: 6 normalized impulse sums (ax,ay,az,gx,gy,gz) + log10 peak accel magnitude.
public struct TapFeature {
    public let vector: [Double]
    public init(vector: [Double]) { self.vector = vector }
}

/// Turns a time-stamped accel/gyro stream into tap features.
/// All timing is wall-clock seconds so the engine is rate-independent and testable.
/// Not thread-safe: feed and configure it from one queue.
public final class TapEngine {
    public var onTap: ((TapFeature) -> Void)?
    public var thresholdG: Double
    /// Raise the onset threshold above `thresholdG` while background vibration is high
    /// (typing, fans, a moving train). It never drops below `thresholdG`.
    public var adaptive: Bool
    public var noiseFactor = 6.0
    public let windowSec = 0.06
    /// Long enough to swallow desk ringing, short enough for a double tap.
    public let refractorySec = 0.15
    private let gravityTau = 0.15
    private let noiseTau = 2.0

    /// Slow average of the dynamic magnitude between taps.
    public private(set) var noiseFloor = 0.0
    private var peakSinceRead = 0.0

    private var gravity: (x: Double, y: Double, z: Double)?
    private var lastAccelT = 0.0
    private var onsetT: Double?
    private var lastFireOnset = -1e9
    private var sums = [Double](repeating: 0, count: 6)
    private var peak = 0.0
    private var accelDone = false
    private var gyroDone = false

    public init(thresholdG: Double = 0.04, adaptive: Bool = true) {
        self.thresholdG = thresholdG
        self.adaptive = adaptive
    }

    public var effectiveThreshold: Double {
        adaptive ? max(thresholdG, noiseFactor * noiseFloor) : thresholdG
    }

    /// Highest dynamic magnitude since the previous call (for a live meter).
    public func readPeak() -> Double {
        defer { peakSinceRead = 0 }
        return peakSinceRead
    }

    public func feedAccel(t: Double, x: Double, y: Double, z: Double) {
        guard var g = gravity else {
            gravity = (x, y, z)
            lastAccelT = t
            return
        }
        let dt = min(max(t - lastAccelT, 1e-4), 0.1)
        lastAccelT = t
        // hold gravity still during a tap and its ringing, or the tap leaks into the
        // estimate and its slow recovery reads as a second, phantom tap
        if onsetT == nil && t - lastFireOnset > refractorySec {
            let a = dt / (gravityTau + dt)
            g = (g.x + a * (x - g.x), g.y + a * (y - g.y), g.z + a * (z - g.z))
            gravity = g
        }
        let dx = x - g.x, dy = y - g.y, dz = z - g.z
        let mag = (dx * dx + dy * dy + dz * dz).squareRoot()
        peakSinceRead = max(peakSinceRead, mag)

        if let onset = onsetT {
            if t <= onset + windowSec {
                sums[0] += dx; sums[1] += dy; sums[2] += dz
                peak = max(peak, mag)
            } else {
                accelDone = true
            }
            maybeFinish(t)
        } else if mag > effectiveThreshold, t - lastFireOnset > refractorySec {
            onsetT = t
            accelDone = false
            gyroDone = false
            sums = [dx, dy, dz, 0, 0, 0]
            peak = mag
        } else if t - lastFireOnset > refractorySec + windowSec {
            // learn the background only between taps, so a tap never raises its own bar
            noiseFloor += dt / (noiseTau + dt) * (mag - noiseFloor)
        }
    }

    public func feedGyro(t: Double, x: Double, y: Double, z: Double) {
        guard let onset = onsetT else { return }
        if t <= onset + windowSec {
            sums[3] += x; sums[4] += y; sums[5] += z
        } else {
            gyroDone = true
            maybeFinish(t)
        }
    }

    private func maybeFinish(_ t: Double) {
        guard let onset = onsetT, accelDone else { return }
        // gyro stream stalled or absent: finish on accel alone rather than dying silently
        guard gyroDone || t > onset + 2 * windowSec else { return }
        onsetT = nil
        lastFireOnset = onset
        var v = sums
        let norm = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm > 0 { v = v.map { $0 / norm } }
        v.append(log10(max(peak, 1e-6)))
        onTap?(TapFeature(vector: v))
    }
}

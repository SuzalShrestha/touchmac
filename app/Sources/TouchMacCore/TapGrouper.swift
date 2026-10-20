/// Turns matched taps into single / double gestures.
/// A zone without a double-tap action fires at once; otherwise its single tap
/// waits `gap` seconds for a second tap on the same zone.
public struct TapGrouper {
    public enum Gesture: Equatable {
        case single(String)
        case double(String)
    }

    public var gap: Double
    private var pending: (zone: String, t: Double)?

    public init(gap: Double = 0.45) { self.gap = gap }

    public var isWaiting: Bool { pending != nil }

    public mutating func tap(zone: String, at t: Double, wantsDouble: Bool) -> [Gesture] {
        var out: [Gesture] = []
        if let p = pending {
            pending = nil
            if p.zone == zone && t - p.t <= gap { return [.double(zone)] }
            out.append(.single(p.zone))
        }
        if wantsDouble { pending = (zone, t) } else { out.append(.single(zone)) }
        return out
    }

    /// Call once `gap` has passed since the last tap: releases the waiting single tap.
    public mutating func flush(at t: Double) -> [Gesture] {
        guard let p = pending, t - p.t >= gap else { return [] }
        pending = nil
        return [.single(p.zone)]
    }
}

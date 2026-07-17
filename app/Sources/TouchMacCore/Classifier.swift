import Foundation

/// k-NN over calibration samples, dims z-scored across the whole training set.
/// The 7th dim (log peak magnitude) is what separates near/far pads on the same side.
public struct Classifier {
    public struct Match {
        public let zone: String
        public let distance: Double  // mean z-scored euclidean distance of winning neighbors
    }

    public var samplesByZone: [String: [[Double]]]
    public var maxDistance: Double

    public init(samplesByZone: [String: [[Double]]], maxDistance: Double = 6.0) {
        self.samplesByZone = samplesByZone
        self.maxDistance = maxDistance
    }

    public func classify(_ feature: [Double]) -> Match? {
        let labeled: [(zone: String, s: [Double])] = samplesByZone.flatMap { zone, list in
            list.filter { $0.count == feature.count }.map { (zone, $0) }
        }
        guard !labeled.isEmpty else { return nil }

        let dims = feature.count
        var std = [Double](repeating: 0, count: dims)
        let all = labeled.map(\.s)
        for d in 0..<dims {
            let vals = all.map { $0[d] }
            let mean = vals.reduce(0, +) / Double(vals.count)
            let varsum = vals.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            std[d] = max((varsum / Double(vals.count)).squareRoot(), 1e-3)
        }

        func dist(_ a: [Double], _ b: [Double]) -> Double {
            var s = 0.0
            for d in 0..<dims {
                let diff = (a[d] - b[d]) / std[d]
                s += diff * diff
            }
            return s.squareRoot()
        }

        let ranked = labeled
            .map { (zone: $0.zone, d: dist(feature, $0.s)) }
            .sorted { $0.d < $1.d }
        let k = min(3, ranked.count)
        let top = ranked.prefix(k)
        var votes: [String: Int] = [:]
        for n in top { votes[n.zone, default: 0] += 1 }
        let winner = votes.max { a, b in
            a.value != b.value ? a.value < b.value
                : top.first(where: { $0.zone == a.key })!.d > top.first(where: { $0.zone == b.key })!.d
        }!.key
        let winnerDists = top.filter { $0.zone == winner }.map(\.d)
        let score = winnerDists.reduce(0, +) / Double(winnerDists.count)
        return score <= maxDistance ? Match(zone: winner, distance: score) : nil
    }
}

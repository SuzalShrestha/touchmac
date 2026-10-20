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
        for d in 0..<dims {
            let vals = labeled.map { $0.s[d] }
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

        let top = labeled
            .map { (zone: $0.zone, d: dist(feature, $0.s)) }
            .sorted { $0.d < $1.d }
            .prefix(3)
        // most votes wins; a tie goes to the zone with the nearest single neighbor
        var votes: [String: (n: Int, nearest: Double)] = [:]
        for n in top {
            let v = votes[n.zone] ?? (0, n.d)
            votes[n.zone] = (v.n + 1, min(v.nearest, n.d))
        }
        guard let winner = votes.max(by: { a, b in
            a.value.n != b.value.n ? a.value.n < b.value.n : a.value.nearest > b.value.nearest
        })?.key else { return nil }
        let winnerDists = top.filter { $0.zone == winner }.map(\.d)
        let score = winnerDists.reduce(0, +) / Double(winnerDists.count)
        return score <= maxDistance ? Match(zone: winner, distance: score) : nil
    }

    // MARK: calibration quality

    public struct Report {
        /// Share of calibration taps a leave-one-out test puts back in their own zone (0...1).
        public let accuracy: Double
        public let perZone: [String: Double]
        /// For each zone, the zone its taps are most often mistaken for.
        public let confusedWith: [String: String]
    }

    /// Leave-one-out test: classify every calibration tap against all the others.
    /// A rejected tap counts as a miss.
    public static func crossValidate(_ samplesByZone: [String: [[Double]]], maxDistance: Double) -> Report? {
        var hits: [String: Int] = [:]
        var wrong: [String: [String: Int]] = [:]
        var total = 0, correct = 0
        for (zone, list) in samplesByZone {
            for i in list.indices {
                var train = samplesByZone
                train[zone]!.remove(at: i)
                let got = Classifier(samplesByZone: train, maxDistance: maxDistance).classify(list[i])?.zone
                total += 1
                if got == zone {
                    correct += 1
                    hits[zone, default: 0] += 1
                } else if let got {
                    wrong[zone, default: [:]][got, default: 0] += 1
                }
            }
        }
        guard total > 0 else { return nil }
        var accuracyByZone: [String: Double] = [:]
        for (zone, list) in samplesByZone where !list.isEmpty {
            accuracyByZone[zone] = Double(hits[zone, default: 0]) / Double(list.count)
        }
        let confused = wrong.compactMapValues { $0.max { $0.value < $1.value }?.key }
        return Report(accuracy: Double(correct) / Double(total), perZone: accuracyByZone, confusedWith: confused)
    }

    /// Drops calibration taps far from the rest of their zone (a keystroke or a slip).
    /// A tap is an outlier when its median distance to the others is over 2.5x the typical one.
    public static func pruneOutliers(_ samples: [[Double]], keepAtLeast: Int = 5) -> [[Double]] {
        guard samples.count > keepAtLeast else { return samples }
        func median(_ v: [Double]) -> Double {
            let s = v.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        func dist(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
        }
        let scores = samples.indices.map { i in
            median(samples.indices.filter { $0 != i }.map { dist(samples[i], samples[$0]) })
        }
        let cutoff = 2.5 * median(scores)
        guard cutoff > 0 else { return samples }
        let ranked = samples.indices.sorted { scores[$0] < scores[$1] }
        let keep = max(keepAtLeast, ranked.filter { scores[$0] <= cutoff }.count)
        return ranked.prefix(keep).sorted().map { samples[$0] }
    }
}

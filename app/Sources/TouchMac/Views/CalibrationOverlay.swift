import SwiftUI

struct CalibrationOverlay: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.45))
            Group {
                if let result = state.calibrationResult {
                    ResultCard(result: result)
                } else {
                    progressCard
                }
            }
            .padding(28)
            .frame(width: 400)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        }
        .ignoresSafeArea()
    }

    private var zoneName: String { state.calibratingZone.map { state.zone($0).name } ?? "" }
    private var progress: Double { Double(state.calibrationTaps) / Double(state.calibrationTarget) }

    private var progressCard: some View {
        VStack(spacing: 18) {
            if state.calibrationCount > 1 {
                Text("Zone \(state.calibrationIndex) of \(state.calibrationCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            DeskMiniMap(active: state.calibratingZone)
                .frame(width: 180, height: 110)

            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: progress)
                // ripple on each counted tap
                Circle()
                    .stroke(Color.accentColor.opacity(state.flashZone == nil ? 0 : 0.6), lineWidth: 3)
                    .scaleEffect(state.flashZone == nil ? 0.7 : 1.35)
                    .animation(state.flashZone == nil ? nil : .easeOut(duration: 0.4), value: state.flashZone)
                Text("\(state.calibrationTaps)/\(state.calibrationTarget)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 6) {
                Text("Tap \(zoneName)")
                    .font(.title3.bold())
                Text("Tap the same spot about once a second, with your everyday strength. Keep your hands off the keyboard and trackpad.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if state.calibrationTaps > 0 {
                    Button("Start Over") { state.redoCalibration() }
                }
                Button("Cancel") { state.endCalibration() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calibrating \(zoneName), \(state.calibrationTaps) of \(state.calibrationTarget) taps")
    }
}

private struct ResultCard: View {
    @Environment(AppState.self) private var state
    let result: CalibrationResult

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
            Text("\(state.zone(result.zoneID).name) calibrated")
                .font(.title3.bold())
            VStack(spacing: 6) {
                Text("\(result.kept) taps saved" + (result.dropped > 0 ? " · \(result.dropped) stray tap\(result.dropped == 1 ? "" : "s") removed" : ""))
                    .foregroundStyle(.secondary)
                if let accuracy = result.accuracy {
                    Text("\(Int((accuracy * 100).rounded()))% of these taps are recognized as this zone")
                        .foregroundStyle(qualityColor(accuracy))
                        .fontWeight(.medium)
                }
                if let other = result.confusedWith, (result.accuracy ?? 1) < 0.9 {
                    Text("It feels similar to \(other). Move the two spots further apart, or tap with a steadier strength, then calibrate again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Redo") { state.redoCalibration() }
                Button(state.calibrationQueue.isEmpty ? "Done" : "Next Zone") { state.nextCalibration() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var color: Color { result.accuracy.map(qualityColor) ?? .green }
    private var icon: String {
        guard let a = result.accuracy else { return "checkmark.circle.fill" }
        return a >= 0.9 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }
}

/// Tiny top-down desk map that highlights one zone.
struct DeskMiniMap: View {
    let active: String?
    static let spots: [String: CGPoint] = [
        "L2": CGPoint(x: 0.06, y: 0.22), "L1": CGPoint(x: 0.06, y: 0.62),
        "R2": CGPoint(x: 0.94, y: 0.22), "R1": CGPoint(x: 0.94, y: 0.62),
        "F1": CGPoint(x: 0.38, y: 0.93), "F2": CGPoint(x: 0.62, y: 0.93),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.secondary.opacity(0.35))
                    .frame(width: w * 0.62, height: h * 0.66)
                    .position(x: w / 2, y: h * 0.4)
                ForEach(Self.spots.sorted { $0.key < $1.key }, id: \.key) { id, p in
                    Circle()
                        .fill(id == active ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: id == active ? 16 : 10)
                        .shadow(color: id == active ? Color.accentColor : .clear, radius: 6)
                        .position(x: p.x * w, y: p.y * h)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

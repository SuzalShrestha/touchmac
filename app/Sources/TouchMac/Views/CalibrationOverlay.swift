import SwiftUI

/// Calibration: the camera moves in on the zone, and the ten dots around its spot fill as you tap.
struct CalibrationOverlay: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.5))
            HStack(spacing: 0) {
                DeskStage(focus: state.calibratingZone, showsLabels: false)
                    .frame(width: 420)
                    .padding(14)
                Group {
                    if let result = state.calibrationResult {
                        ResultPanel(result: result)
                    } else {
                        progressPanel
                    }
                }
                .frame(width: 300, alignment: .leading)
                .padding(.vertical, 24)
                .padding(.trailing, 26)
                .padding(.leading, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.hairline))
            .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
        }
        .ignoresSafeArea()
    }

    private var zoneID: String { state.calibratingZone ?? "" }
    private var zoneName: String { state.zone(zoneID).name }

    private var progressPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepTrack(index: state.calibrationIndex, count: state.calibrationCount, hue: Color.zone(zoneID))
            VStack(alignment: .leading, spacing: 4) {
                Text("Tap \(zoneName)").font(.display(22)).foregroundStyle(Color.ink)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(state.calibrationTaps)")
                        .font(.display(54, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.zone(zoneID))
                    Text("of \(state.calibrationTarget) taps").font(.title3).foregroundStyle(.secondary)
                }
                .animation(.snappy, value: state.calibrationTaps)
            }
            Text("Tap the same spot about once a second, with your everyday strength. Keep your hands off the keyboard and trackpad.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Button("Cancel") { state.endCalibration() }
                    .buttonStyle(.inkQuiet)
                    .keyboardShortcut(.cancelAction)
                if state.calibrationTaps > 0 {
                    Button("Start Over") { state.redoCalibration() }.buttonStyle(.inkQuiet)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calibrating \(zoneName), \(state.calibrationTaps) of \(state.calibrationTarget) taps")
    }
}

/// Where this zone sits in the run: one segment per zone.
private struct StepTrack: View {
    let index: Int
    let count: Int
    let hue: Color

    var body: some View {
        if count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Zone \(index) of \(count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(1...count, id: \.self) { i in
                        Capsule()
                            .fill(i < index ? Color.ink.opacity(0.7) : i == index ? hue : Color.ink.opacity(0.12))
                            .frame(height: 4)
                    }
                }
            }
        }
    }
}

private struct ResultPanel: View {
    @Environment(AppState.self) private var state
    let result: CalibrationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
            Text("\(state.zone(result.zoneID).name) calibrated").font(.display(20)).foregroundStyle(Color.ink)
            VStack(alignment: .leading, spacing: 6) {
                if let accuracy = result.accuracy {
                    Text("\(Int((accuracy * 100).rounded()))% of these taps are recognized as this zone.")
                        .foregroundStyle(qualityColor(accuracy))
                        .fontWeight(.medium)
                }
                Text(
                    "\(result.kept) taps saved"
                        + (result.dropped > 0 ? ", \(result.dropped) stray tap\(result.dropped == 1 ? "" : "s") removed." : ".")
                )
                .foregroundStyle(.secondary)
                if let other = result.confusedWith, (result.accuracy ?? 1) < 0.9 {
                    Text("It feels like \(other). Move the two spots further apart, or tap with a steadier strength, then calibrate again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button("Redo") { state.redoCalibration() }.buttonStyle(.inkQuiet)
                Button(state.calibrationQueue.isEmpty ? "Done" : "Next Zone") { state.nextCalibration() }
                    .buttonStyle(.ink)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var color: Color { result.accuracy.map(qualityColor) ?? .live }
    private var icon: String {
        guard let a = result.accuracy else { return "checkmark.circle.fill" }
        return a >= 0.9 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }
}

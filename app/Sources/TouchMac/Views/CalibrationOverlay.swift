import SwiftUI

struct CalibrationOverlay: View {
    @EnvironmentObject var state: AppState

    private var zoneName: String {
        state.calibratingZone.map { state.zone($0).name } ?? ""
    }
    private var progress: Double {
        Double(state.calibrationTaps) / Double(state.calibrationTarget)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55))
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.2), value: progress)
                    Text("\(state.calibrationTaps)/\(state.calibrationTarget)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 130, height: 130)

                Text("Tap the desk: \(zoneName)")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Tap the same spot on your desk, about once per second.\nUse the strength you'll use day to day.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))

                Button("Cancel") { state.finishCalibration(save: false) }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(40)
        }
        .ignoresSafeArea()
    }
}

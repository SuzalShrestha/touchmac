import SwiftUI

/// First-run guide: hardware check → helper → permissions → calibration.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    let done: () -> Void
    @State private var step = 0
    @State private var permissionTick = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .padding([.horizontal, .top], 28)

            Group {
                switch step {
                case 0: welcome
                case 1: helper
                case 2: permissions
                default: calibrate
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))

            HStack {
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                }
                Spacer()
                footerButtons
            }
            .padding(20)
        }
        .frame(width: 560, height: 480)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionTick += 1
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch step {
        case 0:
            if state.hardwarePresent {
                Button("Continue") { withAnimation { step = 1 } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            } else {
                Button("Close", action: done).keyboardShortcut(.defaultAction)
            }
        case 1:
            Button(state.sensorAlive ? "Continue" : "Skip for Now") { withAnimation { step = 2 } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(state.sensorAlive ? .accentColor : .secondary)
        case 2:
            Button("Continue") { withAnimation { step = 3 } }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        default:
            if state.sensorAlive {
                Button("Later", action: done)
                Button("Start Calibration") {
                    done()
                    state.calibrate(["L2", "L1", "R2", "R1", "F1", "F2"])
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            } else {
                Button("Finish", action: done).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)
            Text("Welcome to TouchMac").font(.largeTitle.bold())
            Text("Tap the desk beside your MacBook to open apps, take screenshots, control music and more. TouchMac reads the motion sensor that is already inside your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            CheckRow(ok: state.hardwarePresent,
                     title: state.hardwarePresent ? "Motion sensor found" : "Motion sensor not found",
                     detail: state.hardwarePresent ? "This Mac is supported." :
                        "TouchMac needs an Apple Silicon MacBook Pro that exposes the SPU accelerometer. It cannot work on this Mac.")
                .padding(.top, 8)
        }
    }

    private var helper: some View {
        VStack(spacing: 16) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Install the sensor helper").font(.title.bold())
            Text("macOS lets only the system read the motion sensor. A small helper does this for TouchMac. It starts with your Mac and only sends motion data. It never runs your actions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if state.sensorAlive {
                CheckRow(ok: true, title: "Sensor live", detail: "Data is arriving. You are ready.")
            } else if state.helperStatus == .installed {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the sensor…").foregroundStyle(.secondary)
                }
            } else {
                Button {
                    state.installHelper()
                } label: {
                    Label("Install Helper", systemImage: "lock.shield")
                        .padding(.horizontal, 8)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(state.helperBusy)
                Text("You enter your password once.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var permissions: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Optional permissions").font(.title.bold())
            Text("Grant these only if you plan to use the actions that need them. You can do this later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ForEach(Permission.allCases) { p in
                    HStack {
                        CheckRow(ok: p.granted, title: p.title, detail: p.purpose)
                        if !p.granted { Button("Grant…") { p.request() } }
                    }
                }
            }
            .id(permissionTick)
        }
    }

    private var calibrate: some View {
        VStack(spacing: 16) {
            DeskMiniMap(active: nil)
                .frame(width: 220, height: 130)
            Text("Teach TouchMac your desk").font(.title.bold())
            Text("You tap each of the six spots 10 times. TouchMac learns how each spot feels and shows how well it can tell them apart. It takes about two minutes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !state.sensorAlive {
                Text("Install the sensor helper first. You can calibrate later from the Desk page.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct CheckRow: View {
    let ok: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

import SwiftUI

/// First-run guide: hardware check → helper → permissions → calibration.
/// Each step opens with a picture: the rendered desk, then flat isometric drawings.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    let done: () -> Void
    @State private var step: Int
    @State private var permissionTick = 0

    init(done: @escaping () -> Void, startAt step: Int = 0) {
        self.done = done
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .background(Color.canvas)
                .clipped()
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }

            VStack(alignment: .leading, spacing: 14) {
                switch step {
                case 0: welcome
                case 1: helper
                case 2: permissions
                default: calibrate
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(step)
            // the old step leaves at once, so two steps never overlap
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .identity))

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(0..<4) { i in
                        Capsule()
                            .fill(i == step ? Color.ink : Color.ink.opacity(0.18))
                            .frame(width: i == step ? 18 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: step)
                .accessibilityLabel("Step \(step + 1) of 4")
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }.buttonStyle(.inkQuiet)
                }
                footerButtons
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(width: 640, height: 590)
        .background(Color.surface)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionTick += 1
        }
    }

    @ViewBuilder
    private var hero: some View {
        switch step {
        case 0: DeskPicture()
        case 1: SensorIllustration()
        case 2: PermissionIllustration()
        default: DeskIllustration(rippling: "R1", tapDots: 6)
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch step {
        case 0:
            if state.hardwarePresent {
                Button("Continue") { withAnimation { step = 1 } }
                    .buttonStyle(.ink).keyboardShortcut(.defaultAction)
            } else {
                Button("Close", action: done).buttonStyle(.ink).keyboardShortcut(.defaultAction)
            }
        case 1:
            Button(state.sensorAlive ? "Continue" : "Skip for Now") { withAnimation { step = 2 } }
                .buttonStyle(InkButtonStyle(prominent: state.sensorAlive))
                .keyboardShortcut(.defaultAction)
        case 2:
            Button("Continue") { withAnimation { step = 3 } }
                .buttonStyle(.ink).keyboardShortcut(.defaultAction)
        default:
            if state.sensorAlive {
                Button("Later", action: done).buttonStyle(.inkQuiet)
                Button("Start Calibration") {
                    done()
                    state.calibrate(calibrationOrder)
                }
                .buttonStyle(.ink).keyboardShortcut(.defaultAction)
            } else {
                Button("Finish", action: done).buttonStyle(.ink).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func heading(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.display(26)).foregroundStyle(Color.ink)
            Text(body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    @ViewBuilder
    private var welcome: some View {
        heading(
            "Your desk becomes six buttons",
            "Tap the table beside your MacBook to open apps, take screenshots or control music. TouchMac reads the motion sensor that is already inside your Mac."
        )
        CheckRow(
            ok: state.hardwarePresent,
            title: state.hardwarePresent ? "Motion sensor found" : "Motion sensor not found",
            detail: state.hardwarePresent
                ? "This Mac is supported." : "TouchMac needs an Apple Silicon MacBook that exposes the SPU accelerometer. It cannot work on this Mac."
        )
    }

    @ViewBuilder
    private var helper: some View {
        heading(
            "Install the sensor helper",
            "macOS lets only the system read the motion sensor. A small helper does this for TouchMac. It starts with your Mac and only sends motion data. It never runs your actions."
        )
        if state.sensorAlive {
            CheckRow(ok: true, title: "Sensor live", detail: "Data is arriving. You are ready.")
        } else if state.helperStatus == .installed {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for the sensor…").foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 12) {
                Button {
                    state.installHelper()
                } label: {
                    Label("Install Helper", systemImage: "lock.shield")
                }
                .buttonStyle(.ink)
                .disabled(state.helperBusy)
                Text("You enter your password once.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var permissions: some View {
        heading(
            "Optional permissions",
            "Grant these only if you plan to use the actions that need them. You can do this later in Settings.")
        VStack(spacing: 8) {
            ForEach(Permission.allCases) { p in
                CheckRow(ok: p.granted, title: p.title, detail: p.purpose) {
                    if !p.granted { Button("Grant…") { p.request() }.buttonStyle(.inkQuiet) }
                }
            }
        }
        .id(permissionTick)
    }

    @ViewBuilder
    private var calibrate: some View {
        heading(
            "Teach TouchMac your desk",
            "Tap each of the six spots 10 times. TouchMac learns how each spot feels and shows how well it can tell them apart. It takes about two minutes."
        )
        if !state.sensorAlive {
            Label("Install the sensor helper first. You can calibrate later from the Desk page.", systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }
}

struct CheckRow<Trailing: View>: View {
    let ok: Bool
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Color.live : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(12)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
    }
}

extension CheckRow where Trailing == EmptyView {
    init(ok: Bool, title: String, detail: String) {
        self.init(ok: ok, title: title, detail: detail) { EmptyView() }
    }
}

/// The rendered desk, filling its frame (no overlays).
struct DeskPicture: View {
    @Environment(\.colorScheme) private var scheme
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image = DeskRender.cached(dark: scheme == .dark)?.nsImage ?? image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            }
        }
        .task(id: scheme) { image = await DeskRender.output(dark: scheme == .dark)?.nsImage }
        .accessibilityHidden(true)
    }
}

import SwiftUI
import TouchMacCore

enum Page: String, CaseIterable, Identifiable {
    case desk = "Desk"
    case sensitivity = "Sensitivity"
    case activity = "Activity"
    case settings = "Settings"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .desk: return "hand.tap"
        case .sensitivity: return "waveform.path.ecg"
        case .activity: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("openWindowAtLaunch") private var openWindowAtLaunch = true
    @State private var page: Page?
    @State private var editingZone: ZoneConfig?

    init(page: Page = .desk) {
        _page = State(initialValue: page)
    }

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.rawValue, systemImage: p.symbol)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 250)
            .safeAreaInset(edge: .bottom) {
                SensorStatusView().padding(12)
            }
        } detail: {
            VStack(spacing: 0) {
                if let notice = state.notice {
                    NoticeBar(text: notice) { state.notice = nil }
                }
                switch page ?? .desk {
                case .desk: DeskView(edit: { editingZone = $0 }, goToSettings: { page = .settings })
                case .sensitivity: SensitivityView()
                case .activity: ActivityView()
                case .settings: SettingsView(showWelcome: { onboarded = false })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.canvas)
            .navigationTitle(page?.rawValue ?? "TouchMac")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $state.testMode) {
                        Label("Test Mode", systemImage: "eye")
                    }
                    .help("Test mode: zones light up, but no actions run")
                    Toggle(isOn: $state.enabled) {
                        Label(state.enabled ? "Enabled" : "Paused", systemImage: state.enabled ? "pause.circle" : "play.circle")
                    }
                    .help(state.enabled ? "Pause tap detection" : "Resume tap detection")
                }
            }
        }
        .frame(minWidth: 920, minHeight: 660)
        .sheet(item: $editingZone) { zone in
            ZoneEditorView(zone: zone).environment(state)
        }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView(done: { onboarded = true }).environment(state)
        }
        .overlay {
            if state.calibratingZone != nil {
                CalibrationOverlay().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: state.calibratingZone == nil)
        .onAppear {
            state.openMainWindow = {
                openWindow(id: "main"); NSApp.activate()
            }
            NSApp.setActivationPolicy(.regular)
            if !state.didLaunch {
                state.didLaunch = true
                if onboarded && !openWindowAtLaunch { dismissWindow(id: "main") }
            }
        }
    }
}

// MARK: - Desk

struct DeskView: View {
    @Environment(AppState.self) private var state
    let edit: (ZoneConfig) -> Void
    let goToSettings: () -> Void
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "Your desk",
                subtitle: "Click a spot on the desk, or its key below, to choose what a tap does."
            ) {
                HStack(spacing: 10) {
                    QualityChip()
                    calibrateMenu
                }
            }

            if !state.sensorAlive {
                SensorOfflineCard(goToSettings: goToSettings)
            }

            DeskStage(
                highlighted: hovered,
                onSelect: { edit(state.zone($0)) },
                onHover: { hovered = $0 }
            )
            .frame(maxWidth: .infinity)
            .layoutPriority(1)  // gets the height left over first; keeps its aspect

            HStack(spacing: 10) {
                ForEach(deskOrder, id: \.self) { id in
                    ZoneKey(
                        zoneID: id, highlighted: hovered == id, edit: { edit(state.zone(id)) },
                        onHover: { inside in
                            if inside { hovered = id } else if hovered == id { hovered = nil }
                        })
                    if id == "L1" || id == "F2" {
                        Spacer().frame(width: 6)  // left, front and right groups, as on the desk
                    }
                }
            }
            .frame(height: 124)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 24)
    }

    private var calibrateMenu: some View {
        let missing = calibrationOrder.filter { !state.zone($0).isCalibrated }
        return Menu {
            Button("Calibrate All Zones") { state.calibrate(calibrationOrder) }
            Button("Calibrate Missing Zones") { state.calibrate(missing) }
                .disabled(missing.isEmpty)
        } label: {
            Label("Calibrate", systemImage: "scope")
        } primaryAction: {
            state.calibrate(missing.isEmpty ? calibrationOrder : missing)
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .tint(Color.ink)
        .fixedSize()
        .disabled(!state.sensorAlive)
        .help(state.sensorAlive ? "Tap each zone 10 times to teach TouchMac how it feels" : "Start the sensor first")
    }
}

struct SensorOfflineCard: View {
    @Environment(AppState.self) private var state
    let goToSettings: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.hardwarePresent ? "sensor" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if state.hardwarePresent {
                switch state.helperStatus {
                case .notInstalled, .outdated:
                    Button(state.helperStatus == .outdated ? "Update Helper" : "Install Helper") { state.installHelper() }
                        .buttonStyle(.ink)
                        .disabled(state.helperBusy)
                case .installed:
                    Button("Troubleshoot", action: goToSettings).buttonStyle(.inkQuiet)
                }
            }
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, style: .continuous)
                .fill(.orange)
                .frame(width: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.hairline))
    }

    private var title: String {
        guard state.hardwarePresent else { return "This Mac has no supported motion sensor" }
        switch state.helperStatus {
        case .notInstalled: return "Install the sensor helper to start"
        case .outdated: return "The sensor helper needs an update"
        case .installed: return "Waiting for the sensor"
        }
    }

    private var detail: String {
        guard state.hardwarePresent else { return "TouchMac needs an Apple Silicon MacBook that exposes the SPU accelerometer." }
        switch state.helperStatus {
        case .notInstalled: return "A small background helper reads the sensor. You enter your password once."
        case .outdated: return "This version of TouchMac ships a newer helper."
        case .installed: return "The helper is installed, but no data is arriving yet. This normally takes a few seconds."
        }
    }
}

// MARK: - Shared pieces

struct QualityChip: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let q = state.quality {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                Text("\(Int((q.accuracy * 100).rounded()))% accurate")
            }
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(qualityColor(q.accuracy))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(qualityColor(q.accuracy).opacity(0.12), in: Capsule())
            .help(helpText(q))
        }
    }

    private func helpText(_ q: Classifier.Report) -> String {
        let pairs = q.confusedWith.map { "\(state.zone($0.key).name) → \(state.zone($0.value).name)" }.sorted()
        let base = "Calibration check: the share of your calibration taps that TouchMac puts back in the right zone."
        return pairs.isEmpty ? base : base + "\nMix-ups: " + pairs.joined(separator: ", ")
    }
}

struct SensorStatusView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PulseDot(color: color, pulsing: state.sensorAlive && state.enabled)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Seismograph(compact: true)
                .frame(height: 34)
            if state.helperStatus == .outdated {
                Button("Update Helper…") { state.installHelper() }
                    .controlSize(.small)
                    .disabled(state.helperBusy)
                    .help("This version of TouchMac ships a newer sensor helper")
            }
        }
        .padding(10)
        .background(Color.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
    }

    private var color: Color {
        if !state.sensorAlive { return .orange }
        return state.enabled ? .live : .secondary
    }

    private var title: String {
        if !state.sensorAlive { return "Sensor offline" }
        return state.enabled ? (state.testMode ? "Test mode" : "Listening") : "Paused"
    }

    private var subtitle: String {
        if !state.sensorAlive {
            switch state.helperStatus {
            case .installed: return "Waiting for data"
            case .outdated: return "Helper needs an update"
            case .notInstalled: return "Helper not installed"
            }
        }
        return state.testMode ? "Actions will not run" : "Tap the desk"
    }
}

/// A status dot; when live it sends out a slow ring, like a sonar ping.
struct PulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var pulsing = false

    var body: some View {
        ZStack {
            if pulsing && !reduceMotion {
                PhaseAnimator([false, true]) { on in
                    Circle().stroke(color, lineWidth: 1.5)
                        .scaleEffect(on ? 2.4 : 1)
                        .opacity(on ? 0 : 0.7)
                } animation: { on in
                    on ? .easeOut(duration: 1.8) : .linear(duration: 0)
                }
            }
            Circle().fill(color)
        }
        .frame(width: 8, height: 8)
    }
}

struct NoticeBar: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}

/// The live sensor signal drawn like a seismogram: a mirrored ink trace on graph paper,
/// log scale, with the red threshold needle a tap must cross.
struct Seismograph: View {
    @Environment(AppState.self) private var state
    var compact = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 25, paused: !state.sensorAlive)) { _ in
            let _ = state.pollSignal()
            let h = state.signal
            Canvas { ctx, size in
                let mid = size.height / 2
                func amp(_ g: Double) -> CGFloat {  // 1 mg ... 1 g, log scale, half height
                    let v = (log10(max(g, 0.001)) + 3) / 3
                    return mid * 0.92 * CGFloat(min(max(v, 0), 1))
                }
                if !compact {
                    var grid = Path()
                    for x in stride(from: 0, through: size.width, by: 8) {
                        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: mid.truncatingRemainder(dividingBy: 8), through: size.height, by: 8) {
                        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    ctx.stroke(grid, with: .color(.ink.opacity(0.05)), lineWidth: 0.5)
                }
                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: mid)); axis.addLine(to: CGPoint(x: size.width, y: mid))
                ctx.stroke(axis, with: .color(.ink.opacity(0.18)), lineWidth: 0.5)

                let step = size.width / CGFloat(SignalHistory.length - 1)
                var trace = Path(), loud = Path()
                for (i, v) in h.values.enumerated() where v > 0 {
                    let x = CGFloat(i) * step, a = max(amp(v), 0.5)
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: mid - a)); line.addLine(to: CGPoint(x: x, y: mid + a))
                    if v > h.threshold { loud.addPath(line) } else { trace.addPath(line) }
                }
                ctx.stroke(trace, with: .color(.ink.opacity(0.4)), lineWidth: max(step * 0.6, 1))
                ctx.stroke(loud, with: .color(.ink), lineWidth: max(step * 0.8, 1.4))

                let t = amp(h.threshold)
                var needle = Path()
                for y in [mid - t, mid + t] {
                    needle.move(to: CGPoint(x: 0, y: y)); needle.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(needle, with: .color(.needle.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                // the pen
                if let last = h.values.last, state.sensorAlive {
                    let a = amp(last)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: size.width - 3.5, y: mid - a - 2, width: 4, height: 4)),
                        with: .color(.needle))
                }
            }
        }
        .background(compact ? Color.clear : Color.surface)
        .overlay {
            if !state.sensorAlive {
                Text("No sensor data").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Live sensor signal")
    }
}

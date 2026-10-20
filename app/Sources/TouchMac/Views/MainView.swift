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
        case .sensitivity: return "slider.horizontal.3"
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
    @State private var page: Page? = .desk
    @State private var editingZone: ZoneConfig?

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.rawValue, systemImage: p.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 240)
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
        .frame(minWidth: 900, minHeight: 620)
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
        .animation(.easeInOut(duration: 0.2), value: state.calibratingZone)
        .onAppear {
            state.openMainWindow = { openWindow(id: "main"); NSApp.activate() }
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your desk is the button")
                        .font(.title2.weight(.semibold))
                    Text("Click a zone to choose what it does. Calibrate zones so TouchMac can tell them apart.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                QualityChip()
                calibrateMenu
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)

            if !state.sensorAlive {
                SensorOfflineCard(goToSettings: goToSettings)
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
            }

            Spacer(minLength: 16)
            deck
            Spacer(minLength: 16)

            SignalStrip()
                .frame(height: 70)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
    }

    private var calibrateMenu: some View {
        let missing = state.config.zones.filter { !$0.isCalibrated }.map(\.id)
        let all = ["L2", "L1", "R2", "R1", "F1", "F2"]
        return Menu {
            Button("Calibrate All Zones") { state.calibrate(all) }
            Button("Calibrate Missing Zones") { state.calibrate(missing) }
                .disabled(missing.isEmpty)
        } label: {
            Label("Calibrate", systemImage: "scope")
        } primaryAction: {
            state.calibrate(missing.isEmpty ? all : missing)
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .fixedSize()
        .disabled(!state.sensorAlive)
        .help(state.sensorAlive ? "Tap each zone 10 times to teach TouchMac its feel" : "Start the sensor first")
    }

    private var deck: some View {
        HStack(spacing: 22) {
            VStack(spacing: 18) {
                pad("L2")
                pad("L1")
            }
            VStack(spacing: 20) {
                MacBookView()
                HStack(spacing: 18) {
                    pad("F1")
                    pad("F2")
                }
            }
            VStack(spacing: 18) {
                pad("R2")
                pad("R1")
            }
        }
        .padding(.horizontal, 28)
    }

    private func pad(_ id: String) -> some View {
        ZonePadView(zoneID: id, edit: { edit(state.zone(id)) })
    }
}

struct SensorOfflineCard: View {
    @Environment(AppState.self) private var state
    let goToSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.hardwarePresent ? "sensor" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if state.hardwarePresent {
                switch state.helperStatus {
                case .notInstalled, .outdated:
                    Button(state.helperStatus == .outdated ? "Update Helper" : "Install Helper") { state.installHelper() }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.helperBusy)
                case .installed:
                    Button("Troubleshoot…", action: goToSettings)
                }
            }
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.25)))
    }

    private var title: String {
        guard state.hardwarePresent else { return "This Mac has no supported motion sensor" }
        switch state.helperStatus {
        case .notInstalled: return "Sensor helper not installed"
        case .outdated: return "Sensor helper needs an update"
        case .installed: return "Waiting for the sensor…"
        }
    }

    private var detail: String {
        guard state.hardwarePresent else { return "TouchMac needs an Apple Silicon MacBook Pro that exposes the SPU accelerometer." }
        switch state.helperStatus {
        case .notInstalled: return "A small background helper reads the sensor. You enter your password once."
        case .outdated: return "This version of TouchMac ships a newer helper."
        case .installed: return "The helper is installed but no data is arriving yet. This normally takes a few seconds."
        }
    }
}

/// Top-down MacBook illustration.
struct MacBookView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.46)], startPoint: .top, endPoint: .bottom))
            .overlay {
                VStack(spacing: 10) {
                    VStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            HStack(spacing: 3) {
                                ForEach(0..<13, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.black.opacity(0.6))
                                        .frame(height: 11)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.black.opacity(0.25))
                        .frame(width: 100, height: 62)
                }
                .padding(.vertical, 18)
            }
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .frame(width: 320, height: 212)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .overlay(alignment: .top) {
                // a ripple from the chassis on every detected tap
                Circle()
                    .strokeBorder(Color.accentColor.opacity(state.flashZone == nil ? 0 : 0.5), lineWidth: 2)
                    .frame(width: state.flashZone == nil ? 20 : 260)
                    .offset(y: 70)
                    .animation(state.flashZone == nil ? nil : .easeOut(duration: 0.45), value: state.flashZone)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("MacBook, seen from above")
    }
}

// MARK: - Shared pieces

func qualityColor(_ value: Double) -> Color {
    value >= 0.9 ? .green : value >= 0.7 ? .orange : .red
}

struct QualityChip: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let q = state.quality {
            Label("\(Int((q.accuracy * 100).rounded()))% accurate", systemImage: "checkmark.seal")
                .font(.callout.weight(.medium))
                .foregroundStyle(qualityColor(q.accuracy))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(qualityColor(q.accuracy).opacity(0.12), in: Capsule())
                .help(helpText(q))
        }
    }

    private func helpText(_ q: Classifier.Report) -> String {
        let pairs = q.confusedWith.map { "\(state.zone($0.key).name) → \(state.zone($0.value).name)" }.sorted()
        let base = "Calibration check: share of your calibration taps TouchMac puts back in the right zone."
        return pairs.isEmpty ? base : base + "\nMix-ups: " + pairs.joined(separator: ", ")
    }
}

struct SensorStatusView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.8), radius: state.sensorAlive ? 4 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if state.helperStatus == .outdated {
                Button("Update Helper…") { state.installHelper() }
                    .controlSize(.small)
                    .disabled(state.helperBusy)
                    .help("This version of TouchMac ships a newer, more efficient sensor helper")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var color: Color {
        if !state.sensorAlive { return .orange }
        return state.enabled ? .green : .secondary
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

struct NoticeBar: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.yellow.opacity(0.12))
    }
}

/// Live scrolling meter of the sensor signal, log scale, with the current tap threshold.
struct SignalStrip: View {
    @Environment(AppState.self) private var state
    var showLegend = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showLegend {
                HStack {
                    Text("Live signal").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Rectangle().fill(.orange).frame(width: 12, height: 2)
                        Text("tap threshold").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            TimelineView(.animation(minimumInterval: 1.0 / 25, paused: !state.sensorAlive)) { _ in
                let _ = state.pollSignal()
                let h = state.signal
                Canvas { ctx, size in
                    func y(_ g: Double) -> CGFloat {  // 1 mg ... 1 g, log scale
                        let v = (log10(max(g, 0.001)) + 3) / 3
                        return size.height * (1 - CGFloat(min(max(v, 0), 1)))
                    }
                    let barW = size.width / CGFloat(SignalHistory.length)
                    for (i, v) in h.values.enumerated() where v > 0 {
                        let top = y(v)
                        let rect = CGRect(x: CGFloat(i) * barW, y: top, width: max(barW - 1, 1), height: size.height - top)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                                 with: .color(v > h.threshold ? Color.accentColor : Color.secondary.opacity(0.45)))
                    }
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: y(h.threshold)))
                    line.addLine(to: CGPoint(x: size.width, y: y(h.threshold)))
                    ctx.stroke(line, with: .color(.orange), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if !state.sensorAlive {
                    Text("No sensor data").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Live sensor signal")
        }
    }
}

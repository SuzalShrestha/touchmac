import ServiceManagement
import SwiftUI
import TouchMacCore

// MARK: - Sensitivity

struct SensitivityView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                SignalStrip(showLegend: false)
                    .frame(height: 110)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    HStack {
                        Text("Background noise: \(milliG(state.signal.noiseFloor))")
                        Spacer()
                        Text("Tap threshold now: \(milliG(state.signal.threshold))")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text("Live signal")
            } footer: {
                Text("Tap the desk and watch the bars. A tap must rise above the orange line.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Slider(value: $state.config.thresholdG, in: 0.01...0.15) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Light").font(.caption)
                    } maximumValueLabel: {
                        Text("Firm").font(.caption)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Tap strength")
                        Text(milliG(state.config.thresholdG)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $state.config.adaptiveThreshold) {
                    Text("Adapt to noisy surroundings")
                    Text("Raises the threshold while the desk vibrates (fans, music, a train). Never lowers it.")
                }
                Toggle(isOn: $state.config.ignoreWhileTyping) {
                    Text("Ignore taps while typing or clicking")
                    Text("Keystrokes and trackpad clicks shake the MacBook too.")
                }
            } header: {
                Text("Tap detection")
            } footer: {
                Text("Light: softer taps work, but typing may trigger zones. Firm: fewer false taps.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Slider(value: $state.config.maxDistance, in: 2...12) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Strict").font(.caption)
                    } maximumValueLabel: {
                        Text("Loose").font(.caption)
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text("Tolerance")
                        Text(String(format: "%.1f", state.config.maxDistance)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Zone matching")
            } footer: {
                Text("Strict ignores taps that do not clearly match a zone. Loose matches more taps but picks the wrong zone more often.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Defaults") {
                    let d = AppConfig()
                    state.config.thresholdG = d.thresholdG
                    state.config.maxDistance = d.maxDistance
                    state.config.adaptiveThreshold = d.adaptiveThreshold
                    state.config.ignoreWhileTyping = d.ignoreWhileTyping
                }
            }
        }
        .formStyle(.grouped)
    }

    private func milliG(_ g: Double) -> String { String(format: "%.3f g", g) }
}

// MARK: - Activity

struct ActivityView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if state.events.isEmpty {
                ContentUnavailableView("No taps yet", systemImage: "hand.tap",
                                       description: Text("Detected taps, actions and errors appear here."))
            } else {
                List(state.events) { event in
                    HStack(spacing: 10) {
                        Image(systemName: symbol(event.kind))
                            .foregroundStyle(color(event.kind))
                            .frame(width: 18)
                        Text(event.text)
                            .textSelection(.enabled)
                        Spacer()
                        Text(event.date, format: .dateTime.hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Clear", systemImage: "trash") { state.events.removeAll() }
                    .disabled(state.events.isEmpty)
                    .help("Clear the activity list")
            }
        }
    }

    private func symbol(_ kind: TapEvent.Kind) -> String {
        switch kind {
        case .action: return "hand.tap.fill"
        case .unmatched: return "questionmark.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }

    private func color(_ kind: TapEvent.Kind) -> Color {
        switch kind {
        case .action: return .accentColor
        case .unmatched: return .secondary
        case .error: return .red
        case .info: return .blue
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage("openWindowAtLaunch") private var openWindowAtLaunch = true
    @State private var confirmUninstall = false
    @State private var confirmClear = false
    @State private var permissionTick = 0
    let showWelcome: () -> Void

    var body: some View {
        Form {
            Section("Sensor") {
                LabeledContent("Motion sensor") {
                    Label(state.hardwarePresent ? "Found" : "Not found on this Mac",
                          systemImage: state.hardwarePresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(state.hardwarePresent ? .green : .red)
                }
                LabeledContent("Helper") {
                    Text(helperText).foregroundStyle(.secondary)
                }
                LabeledContent("Data") {
                    Label(state.sensorAlive ? "Streaming" : "No data",
                          systemImage: state.sensorAlive ? "dot.radiowaves.left.and.right" : "pause.circle")
                        .foregroundStyle(state.sensorAlive ? .green : .orange)
                }
                HStack {
                    Button(state.helperStatus == .notInstalled ? "Install Helper…" :
                           state.helperStatus == .outdated ? "Update Helper…" : "Reinstall Helper…") {
                        state.installHelper()
                    }
                    if state.helperStatus != .notInstalled {
                        Button("Restart Helper…") { state.restartHelper() }
                        Button("Uninstall…", role: .destructive) { confirmUninstall = true }
                    }
                    Spacer()
                    if state.helperBusy { ProgressView().controlSize(.small) }
                    Button("Show Log") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: Helper.logPath))
                    }
                    .disabled(!FileManager.default.fileExists(atPath: Helper.logPath))
                }
                .disabled(state.helperBusy || !state.hardwarePresent)
            }

            Section {
                ForEach(Permission.allCases) { p in
                    LabeledContent {
                        if p.granted {
                            Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Grant…") { p.request() }
                        }
                    } label: {
                        Text(p.title)
                        Text(p.purpose)
                    }
                }
                .id(permissionTick)
            } header: {
                Text("Permissions")
            } footer: {
                Text("Only needed for the actions that use them. After an update, macOS may ask again.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch TouchMac at login", isOn: Binding(get: { state.launchAtLogin },
                                                                 set: { state.setLaunchAtLogin($0) }))
                Toggle("Open this window when TouchMac starts", isOn: $openWindowAtLaunch)
                Button("Show Welcome Guide…", action: showWelcome)
            }

            Section("Data") {
                HStack {
                    Button("Show Settings File") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppConfig.defaultURL])
                    }
                    Spacer()
                    Button("Clear All Calibration…", role: .destructive) { confirmClear = true }
                }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionTick += 1
            state.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .confirmationDialog("Uninstall the sensor helper?", isPresented: $confirmUninstall) {
            Button("Uninstall", role: .destructive) { state.uninstallHelper() }
        } message: {
            Text("TouchMac stops detecting taps until you install it again.")
        }
        .confirmationDialog("Clear the calibration of all six zones?", isPresented: $confirmClear) {
            Button("Clear All", role: .destructive) { state.clearCalibration(zoneIDs: state.config.zones.map(\.id)) }
        } message: {
            Text("Your actions stay. You will need to calibrate every zone again.")
        }
    }

    private var helperText: String {
        switch state.helperStatus {
        case .notInstalled: return "Not installed"
        case .outdated: return "Installed (update available)"
        case .installed: return "Installed · starts at boot"
        }
    }
}

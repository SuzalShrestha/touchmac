import SwiftUI
import UniformTypeIdentifiers

struct ZoneEditorView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var zone: ZoneConfig
    @State private var kind: Kind
    @State private var shellCommand: String
    @State private var appPath: String

    enum Kind: String, CaseIterable, Identifiable {
        case none = "None"
        case openApp = "Open app"
        case screenshot = "Screenshot"
        case volumeUp = "Volume up"
        case volumeDown = "Volume down"
        case mute = "Mute"
        case playPause = "Play / Pause"
        case shell = "Shell command"
        var id: String { rawValue }
    }

    init(zone: ZoneConfig) {
        _zone = State(initialValue: zone)
        switch zone.action {
        case .none: _kind = State(initialValue: .none); _shellCommand = State(initialValue: ""); _appPath = State(initialValue: "")
        case .openApp(let p): _kind = State(initialValue: .openApp); _shellCommand = State(initialValue: ""); _appPath = State(initialValue: p)
        case .shell(let c): _kind = State(initialValue: .shell); _shellCommand = State(initialValue: c); _appPath = State(initialValue: "")
        case .screenshot: _kind = State(initialValue: .screenshot); _shellCommand = State(initialValue: ""); _appPath = State(initialValue: "")
        case .volumeUp: _kind = State(initialValue: .volumeUp); _shellCommand = State(initialValue: ""); _appPath = State(initialValue: "")
        case .volumeDown: _kind = State(initialValue: .volumeDown); _shellCommand = State(initialValue: ""); _appPath = State(initialValue: "")
        case .mute: _kind = State(initialValue: .mute); _shellCommand = State(initialValue: ""); _appPath = State(initialValue: "")
        case .playPause: _kind = State(initialValue: .playPause); _shellCommand = State(initialValue: ""); _appPath = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(zone.name)
                .font(.title3.bold())

            Picker("When tapped", selection: $kind) {
                ForEach(Kind.allCases) { k in Text(k.rawValue).tag(k) }
            }

            if kind == .openApp {
                HStack {
                    if appPath.isEmpty {
                        Text("No app selected").foregroundStyle(.secondary)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                            .resizable().frame(width: 20, height: 20)
                        Text((appPath as NSString).lastPathComponent)
                    }
                    Spacer()
                    Button("Choose…") { chooseApp() }
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            if kind == .shell {
                TextField("e.g. open -a Notes", text: $shellCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calibration")
                        .font(.headline)
                    Text(zone.isCalibrated
                         ? "\(zone.samples.count) taps recorded"
                         : "Not calibrated — zone can't be detected yet")
                        .font(.caption)
                        .foregroundStyle(zone.isCalibrated ? .secondary : Color.orange)
                }
                Spacer()
                if zone.isCalibrated {
                    Button("Clear") {
                        state.clearCalibration(zoneID: zone.id)
                        zone.samples = []
                    }
                }
                Button(zone.isCalibrated ? "Recalibrate" : "Calibrate") {
                    save()
                    dismiss()
                    state.startCalibration(zoneID: zone.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.sensorAlive)
                .help(state.sensorAlive ? "" : "Start the sensor first")
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        switch kind {
        case .none: zone.action = .none
        case .openApp: zone.action = appPath.isEmpty ? .none : .openApp(appPath)
        case .shell: zone.action = shellCommand.isEmpty ? .none : .shell(shellCommand)
        case .screenshot: zone.action = .screenshot
        case .volumeUp: zone.action = .volumeUp
        case .volumeDown: zone.action = .volumeDown
        case .mute: zone.action = .mute
        case .playPause: zone.action = .playPause
        }
        state.update(zone)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            appPath = url.path
        }
    }
}

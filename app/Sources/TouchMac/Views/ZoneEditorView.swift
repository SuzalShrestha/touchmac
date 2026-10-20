import SwiftUI
import TouchMacCore
import UniformTypeIdentifiers

struct ZoneEditorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var zone: ZoneConfig
    @State private var kind: TapAction.Kind
    @State private var text: String
    @State private var doubleKind: TapAction.Kind
    @State private var doubleText: String

    init(zone: ZoneConfig) {
        _zone = State(initialValue: zone)
        _kind = State(initialValue: zone.action.kind)
        _text = State(initialValue: zone.action.text)
        _doubleKind = State(initialValue: zone.doubleAction.kind)
        _doubleText = State(initialValue: zone.doubleAction.text)
    }

    private var action: TapAction { TapAction(kind: kind, text: text) }
    private var doubleAction: TapAction { TapAction(kind: doubleKind, text: doubleText) }
    private var calibrated: ZoneConfig { state.zone(zone.id) }  // live: Clear updates it at once

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $zone.name)
                }
                Section("Single tap") {
                    ActionPicker(title: "Action", kind: $kind, text: $text)
                }
                Section {
                    ActionPicker(title: "Action", kind: $doubleKind, text: $doubleText)
                } header: {
                    Text("Double tap")
                } footer: {
                    Text("With a double-tap action, a single tap on this zone waits about half a second for a second tap.")
                        .foregroundStyle(.secondary)
                }
                Section("Calibration") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calibrated.isCalibrated ? "\(calibrated.samples.count) taps recorded" : "Not calibrated")
                            if let score = state.quality?.perZone[zone.id] {
                                Text("\(Int((score * 100).rounded()))% of its taps are recognized"
                                     + (state.quality?.confusedWith[zone.id].map { " · sometimes read as \(state.zone($0).name)" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(qualityColor(score))
                            } else if !calibrated.isCalibrated {
                                Text("This zone cannot be detected yet.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if calibrated.isCalibrated {
                            Button("Clear", role: .destructive) { state.clearCalibration(zoneIDs: [zone.id]) }
                        }
                        Button(calibrated.isCalibrated ? "Recalibrate" : "Calibrate") {
                            save()
                            dismiss()
                            state.calibrate([zone.id])
                        }
                        .disabled(!state.sensorAlive)
                        .help(state.sensorAlive ? "Tap this spot 10 times" : "Start the sensor first")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button {
                    state.run(action, from: "Test")
                } label: {
                    Label("Test Action", systemImage: "play")
                }
                .disabled(action == .none)
                .help("Run the single-tap action now")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 480)
        .frame(minHeight: 560)
    }

    private func save() {
        var z = calibrated
        z.name = zone.name.trimmingCharacters(in: .whitespaces).isEmpty ? calibrated.name : zone.name
        z.action = action
        z.doubleAction = doubleAction
        state.update(z)
    }
}

struct ActionPicker: View {
    let title: String
    @Binding var kind: TapAction.Kind
    @Binding var text: String
    @State private var permissionTick = 0

    var body: some View {
        Picker(title, selection: $kind) {
            ForEach(TapAction.Kind.allCases) { k in
                Label(k.rawValue, systemImage: TapAction(kind: k, text: "x").symbol).tag(k)
            }
        }
        .onChange(of: kind) { text = "" }

        if kind == .openApp {
            HStack {
                if text.isEmpty {
                    Text("No app chosen").foregroundStyle(.secondary)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: text))
                        .resizable().frame(width: 20, height: 20)
                    Text(((text as NSString).lastPathComponent as NSString).deletingPathExtension)
                }
                Spacer()
                Button("Choose…", action: chooseApp)
            }
        } else if let placeholder = kind.placeholder {
            TextField(kind == .shell ? "Command" : kind == .openURL ? "Address" : "Name", text: $text, prompt: Text(placeholder))
                .font(kind == .shell ? .body.monospaced() : .body)
            if kind == .shell {
                Text("Runs in your login shell, so tools from Homebrew work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        if let p = TapAction(kind: kind, text: "x").requiredPermission, !p.granted {
            HStack {
                Label("Needs the \(p.title) permission", systemImage: "lock")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Grant…") { p.request() }
            }
            .id(permissionTick)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permissionTick += 1
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            text = url.path
        }
    }
}

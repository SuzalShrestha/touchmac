import SwiftUI

@main
struct TouchMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()
    @State private var updater = Updater()

    var body: some Scene {
        Window("TouchMac", id: "main") {
            MainView()
                .environment(state)
                .environment(updater)
                .onAppear { delegate.state = state }
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                if updater.isConfigured {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
        }

        MenuBarExtra {
            MenuPanel()
                .environment(state)
                .environment(updater)
        } label: {
            Image(systemName: state.enabled && state.sensorAlive ? "hand.tap.fill" : "hand.tap")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationWillFinishLaunching(_ notification: Notification) {
        if let dir = Snapshot.directory { MainActor.assumeIsolated { Snapshot.run(to: dir) } }
        // one copy only: a second one could not bind the sensor port anyway
        guard let id = Bundle.main.bundleIdentifier else { return }
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0 != .current })
        {
            other.activate()
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // main window closed: live on in the menu bar, no Dock icon (SwiftUI's onDisappear does not fire here)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, window.sheetParent == nil, !(window is NSPanel),
                window.canBecomeMain
            else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Double-clicking the app while it runs in the menu bar brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { state?.openMainWindow?() } }
        return true
    }

    /// Closing the window keeps TouchMac running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// The menu bar panel: status, the live signal, the last taps, and the switches you use most.
struct MenuPanel: View {
    @Environment(AppState.self) private var state
    @Environment(Updater.self) private var updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("TouchMac").font(.display(15))
                Spacer()
                PulseDot(
                    color: state.sensorAlive ? (state.enabled ? .live : .secondary) : .orange,
                    pulsing: state.sensorAlive && state.enabled)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Seismograph()
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hairline))

            VStack(alignment: .leading, spacing: 6) {
                if state.events.isEmpty {
                    Text("No taps yet. Tap the desk beside your MacBook.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(state.events.prefix(3)) { event in
                        EventRow(event: event, compact: true)
                    }
                }
            }

            Divider()
            Toggle("Detect taps", isOn: $state.enabled)
            Toggle("Test mode (no actions run)", isOn: $state.testMode)

            if let version = updater.pendingVersion {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("TouchMac \(version) is available", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.ink)
            }

            Divider()
            HStack {
                Button("Open TouchMac") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .buttonStyle(.ink)
                .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.inkQuiet)
                    .keyboardShortcut("q")
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(14)
        .frame(width: 300)
    }

    private var status: String {
        if !state.sensorAlive { return "Sensor offline" }
        return state.enabled ? (state.testMode ? "Test mode" : "Listening") : "Paused"
    }
}

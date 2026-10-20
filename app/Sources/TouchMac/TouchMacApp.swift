import SwiftUI

@main
struct TouchMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        Window("TouchMac", id: "main") {
            MainView()
                .environment(state)
                .onAppear { delegate.state = state }
        }
        .defaultSize(width: 980, height: 660)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuContent()
                .environment(state)
        } label: {
            Image(systemName: state.enabled && state.sensorAlive ? "hand.tap.fill" : "hand.tap")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // one copy only: a second one could not bind the sensor port anyway
        guard let id = Bundle.main.bundleIdentifier else { return }
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first(where: { $0 != .current }) {
            other.activate()
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // main window closed: live on in the menu bar, no Dock icon (SwiftUI's onDisappear does not fire here)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow, window.sheetParent == nil, !(window is NSPanel),
                  window.canBecomeMain else { return }
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

struct MenuContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var state = state
        Text(state.sensorAlive ? "Sensor live" : "Sensor offline")
        Toggle("Enabled", isOn: $state.enabled)
        Toggle("Test Mode", isOn: $state.testMode)
        Divider()
        Button("Open TouchMac…") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit TouchMac") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

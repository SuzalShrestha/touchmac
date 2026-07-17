import SwiftUI

@main
struct TouchMacApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("TouchMac", id: "main") {
            MainView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("TouchMac", systemImage: "hand.tap.fill") {
            Toggle("Enabled", isOn: Binding(get: { state.enabled }, set: { state.enabled = $0 }))
            Divider()
            Button("Open TouchMac…") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.title == "TouchMac" {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

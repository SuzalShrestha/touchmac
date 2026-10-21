import AppKit
import SwiftUI
import TouchMacCore

/// `TouchMac --snapshot <dir>` renders the desk and every screen to PNG files with demo data,
/// then quits. It never connects to the sensor and never writes the settings file.
/// Used to review the design and to make the README and website pictures.
@MainActor
enum Snapshot {
    static let directory: URL? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }()

    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDefaults.standard.register(defaults: ["onboarded": true])  // volatile: nothing is stored
        for dark in [false, true] {
            guard let out = DeskRender.render(dark: dark) else { continue }
            DeskRender.prime(out, dark: dark)
            write(out.image, to: dir.appendingPathComponent("desk-render-\(dark ? "dark" : "light").png"))
        }

        let state = AppState()
        let updater = Updater()
        fillDemo(state)

        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            func shot<V: View>(_ name: String, _ size: CGSize, settle: Double = 0.9, _ view: V) {
                capture(
                    view.environment(state).environment(updater), size: size, dark: dark,
                    settle: settle, to: dir.appendingPathComponent("\(name)-\(suffix).png"))
            }
            let window = CGSize(width: 1100, height: 760)
            shot("desk", window, MainView(page: .desk))
            shot("desk-alone", CGSize(width: 900, height: 708), DeskView(edit: { _ in }, goToSettings: {}).background(Color.canvas))
            state.flashZone = "R1"
            shot("desk-tap", window, settle: 0.25, MainView(page: .desk))
            state.flashZone = nil
            shot("sensitivity", window, MainView(page: .sensitivity))
            shot("activity", window, MainView(page: .activity))
            shot("settings", window, MainView(page: .settings))
            shot("menu", CGSize(width: 300, height: 330), MenuPanel().background(Color.surface))  // the real panel gets a system material
            shot("editor", CGSize(width: 500, height: 640), ZoneEditorView(zone: state.zone("R1")))
            for step in 0..<4 {
                shot("onboarding-\(step)", CGSize(width: 640, height: 590), OnboardingView(done: {}, startAt: step))
            }
            state.calibrate(["R1", "F1", "F2"])
            state.calibrationTaps = 6
            shot("calibration", window, settle: 1.6, MainView(page: .desk))
            state.endCalibration()
        }
        exit(0)
    }

    private static func fillDemo(_ state: AppState) {
        let actions: [String: (TapAction, TapAction)] = [
            "L2": (.openApp("/Applications/Safari.app"), .none),
            "L1": (.screenshot, .none),
            "F1": (.missionControl, .none),
            "F2": (.openApp("/System/Applications/Notes.app"), .shortcut("Focus")),
            "R1": (.volumeUp, .volumeDown),
            "R2": (.playPause, .nextTrack),
        ]
        var rng = SystemRandomNumberGenerator()
        for (i, id) in calibrationOrder.enumerated() {
            var z = state.zone(id)
            z.action = actions[id]?.0 ?? .none
            z.doubleAction = actions[id]?.1 ?? .none
            z.samples =
                id == "F1"
                ? []
                : (0..<10).map { _ in  // F1 left to calibrate, to show that state
                    (0..<7).map { d in (d == i ? 1 : 0.15) + Double.random(in: -0.12...0.12, using: &rng) }
                }
            state.update(z)
        }
        state.sensorAlive = true
        state.helperStatus = .installed
        for i in 0..<SignalHistory.length {
            let tap = [40, 41, 90, 91, 92, 128].contains(i)
            state.signal.push(
                tap ? Double.random(in: 0.1...0.35) : Double.random(in: 0.002...0.008),
                threshold: 0.04, noise: 0.004)
        }
        state.log(.info, "Sensor helper installed. It now starts with your Mac.")
        state.log(.action, "Left Far → Open Safari", zone: "L2")
        state.log(.unmatched, "Tap did not match any zone")
        state.log(.action, "Right Near → Volume up", zone: "R1")
        state.log(.action, "Right Far ×2 → Next track", zone: "R2")
        state.log(.action, "Left Near → Screenshot", zone: "L1")
    }

    private static func capture<V: View>(_ view: V, size: CGSize, dark: Bool, settle: Double, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        // on screen but fully transparent: the toolbar and safe areas lay out as in a real window
        window.alphaValue = 0
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))  // let .task and animations run
        host.layoutSubtreeIfNeeded()
        // a split view taller than its window means some page claims too much height
        if let split = host.firstSubview(of: NSSplitView.self), split.frame.height > size.height + 1 {
            print("warning: \(url.lastPathComponent) lays out \(split.frame.height) pt tall in a \(size.height) pt window")
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
        window.close()
    }

    static func write(_ image: CGImage, to url: URL) {
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }
}

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        for v in subviews {
            if let t = v as? T ?? v.firstSubview(of: type) { return t }
        }
        return nil
    }
}

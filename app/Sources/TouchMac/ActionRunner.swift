import AppKit
import CoreGraphics
import Foundation
import TouchMacCore

/// macOS privacy permissions some actions need.
enum Permission: CaseIterable, Identifiable {
    case accessibility  // posting media-key events
    case screenRecording  // screenshots

    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: return "Needed for Play / Pause and track keys."
        case .screenRecording: return "Needed for the Screenshot action."
        }
    }

    var granted: Bool {
        switch self {
        case .accessibility: return CGPreflightPostEventAccess()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        }
    }

    /// Shows the system prompt (first time only), then opens the matching Settings pane.
    func request() {
        switch self {
        case .accessibility: _ = CGRequestPostEventAccess()
        case .screenRecording: _ = CGRequestScreenCaptureAccess()
        }
        let anchor = self == .accessibility ? "Privacy_Accessibility" : "Privacy_ScreenCapture"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!)
    }
}

extension TapAction {
    var requiredPermission: Permission? {
        switch self {
        case .playPause, .nextTrack, .previousTrack: return .accessibility
        case .screenshot: return .screenRecording
        default: return nil
        }
    }
}

@MainActor
enum ActionRunner {
    /// Runs the action; `done` gets nil on success or a message for the activity log.
    static func run(_ action: TapAction, done: @escaping (String?) -> Void) {
        if let p = action.requiredPermission, !p.granted {
            return done("\(action.label) needs the \(p.title) permission. Grant it in Settings.")
        }
        switch action {
        case .none:
            done(nil)
        case .openApp(let path):
            guard FileManager.default.fileExists(atPath: path) else { return done("App not found: \(path)") }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init()) { _, error in
                DispatchQueue.main.async { done(error?.localizedDescription) }
            }
        case .openURL(let s):
            let text = s.contains("://") ? s : "https://" + s
            guard let url = URL(string: text) else { return done("Not a valid web address: \(s)") }
            NSWorkspace.shared.open(url, configuration: .init()) { _, error in
                DispatchQueue.main.async { done(error?.localizedDescription) }
            }
        case .shortcut(let name):
            exec("/usr/bin/shortcuts", ["run", name], done: done)
        case .shell(let cmd):
            // login shell: GUI apps start with a bare PATH, so Homebrew tools would be "not found"
            exec(userShell, ["-l", "-c", cmd], done: done)
        case .volumeUp:
            appleScript("set volume output volume ((output volume of (get volume settings)) + 6)", done: done)
        case .volumeDown:
            appleScript("set volume output volume ((output volume of (get volume settings)) - 6)", done: done)
        case .mute:
            appleScript("set volume output muted (not (output muted of (get volume settings)))", done: done)
        case .playPause:
            postMediaKey(16, done: done)  // NX_KEYTYPE_PLAY
        case .nextTrack:
            postMediaKey(17, done: done)  // NX_KEYTYPE_NEXT
        case .previousTrack:
            postMediaKey(18, done: done)  // NX_KEYTYPE_PREVIOUS
        case .screenshot:
            exec("/usr/sbin/screencapture", ["-ic"], done: done)
        case .missionControl:
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"),
                configuration: .init()
            ) { _, error in
                DispatchQueue.main.async { done(error?.localizedDescription) }
            }
        case .sleepDisplay:
            exec("/usr/bin/pmset", ["displaysleepnow"], done: done)
        }
    }

    private static var userShell: String {
        if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell { return String(cString: shell) }
        return "/bin/zsh"
    }

    private static func exec(_ path: String, _ args: [String], done: @escaping (String?) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        DispatchQueue.global().async {
            var message: String?
            do {
                try p.run()
                // read before waiting so a chatty command cannot fill the pipe and hang
                let data = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    message = text.isEmpty ? "Exited with code \(p.terminationStatus)" : String(text.prefix(200))
                }
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async { done(message) }
        }
    }

    /// In-process: no osascript launch per tap, and Standard Additions need no Automation prompt.
    private static func appleScript(_ source: String, done: (String?) -> Void) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        done(error.map { ($0[NSAppleScript.errorMessage] as? String) ?? "AppleScript error" })
    }

    /// System-defined media key event.
    private static func postMediaKey(_ key: Int32, done: (String?) -> Void) {
        func post(_ down: Bool) -> Bool {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | Int32((down ? 0xA : 0xB) << 8))
            guard
                let event = NSEvent.otherEvent(
                    with: .systemDefined, location: .zero, modifierFlags: flags,
                    timestamp: 0, windowNumber: 0, context: nil,
                    subtype: 8, data1: data1, data2: -1)?.cgEvent
            else { return false }
            event.post(tap: .cghidEventTap)
            return true
        }
        done(post(true) && post(false) ? nil : "Could not create the media key event")
    }
}

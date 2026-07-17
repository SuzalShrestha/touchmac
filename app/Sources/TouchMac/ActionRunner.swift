import AppKit
import Foundation

enum ActionRunner {
    static func run(_ action: TapAction) {
        switch action {
        case .none:
            break
        case .openApp(let path):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                               configuration: NSWorkspace.OpenConfiguration())
        case .shell(let cmd):
            shell(cmd)
        case .volumeUp:
            shell("osascript -e 'set volume output volume (((output volume of (get volume settings)) + 10) as integer)'")
        case .volumeDown:
            shell("osascript -e 'set volume output volume (((output volume of (get volume settings)) - 10) as integer)'")
        case .mute:
            shell("osascript -e 'set volume output muted (not (output muted of (get volume settings)))'")
        case .playPause:
            postMediaKey(16)  // NX_KEYTYPE_PLAY
        case .screenshot:
            shell("screencapture -ic")
        }
    }

    private static func shell(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
    }

    /// System-defined media key event (play/pause); no special permissions needed.
    private static func postMediaKey(_ key: Int32) {
        func post(_ down: Bool) {
            let flags: NSEvent.ModifierFlags = down ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00)
            let data1 = Int((key << 16) | Int32((down ? 0xA : 0xB) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                               timestamp: 0, windowNumber: 0, context: nil,
                               subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
        post(true)
        post(false)
    }
}

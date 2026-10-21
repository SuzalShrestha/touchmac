import Foundation
import TouchMacCore

/// Installs touchmacd as a LaunchDaemon: one admin prompt, then it starts at boot and
/// launchd restarts it after a crash, sleep or stall. The root binary lives in
/// /Library/PrivilegedHelperTools (root-owned), never in the user-writable app bundle.
enum Helper {
    static let label = "com.sujal.touchmacd"
    static let installedBinary = "/Library/PrivilegedHelperTools/\(label)"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let logPath = "/var/log/touchmacd.log"

    enum Status: Equatable {
        case notInstalled
        case outdated  // the app ships a different helper binary than the installed one
        case installed
    }

    static var bundledBinary: String? {
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let path = dir.appendingPathComponent("touchmacd").path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    static var status: Status {
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistPath), fm.fileExists(atPath: installedBinary) else { return .notInstalled }
        if let bundled = bundledBinary, !fm.contentsEqual(atPath: bundled, andPath: installedBinary) { return .outdated }
        return .installed
    }

    /// Calls `done` on the main queue with nil on success, else a message for the user.
    static func install(done: @escaping (String?) -> Void) {
        guard let src = bundledBinary else {
            return done("The helper is missing from the app bundle. Build with make_app.sh.")
        }
        runAsAdmin(
            """
            set -e
            launchctl bootout system/\(label) 2>/dev/null && sleep 1 || true
            pkill -x touchmacd 2>/dev/null || true
            rm -f /var/run/touchmacd.pid
            mkdir -p /Library/PrivilegedHelperTools
            install -m 755 -o root -g wheel \(shq(src)) \(installedBinary)
            cat > \(plistPath) <<'PLIST'
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>\(label)</string>
                <key>ProgramArguments</key><array><string>\(installedBinary)</string></array>
                <key>RunAtLoad</key><true/>
                <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
                <key>ThrottleInterval</key><integer>5</integer>
                <key>StandardErrorPath</key><string>\(logPath)</string>
                <key>StandardOutPath</key><string>\(logPath)</string>
            </dict>
            </plist>
            PLIST
            chown root:wheel \(plistPath)
            chmod 644 \(plistPath)
            launchctl bootstrap system \(plistPath)
            """, done: done)
    }

    static func uninstall(done: @escaping (String?) -> Void) {
        runAsAdmin(
            """
            launchctl bootout system/\(label) 2>/dev/null || true
            pkill -x touchmacd 2>/dev/null || true
            rm -f \(plistPath) \(installedBinary) /var/run/touchmacd.pid \(SensorWire.socketPath)
            """, done: done)
    }

    static func restart(done: @escaping (String?) -> Void) {
        runAsAdmin("launchctl kickstart -k system/\(label)", done: done)
    }

    /// POSIX single-quote escaping, safe for any path (including ones with ' in them).
    static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The script goes to osascript as an argument, so it needs no AppleScript escaping.
    private static func runAsAdmin(_ script: String, done: @escaping (String?) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = [
            "-e", "on run argv", "-e", "do shell script (item 1 of argv) with administrator privileges",
            "-e", "end run", script,
        ]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        DispatchQueue.global().async {
            var message: String?
            do {
                try p.run()
                let data = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    message = text.contains("-128") ? "Cancelled." : (text.isEmpty ? "Failed (\(p.terminationStatus))." : text)
                }
            } catch {
                message = error.localizedDescription
            }
            DispatchQueue.main.async { done(message) }
        }
    }
}

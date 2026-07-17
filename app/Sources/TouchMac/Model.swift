import Foundation

enum TapAction: Codable, Hashable {
    case none
    case openApp(String)      // full path to .app
    case shell(String)
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case screenshot

    var label: String {
        switch self {
        case .none: return "Not set"
        case .openApp(let path): return "Open \((path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""))"
        case .shell(let cmd): return cmd.count > 28 ? String(cmd.prefix(28)) + "…" : cmd
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .playPause: return "Play / Pause"
        case .screenshot: return "Screenshot"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .openApp: return "app.badge.checkmark"
        case .shell: return "terminal"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        case .playPause: return "playpause"
        case .screenshot: return "camera.viewfinder"
        }
    }
}

struct ZoneConfig: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var action: TapAction = .none
    var samples: [[Double]] = []   // calibration features

    var isCalibrated: Bool { samples.count >= 5 }
}

struct AppConfig: Codable {
    var thresholdG = 0.04
    var maxDistance = 6.0
    var zones: [ZoneConfig] = AppConfig.defaultZones

    static let defaultZones = [
        ZoneConfig(id: "L1", name: "Left Near"),
        ZoneConfig(id: "L2", name: "Left Far"),
        ZoneConfig(id: "R1", name: "Right Near"),
        ZoneConfig(id: "R2", name: "Right Far"),
        ZoneConfig(id: "F1", name: "Front Left"),
        ZoneConfig(id: "F2", name: "Front Right"),
    ]

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchMac")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else { return AppConfig() }
        var merged = cfg
        // new zones appear if the layout ever grows; existing config wins otherwise
        for zone in defaultZones where !merged.zones.contains(where: { $0.id == zone.id }) {
            merged.zones.append(zone)
        }
        return merged
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(self).write(to: Self.fileURL)
    }
}

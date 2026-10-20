import Foundation

public enum TapAction: Codable, Hashable {
    case none
    case openApp(String)      // full path to .app
    case shell(String)
    case volumeUp
    case volumeDown
    case mute
    case playPause
    case screenshot
    case openURL(String)
    case shortcut(String)     // Shortcuts.app shortcut name
    case nextTrack
    case previousTrack
    case missionControl
    case sleepDisplay

    /// Flat list for pickers; `text` carries the associated string, if any.
    public enum Kind: String, CaseIterable, Identifiable {
        case none = "Do nothing"
        case openApp = "Open app"
        case openURL = "Open website"
        case shortcut = "Run shortcut"
        case screenshot = "Screenshot"
        case volumeUp = "Volume up"
        case volumeDown = "Volume down"
        case mute = "Mute"
        case playPause = "Play / Pause"
        case nextTrack = "Next track"
        case previousTrack = "Previous track"
        case missionControl = "Mission Control"
        case sleepDisplay = "Sleep display"
        case shell = "Shell command"
        public var id: String { rawValue }

        public var placeholder: String? {
            switch self {
            case .openURL: return "https://example.com"
            case .shortcut: return "Shortcut name"
            case .shell: return "open -a Notes"
            default: return nil
            }
        }
    }

    public init(kind: Kind, text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .none: self = .none
        case .openApp: self = text.isEmpty ? .none : .openApp(text)
        case .openURL: self = text.isEmpty ? .none : .openURL(text)
        case .shortcut: self = text.isEmpty ? .none : .shortcut(text)
        case .shell: self = text.isEmpty ? .none : .shell(text)
        case .screenshot: self = .screenshot
        case .volumeUp: self = .volumeUp
        case .volumeDown: self = .volumeDown
        case .mute: self = .mute
        case .playPause: self = .playPause
        case .nextTrack: self = .nextTrack
        case .previousTrack: self = .previousTrack
        case .missionControl: self = .missionControl
        case .sleepDisplay: self = .sleepDisplay
        }
    }

    public var kind: Kind {
        switch self {
        case .none: return .none
        case .openApp: return .openApp
        case .openURL: return .openURL
        case .shortcut: return .shortcut
        case .shell: return .shell
        case .screenshot: return .screenshot
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .mute: return .mute
        case .playPause: return .playPause
        case .nextTrack: return .nextTrack
        case .previousTrack: return .previousTrack
        case .missionControl: return .missionControl
        case .sleepDisplay: return .sleepDisplay
        }
    }

    public var text: String {
        switch self {
        case .openApp(let s), .openURL(let s), .shortcut(let s), .shell(let s): return s
        default: return ""
        }
    }

    public var label: String {
        switch self {
        case .none: return "Not set"
        case .openApp(let path): return "Open " + ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        case .openURL(let s): return URL(string: s)?.host ?? s
        case .shortcut(let s): return "Shortcut: \(s)"
        case .shell(let cmd): return cmd.count > 28 ? String(cmd.prefix(28)) + "…" : cmd
        default: return kind.rawValue
        }
    }

    public var symbol: String {
        switch self {
        case .none: return "circle.dashed"
        case .openApp: return "app.badge.checkmark"
        case .openURL: return "safari"
        case .shortcut: return "square.2.layers.3d"
        case .shell: return "terminal"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        case .playPause: return "playpause"
        case .nextTrack: return "forward"
        case .previousTrack: return "backward"
        case .screenshot: return "camera.viewfinder"
        case .missionControl: return "rectangle.3.group"
        case .sleepDisplay: return "moon"
        }
    }
}

public struct ZoneConfig: Codable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var action: TapAction = .none
    public var doubleAction: TapAction = .none
    public var samples: [[Double]] = []   // calibration features

    public var isCalibrated: Bool { samples.count >= 5 }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey { case id, name, action, doubleAction, samples }

    // Lenient: a missing or unknown field falls back to its default instead of
    // failing the whole file (which used to wipe every zone's calibration).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? id
        action = (try? c.decode(TapAction.self, forKey: .action)) ?? .none
        doubleAction = (try? c.decode(TapAction.self, forKey: .doubleAction)) ?? .none
        samples = (try? c.decode([[Double]].self, forKey: .samples)) ?? []
    }
}

public struct AppConfig: Codable, Equatable {
    public var thresholdG = 0.04
    public var maxDistance = 6.0
    public var adaptiveThreshold = true
    public var ignoreWhileTyping = true
    public var zones: [ZoneConfig] = AppConfig.defaultZones

    public static let defaultZones = [
        ZoneConfig(id: "L1", name: "Left Near"),
        ZoneConfig(id: "L2", name: "Left Far"),
        ZoneConfig(id: "R1", name: "Right Near"),
        ZoneConfig(id: "R2", name: "Right Far"),
        ZoneConfig(id: "F1", name: "Front Left"),
        ZoneConfig(id: "F2", name: "Front Right"),
    ]

    public init() {}

    enum CodingKeys: String, CodingKey { case thresholdG, maxDistance, adaptiveThreshold, ignoreWhileTyping, zones }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        thresholdG = (try? c.decode(Double.self, forKey: .thresholdG)) ?? d.thresholdG
        maxDistance = (try? c.decode(Double.self, forKey: .maxDistance)) ?? d.maxDistance
        adaptiveThreshold = (try? c.decode(Bool.self, forKey: .adaptiveThreshold)) ?? d.adaptiveThreshold
        ignoreWhileTyping = (try? c.decode(Bool.self, forKey: .ignoreWhileTyping)) ?? d.ignoreWhileTyping
        var zones = (try? c.decode([ZoneConfig].self, forKey: .zones)) ?? []
        // new zones appear if the layout ever grows; existing config wins otherwise
        for zone in Self.defaultZones where !zones.contains(where: { $0.id == zone.id }) {
            zones.append(zone)
        }
        self.zones = zones
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TouchMac/config.json")
    }

    /// Returns the config and, when the file was unreadable, a note saying where the bad copy went.
    /// A broken file is moved aside, never overwritten.
    public static func load(from url: URL = defaultURL) -> (AppConfig, warning: String?) {
        guard let data = try? Data(contentsOf: url) else { return (AppConfig(), nil) }
        if let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) { return (cfg, nil) }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingPathExtension().appendingPathExtension("broken-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return (AppConfig(), "Your settings file could not be read. A copy was saved as \(backup.lastPathComponent).")
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}

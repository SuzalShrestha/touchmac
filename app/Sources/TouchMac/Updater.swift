import AppKit
import Sparkle

/// In-app updates. Sparkle reads `appcast.xml` from the latest GitHub release and installs an
/// update only if its EdDSA signature matches `SUPublicEDKey` in Info.plist.
@Observable @MainActor
final class Updater: NSObject {
    static let releasesURL = URL(string: "https://github.com/SuzalShrestha/touchmac/releases")!

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    var canCheck = false
    var lastCheck: Date?
    /// Found by a scheduled check while TouchMac sat in the menu bar; shown until the user looks at it.
    var pendingVersion: String?
    var automaticallyChecks = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    var automaticallyInstalls = false {
        didSet { controller?.updater.automaticallyDownloadsUpdates = automaticallyInstalls }
    }

    /// False in builds without a public key (local builds): there is nothing to verify an update against.
    var isConfigured: Bool { controller != nil }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    override init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty, Snapshot.directory == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyInstalls = updater.automaticallyDownloadsUpdates
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] u, _ in
                let can = u.canCheckForUpdates
                Task { @MainActor in self?.canCheck = can }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] u, _ in
                let date = u.lastUpdateCheckDate
                Task { @MainActor in self?.lastCheck = date }
            },
        ]
    }

    func checkForUpdates() {
        pendingVersion = nil
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    /// TouchMac is a menu bar app: a scheduled check must not steal focus. We show a badge instead.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.pendingVersion = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pendingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pendingVersion = nil }
    }
}

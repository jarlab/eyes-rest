import AppKit
import EyeRestCore
import ServiceManagement

/// The "Open at login" setting. `SMAppService.mainApp` is the only source of truth; nothing is stored separately.
@MainActor
public final class LaunchAtLoginModel: ObservableObject {
    /// False outside an app bundle (e.g. `swift run`) and for a bundle outside /Applications or ~/Applications, where
    /// login items are unreliable.
    public let isAvailable = AppEnvironment.isBundledApp && AppEnvironment.isInstalledInApplications
    /// On while registered, including while waiting for the user's approval.
    @Published public private(set) var isEnabled = false
    @Published public private(set) var requiresApproval = false
    /// A description of the last failed register/unregister, cleared by the next success.
    @Published public private(set) var lastError: String?

    private var activationObserver: NSObjectProtocol?

    public init() {
        refresh()
        // The user may approve or remove the login item in System Settings while EyeRest runs.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Re-reads the registration status.
    public func refresh() {
        let status = SMAppService.mainApp.status
        let enabled = status == .enabled || status == .requiresApproval
        let approval = status == .requiresApproval
        if isEnabled != enabled { isEnabled = enabled }
        if requiresApproval != approval { requiresApproval = approval }
    }

    /// Registers or unregisters EyeRest as a login item. Does nothing unless `isAvailable`.
    public func setEnabled(_ enabled: Bool) {
        guard isAvailable, enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            let action = enabled ? "turn on" : "turn off"
            lastError = "Couldn't \(action) Open at login: \(error.localizedDescription)"
        }
        refresh()
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

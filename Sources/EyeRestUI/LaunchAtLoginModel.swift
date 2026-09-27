import AppKit
import EyeRestCore
import ServiceManagement

/// The "Open at login" setting. `SMAppService.mainApp` is the only source of truth; nothing is stored separately.
@MainActor
public final class LaunchAtLoginModel: ObservableObject {
    public enum Availability: Equatable, Sendable {
        case available
        /// Running outside an app bundle (e.g. `swift run`).
        case notBundled
        /// A bundle outside /Applications or ~/Applications, where login items are unreliable.
        case notInApplications
    }

    public let availability: Availability
    /// On while registered, including while waiting for the user's approval.
    @Published public private(set) var isEnabled = false
    @Published public private(set) var requiresApproval = false
    /// A description of the last failed register/unregister, cleared by the next success.
    @Published public private(set) var lastError: String?

    private var activationObserver: NSObjectProtocol?

    public init() {
        if !AppEnvironment.isBundledApp {
            availability = .notBundled
        } else if !AppEnvironment.isInstalledInApplications {
            availability = .notInApplications
        } else {
            availability = .available
        }
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

    /// Registers or unregisters EyeRest as a login item. Does nothing unless `availability` is `.available`.
    public func setEnabled(_ enabled: Bool) {
        guard availability == .available, enabled != isEnabled else { return }
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

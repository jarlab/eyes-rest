import AppKit
import EyeRestCore

/// App lifecycle: the main menu, single-instance enforcement, the paths that bring Settings forward and handing
/// keyboard focus back when EyeRest's last window closes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Posted by a second copy of EyeRest just before it quits, asking the running copy to show Settings.
    private static let showSettingsNotification = Notification.Name("com.balraj.EyeRest.showSettings")

    private var controller: AppController?
    private var showSettingsObserver: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only an app bundle has an identity to share with other copies; `swift run` builds skip this.
        if AppEnvironment.isBundledApp {
            // Observe first, so a copy launched right after this one can already reach it.
            showSettingsObserver = DistributedNotificationCenter.default().addObserver(
                forName: Self.showSettingsNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.controller?.showSettings() }
            }
            guard !isAnotherInstanceRunning() else {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.showSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true
                )
                NSApp.terminate(nil)
                return
            }
        }

        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow, window.styleMask.contains(.titled) else { return }
                // The closing window is still visible now; check once it is gone.
                DispatchQueue.main.async { Self.hideIfNoTitledWindowIsOpen() }
            }
        }

        let controller = AppController()
        self.controller = controller
        controller.start()
    }

    /// Opening EyeRest while it runs (Finder, Spotlight, Launchpad) shows Settings. This is also the way back when
    /// the menu-bar icon is hidden behind the notch or an overflowing menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.showSettings()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Main menu actions

    @objc func showSettings(_ sender: Any?) {
        controller?.showSettings()
    }

    @objc func showAbout(_ sender: Any?) {
        controller?.showAbout()
    }

    /// An accessory app stays active with no windows after its last window (Settings or the About panel) closes,
    /// which leaves the user without keyboard focus. Hiding EyeRest hands focus back to the previous app. The reminder
    /// card's panel is borderless and can't hide, so it neither counts nor disappears.
    private static func hideIfNoTitledWindowIsOpen() {
        guard NSApp.isActive,
              !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) })
        else { return }
        NSApp.hide(nil)
    }

    /// True when another copy of EyeRest started before this one, which then keeps running. Copies launched
    /// together agree on a single survivor: the earlier launch, or the lower PID when a launch date is missing or
    /// equal. Copies that are already quitting don't count.
    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains { other in
            other.processIdentifier != current.processIdentifier && !other.isTerminated
                && Self.launchedBefore(other, current)
        }
    }

    private static func launchedBefore(_ app: NSRunningApplication, _ other: NSRunningApplication) -> Bool {
        if let date = app.launchDate, let otherDate = other.launchDate, date != otherDate {
            return date < otherDate
        }
        return app.processIdentifier < other.processIdentifier
    }
}

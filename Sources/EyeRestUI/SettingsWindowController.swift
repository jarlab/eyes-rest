import AppKit
import SwiftUI

/// Owns the "EyeRest Settings" window.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsModel
    private let launchAtLogin: LaunchAtLoginModel
    private var window: NSWindow?

    public init(model: SettingsModel, launchAtLogin: LaunchAtLoginModel) {
        self.model = model
        self.launchAtLogin = launchAtLogin
        super.init()
    }

    /// Brings the window to the front, activating EyeRest.
    public func show() {
        launchAtLogin.refresh()
        let window = window ?? makeWindow()
        // `activate()` and activation-policy changes do not bring an accessory app forward without a user
        // click; `activate(ignoringOtherApps:)` does.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        // End editing so a half-typed value is committed. (Handing keyboard focus back to the previous app is up to
        // the app delegate, which does it for every titled window.)
        window?.makeFirstResponder(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = NSHostingController(rootView: SettingsView(model: model, launchAtLogin: launchAtLogin))
        // The window's height follows the form's, e.g. when the login-item approval row appears.
        content.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: content)
        window.styleMask = [.titled, .closable]
        window.title = "EyeRest Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        // Size before centring: the window only takes the form's size on a later layout pass, keeping its top-left
        // corner, so centring the initial placeholder size would leave the real window off-centre.
        window.setContentSize(content.view.fittingSize)
        window.center()
        self.window = window
        return window
    }
}

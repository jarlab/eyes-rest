import AppKit
import SwiftUI

/// Owns the "EyeRest Settings" window.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Called when the window closes.
    public var onClose: (() -> Void)?

    public var isVisible: Bool { window?.isVisible ?? false }

    private static let styleMask: NSWindow.StyleMask = [.titled, .closable]
    private static let titleBarHeight = NSWindow.frameRect(forContentRect: .zero, styleMask: styleMask).height

    private let model: SettingsModel
    private let launchAtLogin: LaunchAtLoginModel
    private let presentation = SettingsPresentation()
    private var window: NSWindow?

    public init(model: SettingsModel, launchAtLogin: LaunchAtLoginModel) {
        self.model = model
        self.launchAtLogin = launchAtLogin
        super.init()
    }

    /// Brings the window to the front, activating EyeRest. `welcome` adds the first-launch header; once shown it
    /// stays until the window closes.
    public func show(welcome: Bool) {
        presentation.showsWelcome = welcome || (isVisible && presentation.showsWelcome)
        if let screen = window?.screen ?? NSScreen.main {
            presentation.maxHeight = screen.visibleFrame.height - Self.titleBarHeight
        }
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
        onClose?()
    }

    private func makeWindow() -> NSWindow {
        let content = NSHostingController(
            rootView: SettingsView(model: model, launchAtLogin: launchAtLogin, presentation: presentation)
        )
        // The window's height follows the form's, e.g. when the welcome header or a footer appears.
        content.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: content)
        window.styleMask = Self.styleMask
        window.title = "EyeRest Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = self
        // The window only takes the form's size on a later layout pass, keeping its top-left corner; centring the
        // initial 1-pt window would leave the real one off-centre and hanging below the screen. `show` has already
        // capped the height to the screen.
        window.setContentSize(content.preferredContentSize)
        window.center()
        self.window = window
        return window
    }
}

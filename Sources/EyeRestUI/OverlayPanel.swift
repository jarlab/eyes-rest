import AppKit
import SwiftUI

/// A borderless, full-screen panel for the break overlay. It floats above everything, including the menu bar
/// and full-screen apps, and can become key without activating EyeRest, so it receives keystrokes while the
/// user's app stays frontmost.
final class OverlayPanel: NSPanel {
    /// Creates a panel covering `screen`.
    ///
    /// The four-argument initializer is used because the `screen:` variant treats the rect as relative to that
    /// screen, which misplaces panels on secondary displays. `.nonactivatingPanel` is set here and never toggled.
    convenience init(screen: NSScreen) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A hosting view that acts on the first click even when its window is not key, so buttons on a
/// non-key panel work with a single click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    /// The screen containing the mouse pointer, falling back to the main screen, then the first screen.
    static var withMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main ?? screens.first
    }
}

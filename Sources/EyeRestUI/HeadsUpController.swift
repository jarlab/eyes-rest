import AppKit
import EyeRestCore
import SwiftUI

/// A floating panel that can never become key, so it never takes keystrokes from the user's app.
final class HeadsUpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the "Eye break in N seconds" pill near the top of the screen under the mouse.
@MainActor
public final class HeadsUpController {
    public struct Actions {
        public var startNow: @MainActor () -> Void
        public var snooze: @MainActor () -> Void

        public init(startNow: @escaping @MainActor () -> Void, snooze: @escaping @MainActor () -> Void) {
            self.startNow = startNow
            self.snooze = snooze
        }
    }

    public private(set) var isVisible = false

    private static let fadeDuration: TimeInterval = 0.2
    private static let cornerRadius: CGFloat = 14
    /// Gap between the menu bar (top of the visible frame) and the pill.
    private static let topMargin: CGFloat = 12
    private static let minimumWidth: CGFloat = 340

    private let actions: Actions
    private var reduceMotion = false
    private lazy var hostingView: FirstMouseHostingView<HeadsUpView> = makeHostingView()
    private lazy var panel: HeadsUpPanel = makePanel()

    public init(actions: Actions) {
        self.actions = actions
    }

    /// Shows the pill, or updates it if it is already visible.
    public func show(secondsLeft: Int, allowSnooze: Bool, snoozeMinutes: Int) {
        let secondsLeft = max(1, secondsLeft)
        hostingView.rootView = HeadsUpView(
            secondsLeft: secondsLeft,
            allowSnooze: allowSnooze,
            snoozeMinutes: snoozeMinutes,
            actions: actions
        )
        if isVisible {
            // Keeps the pill where it is; only its width can change (when the snooze button comes or goes).
            if let screen = panel.screen ?? NSScreen.withMouse { place(on: screen) }
            return
        }

        isVisible = true
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if let screen = NSScreen.withMouse { place(on: screen) }
        panel.ignoresMouseEvents = false
        panel.alphaValue = reduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        if !reduceMotion {
            let panel = panel
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panel.animator().alphaValue = 1
            }
        }
        VoiceOver.announce(StatusText.headsUpText(secondsLeft: secondsLeft) + ".")
    }

    public func hide() {
        guard isVisible else { return }
        isVisible = false
        let panel = panel
        // Clicks pass through the fading pill, so a double-click can't snooze twice.
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : Self.fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Skip the order-out if the pill was shown again while fading.
                guard let self, !self.isVisible else { return }
                panel.orderOut(nil)
            }
        }
    }

    /// Sizes the panel to its content and centres it horizontally just below the menu bar of `screen`.
    private func place(on screen: NSScreen) {
        let fitting = hostingView.fittingSize
        let size = NSSize(width: max(Self.minimumWidth, fitting.width.rounded(.up)), height: HeadsUpView.height)
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: visible.maxY - Self.topMargin - size.height,
            width: size.width,
            height: size.height
        )
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private func makeHostingView() -> FirstMouseHostingView<HeadsUpView> {
        let view = FirstMouseHostingView(
            rootView: HeadsUpView(secondsLeft: 10, allowSnooze: false, snoozeMinutes: 0, actions: actions)
        )
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }

    private func makePanel() -> HeadsUpPanel {
        let panel = HeadsUpPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.minimumWidth, height: HeadsUpView.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        // Stays visible while EyeRest is hidden (it hides itself after Settings closes) or inactive.
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isMovable = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        panel.contentView = background
        hostingView.frame = background.bounds
        hostingView.autoresizingMask = [.width, .height]
        background.addSubview(hostingView)
        return panel
    }

    /// A stretchable rounded-rectangle mask, the supported way to round an `NSVisualEffectView`.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

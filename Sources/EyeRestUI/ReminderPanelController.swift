import AppKit
import SwiftUI

/// Shows the reminder card in the top-right corner of the screen with the mouse, just under the menu bar, like a
/// notification.
///
/// The card never blocks: its panel can't become key or main and never activates EyeRest, so the user's app keeps
/// the keyboard and the rest of the screen stays usable, while a single click still works on Done.
@MainActor
public final class ReminderPanelController {
    public private(set) var isVisible = false

    /// The visible card's distance from the right edge of the screen and from the bottom of the menu bar.
    private static let rightInset: CGFloat = 16
    private static let topInset: CGFloat = 12
    /// The float-in starts this far above the card's resting place.
    private static let floatDistance: CGFloat = 8
    private static let fadeInDuration: TimeInterval = 0.35
    private static let fadeOutDuration: TimeInterval = 0.25
    /// How long after its scheduled end the card closes itself if the app never closed it.
    private static let failsafeDelay: TimeInterval = 5

    private let onDone: @MainActor () -> Void
    private let model = ReminderCardModel()
    /// The card's view (internal so offscreen render checks can draw the real thing).
    lazy var hostingView: FirstMouseHostingView<ReminderPanelContent> = {
        let view = FirstMouseHostingView(rootView: ReminderPanelContent(model: model) { [weak self] in self?.done() })
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }()
    private lazy var panel: NSPanel = makePanel()
    private var failsafeTimer: Timer?
    /// The card that the failsafe closed; `show` ignores it from then on.
    private var failsafeTrippedEndsAt: Date?

    /// `onDone` runs when the user clicks Done.
    public init(onDone: @escaping @MainActor () -> Void) {
        self.onDone = onDone
    }

    /// Floats the card in (it just appears with Reduce Motion) and announces it to VoiceOver. Does nothing if the
    /// card is already up, or if the failsafe already closed the card ending at `endsAt`.
    public func show(endsAt: Date, remaining: TimeInterval, progress: Double) {
        guard !isVisible, endsAt != failsafeTrippedEndsAt else { return }
        isVisible = true
        update(remaining: remaining, progress: progress)
        place(on: NSScreen.withMouse)

        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let panel = panel, hostingView = hostingView
        panel.alphaValue = animated ? 0 : 1
        // The content slides inside the panel (into its shadow margin), so the panel never overlaps the menu bar.
        hostingView.setFrameOrigin(NSPoint(x: 0, y: animated ? Self.floatDistance : 0))
        panel.orderFrontRegardless()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeInDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                hostingView.animator().setFrameOrigin(.zero)
            }
        }

        scheduleFailsafe(endsAt: endsAt)
        Self.announce("Time to rest your eyes. Look away for \(ReminderCardView.spokenSeconds(remaining)).")
    }

    /// Updates the countdown and ring.
    public func update(remaining: TimeInterval, progress: Double) {
        if model.remaining != remaining { model.remaining = remaining }
        if model.progress != progress { model.progress = progress }
    }

    /// Fades the card out (instantly with Reduce Motion). Does nothing if it is hidden.
    public func hide() {
        guard isVisible else { return }
        isVisible = false
        failsafeTimer?.invalidate()
        failsafeTimer = nil
        let panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Skip the order-out if the card was shown again while fading.
                guard let self, !self.isVisible else { return }
                panel.orderOut(nil)
            }
        }
    }

    // MARK: - Internals

    private func done() {
        guard isVisible else { return }
        onDone()
    }

    /// Sizes the panel to the card plus its shadow margin and puts the visible card `rightInset` from the right edge
    /// and `topInset` below the menu bar of `screen`.
    private func place(on screen: NSScreen?) {
        let size = hostingView.fittingSize
        hostingView.setFrameSize(size)
        guard let screen else { return }
        let margin = Aero.shadowMargin
        panel.setFrame(NSRect(x: screen.visibleFrame.maxX - Self.rightInset + margin.trailing - size.width,
                              y: screen.menuBarBottom - Self.topInset + margin.top - size.height,
                              width: size.width, height: size.height), display: false)
    }

    private func makePanel() -> NSPanel {
        let panel = ReminderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary,
                                    .ignoresCycle]
        panel.isReleasedWhenClosed = false
        // Stays up while EyeRest is inactive or hidden (it hides itself when Settings closes).
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card draws its own shadow; a window shadow would outline the transparent margin.
        panel.hasShadow = false
        panel.animationBehavior = .none
        let container = NSView()
        container.addSubview(hostingView)
        panel.contentView = container
        return panel
    }

    /// Closes the card shortly after it should have ended, in case the app's own timer has stopped.
    private func scheduleFailsafe(endsAt: Date) {
        let timer = Timer(fire: endsAt.addingTimeInterval(Self.failsafeDelay), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.failsafeFired(endsAt: endsAt) }
        }
        RunLoop.main.add(timer, forMode: .common)
        failsafeTimer = timer
    }

    private func failsafeFired(endsAt: Date) {
        guard isVisible else { return }
        failsafeTrippedEndsAt = endsAt
        hide()
    }

    /// Asks VoiceOver to speak `message` at high priority. Does nothing when VoiceOver is off.
    private static func announce(_ message: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}

/// The card's live values.
@MainActor
final class ReminderCardModel: ObservableObject {
    @Published var remaining: TimeInterval = 0
    @Published var progress: Double = 0
}

/// The card as hosted in the panel, following the system's Reduce Transparency and Increase Contrast settings.
struct ReminderPanelContent: View {
    @ObservedObject var model: ReminderCardModel
    var onDone: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ReminderCardView(remaining: model.remaining, progress: model.progress, reduceTransparency: reduceTransparency,
                         increaseContrast: colorSchemeContrast == .increased, onDone: onDone)
    }
}

/// A panel that can never become key or main, so the card never takes focus from the user's app.
private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A hosting view that acts on the first click even though its window is never key, so Done works with one click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private extension NSScreen {
    /// The screen containing the mouse pointer, falling back to the main screen, then the first screen.
    static var withMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main ?? screens.first
    }

    /// Where the bottom of the menu bar is, or would be when it is hidden (auto-hide, full-screen Spaces), since
    /// `visibleFrame` then reserves no room for it. Screens that never show a menu bar use their visible top.
    var menuBarBottom: CGFloat {
        let visibleTop = visibleFrame.maxY
        guard NSScreen.screensHaveSeparateSpaces || self == NSScreen.screens.first else { return visibleTop }
        // A menu bar is 24 pt, or as tall as the notch's safe area on displays with a camera housing.
        return min(visibleTop, frame.maxY - max(safeAreaInsets.top, 24))
    }
}

import AppKit
import EyeRestCore
import SwiftUI

/// What the break overlay shows. It is fixed for the length of one break.
public struct BreakOverlayContent: Equatable, Sendable {
    public var tip: String
    public var breakDuration: TimeInterval
    public var allowSkip: Bool
    public var allowSnooze: Bool
    public var snoozeMinutes: Int

    public init(tip: String, breakDuration: TimeInterval, allowSkip: Bool, allowSnooze: Bool, snoozeMinutes: Int) {
        self.tip = tip
        self.breakDuration = breakDuration
        self.allowSkip = allowSkip
        self.allowSnooze = allowSnooze
        self.snoozeMinutes = snoozeMinutes
    }
}

/// Covers every screen with the break overlay and handles its keyboard input.
///
/// The overlay never activates EyeRest: the panel under the mouse becomes key (so it gets keystrokes) while the
/// user's app stays frontmost, and focus returns to it untouched when the panels are ordered out.
@MainActor
public final class BreakOverlayController {
    public struct Actions {
        public var skip: @MainActor () -> Void
        public var snooze: @MainActor () -> Void

        public init(skip: @escaping @MainActor () -> Void, snooze: @escaping @MainActor () -> Void) {
            self.skip = skip
            self.snooze = snooze
        }
    }

    public private(set) var isVisible = false

    private static let fadeDuration: TimeInterval = 0.4
    /// Keystrokes this soon after the overlay appears are ignored, so typing can't skip a break by reflex.
    private static let inputGuard: TimeInterval = 1
    /// How long after the scheduled end the overlay closes itself if the app never did.
    private static let failsafeDelay: TimeInterval = 5
    private static let escapeKeyCode: UInt16 = 53

    private let actions: Actions
    private var model: BreakOverlayModel?
    private var panels: [OverlayPanel] = []
    private var endsAt: Date?
    /// `ProcessInfo.systemUptime` when the overlay appeared, comparable with `NSEvent.timestamp`.
    private var shownAtUptime: TimeInterval = 0
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var failsafeTimer: Timer?
    private var emergencyHoldTimer: Timer?
    /// The break whose overlay the failsafe closed; `show` ignores it from then on.
    private var failsafeTrippedEndsAt: Date?

    public init(actions: Actions) {
        self.actions = actions
    }

    /// Shows the overlay on every screen. Does nothing if it is already visible or if the failsafe has already
    /// closed the overlay for the break ending at `endsAt`.
    public func show(content: BreakOverlayContent, endsAt: Date, remaining: TimeInterval, progress: Double) {
        guard !isVisible, endsAt != failsafeTrippedEndsAt else { return }
        let model = BreakOverlayModel(content: content, accessibility: .current, remaining: remaining, progress: progress)
        self.model = model
        self.endsAt = endsAt
        isVisible = true
        shownAtUptime = ProcessInfo.processInfo.systemUptime

        showPanels(fadeIn: !model.accessibility.reduceMotion)
        installKeyMonitor()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels() }
        }
        scheduleFailsafe(for: endsAt)
        VoiceOver.announce(
            "Break started. Look away from the screen for \(TimeFormatting.duration(content.breakDuration))."
        )
    }

    /// Updates the countdown and ring.
    public func update(remaining: TimeInterval, progress: Double) {
        guard let model else { return }
        if model.remaining != remaining { model.remaining = remaining }
        if model.progress != progress { model.progress = progress }
    }

    /// Closes the overlay; `completed` announces "Break over." to VoiceOver. Does nothing if it is hidden.
    public func hide(completed: Bool) {
        guard isVisible else { return }
        isVisible = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        failsafeTimer?.invalidate()
        failsafeTimer = nil
        emergencyHoldTimer?.invalidate()
        emergencyHoldTimer = nil

        // The key monitor stays until the panels are gone: a keystroke reaching the fading key panel would beep.
        // With `model` cleared it only swallows keys.
        retire(panels, animated: !(model?.accessibility.reduceMotion ?? true)) { [weak self] in
            guard let self, !isVisible else { return }  // shown again meanwhile: the monitor is in use
            removeKeyMonitor()
        }
        panels = []
        model = nil
        endsAt = nil
        if completed { VoiceOver.announce("Break over.") }
    }

    // MARK: - Panels

    /// Puts one panel on each screen; the one under the mouse becomes key.
    private func showPanels(fadeIn: Bool) {
        guard let model else { return }
        let screens = NSScreen.screens
        let keyScreen = NSScreen.withMouse
        let keyIndex = screens.firstIndex { $0 == keyScreen } ?? 0
        panels = screens.map { makePanel(for: $0, model: model) }
        for (index, panel) in panels.enumerated() {
            panel.alphaValue = fadeIn ? 0 : 1
            if index == keyIndex {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
        guard fadeIn else { return }
        let panels = panels
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            for panel in panels { panel.animator().alphaValue = 1 }
        }
    }

    private func makePanel(for screen: NSScreen, model: BreakOverlayModel) -> OverlayPanel {
        let panel = OverlayPanel(screen: screen)
        panel.appearance = NSAppearance(named: .darkAqua)
        let hostingView = FirstMouseHostingView(rootView: BreakOverlayView(model: model, actions: actions))
        hostingView.sizingOptions = []
        if model.accessibility.reduceTransparency {
            panel.contentView = hostingView
        } else {
            let blur = NSVisualEffectView()
            blur.material = .fullScreenUI
            blur.blendingMode = .behindWindow
            blur.state = .active
            panel.contentView = blur
            hostingView.frame = blur.bounds
            hostingView.autoresizingMask = [.width, .height]
            blur.addSubview(hostingView)
        }
        return panel
    }

    /// Replaces the panels after displays are added, removed or rearranged.
    private func rebuildPanels() {
        guard isVisible else { return }
        let oldPanels = panels
        showPanels(fadeIn: false)
        retire(oldPanels, animated: false)
    }

    /// Fades the panels out (instantly with Reduce Motion), then orders them out and calls `completion`. Clicks pass
    /// through fading panels, so a second click can't press Skip or Snooze again. The order-out runs from the
    /// animation's completion, which AppKit calls asynchronously, so a panel is never released while the Skip or
    /// Snooze click that closed it is still being dispatched to it.
    private func retire(
        _ panels: [OverlayPanel], animated: Bool, completion: @escaping @MainActor () -> Void = {}
    ) {
        guard !panels.isEmpty else {
            completion()
            return
        }
        for panel in panels { panel.ignoresMouseEvents = true }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? Self.fadeDuration : 0
            for panel in panels { panel.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated {
                for panel in panels { panel.orderOut(nil) }
                completion()
            }
        }
    }

    // MARK: - Keyboard

    /// Swallows every key event while the overlay is up and while it fades out; only Esc does anything. Keeps the
    /// monitor if it is still installed from the previous overlay's fade-out.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            self?.handleKey(event)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleKey(_ event: NSEvent) {
        guard event.keyCode == Self.escapeKeyCode, let model else { return }
        switch event.type {
        case .keyDown:
            guard !event.isARepeat, event.timestamp - shownAtUptime >= Self.inputGuard else { return }
            if model.content.allowSkip {
                actions.skip()
            } else {
                beginEmergencyHold()
            }
        case .keyUp:
            cancelEmergencyHold()
        default:
            break
        }
    }

    /// Starts the hold-Esc escape hatch used when skipping is turned off.
    private func beginEmergencyHold() {
        guard emergencyHoldTimer == nil, let model else { return }
        model.emergencyHoldStartedAt = Date()
        let timer = Timer(timeInterval: BreakOverlayModel.emergencyHoldDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.completeEmergencyHold() }
        }
        RunLoop.main.add(timer, forMode: .common)
        emergencyHoldTimer = timer
    }

    private func cancelEmergencyHold() {
        emergencyHoldTimer?.invalidate()
        emergencyHoldTimer = nil
        model?.emergencyHoldStartedAt = nil
    }

    private func completeEmergencyHold() {
        emergencyHoldTimer = nil
        model?.emergencyHoldStartedAt = nil
        actions.skip()
    }

    // MARK: - Failsafe

    /// Closes the overlay shortly after the break should have ended, in case the app's own timer has stopped.
    private func scheduleFailsafe(for endsAt: Date) {
        let timer = Timer(fire: endsAt.addingTimeInterval(Self.failsafeDelay), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.failsafeFired(endsAt: endsAt) }
        }
        RunLoop.main.add(timer, forMode: .common)
        failsafeTimer = timer
    }

    private func failsafeFired(endsAt: Date) {
        guard isVisible, self.endsAt == endsAt else { return }
        failsafeTrippedEndsAt = endsAt
        hide(completed: true)
    }
}

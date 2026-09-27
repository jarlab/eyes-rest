import AppKit
import EyeRestCore
import EyeRestSystem
import EyeRestUI

/// Wires the break scheduler to the clock, the OS signals, the stores and every piece of UI.
///
/// Two rules keep the app consistent with the scheduler:
/// - Stats and sounds come only from scheduler events, so each break is counted and chimed exactly once.
/// - The UI follows the scheduler's state after every scheduler call, so it can never get stuck out of step.
@MainActor
final class AppController {
    /// UserDefaults key set once the first-launch Settings window has been closed.
    private static let onboardingCompletedKey = "onboarding.v1.completed"
    /// The camera and microphone are only checked when a break is at most this many seconds away (or already held).
    private static let callCheckLeadTime: TimeInterval = 35
    /// The heads-up appears when a break is at most this many seconds away.
    private static let headsUpLeadTime: TimeInterval = 10
    private static let pausedUntilStyle = Date.FormatStyle(date: .omitted, time: .shortened)

    private let defaults: UserDefaults
    private let settingsStore: SettingsStore
    private let statsStore: StatsStore
    private var scheduler: BreakScheduler
    private var stats: DailyStats
    /// How the last break ended, used to tell the overlay whether to announce "Break over."
    private var lastBreakOutcome: BreakOutcome?

    private let settingsModel: SettingsModel
    private let launchAtLogin = LaunchAtLoginModel()
    private let idleTime = EffectiveIdleTime()
    private let monitor: SystemActivityMonitor
    private let soundPlayer = SoundPlayer()
    /// Keeps App Nap from throttling the timer for the app's whole lifetime; idle and display sleep still happen.
    private let activity: NSObjectProtocol
    private var timer: Timer?
    /// The time of the tick in progress. Changes that `monitor.poll` reports during the tick use it, so every
    /// scheduler call in one tick sees the same instant.
    private var tickTime: Date?

    private lazy var settingsWindow: SettingsWindowController = {
        let controller = SettingsWindowController(model: settingsModel, launchAtLogin: launchAtLogin)
        controller.onClose = { [weak self] in
            self?.defaults.set(true, forKey: Self.onboardingCompletedKey)
        }
        return controller
    }()

    // `postpone` also pushes back an upcoming break (stacking), so a snooze click that arrives after its break or
    // heads-up has ended must be dropped: for example the second click of a double-click, which can land on the
    // panel while it fades out, or a click in the instant the break completes.
    private lazy var overlay = BreakOverlayController(actions: .init(
        skip: { [weak self] in self?.perform { $0.skipBreak(now: $1) } },
        snooze: { [weak self] in
            self?.perform { scheduler, now in
                guard let remaining = scheduler.breakTimeRemaining(now: now), remaining > 0 else { return [] }
                return scheduler.postpone(now: now)
            }
        }
    ))

    private lazy var headsUp: HeadsUpController = HeadsUpController(actions: .init(
        startNow: { [weak self] in
            guard let self, headsUp.isVisible else { return }
            perform { $0.takeBreakNow(now: $1) }
        },
        snooze: { [weak self] in
            guard let self, headsUp.isVisible else { return }
            perform { $0.postpone(now: $1) }
        }
    ))

    private lazy var statusItem = StatusItemController(display: statusDisplay(now: Date()), actions: .init(
        takeBreakNow: { [weak self] in self?.perform { $0.takeBreakNow(now: $1) } },
        pause: { [weak self] duration in self?.perform { $0.pause(for: duration, now: $1) } },
        resume: { [weak self] in self?.perform { $0.resume(now: $1) } },
        resetTimer: { [weak self] in self?.perform { $0.resetCycle(now: $1) } },
        showSettings: { [weak self] in self?.showSettings() },
        showAbout: { [weak self] in self?.showAbout() }
    ))

    init(defaults: UserDefaults = .standard) {
        let now = Date()
        let settingsStore = SettingsStore(defaults: defaults)
        let statsStore = StatsStore(defaults: defaults)
        let scheduler = BreakScheduler(settings: settingsStore.load(), now: now)
        self.defaults = defaults
        self.settingsStore = settingsStore
        self.statsStore = statsStore
        self.scheduler = scheduler
        stats = statsStore.load(now: now)
        // A lock or display sleep counts from the last sign of the user, which includes watching a video.
        monitor = SystemActivityMonitor(awayIdleSeconds: { [idleTime] in idleTime.seconds() })
        settingsModel = SettingsModel(settings: scheduler.settings)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Eye break timer"
        )
    }

    /// Starts the OS observers and the 1 Hz timer, runs a first tick (which puts the icon in the menu bar) and opens
    /// the welcome on first launch.
    func start() {
        settingsModel.onChange = { [weak self] settings in self?.settingsDidChange(settings) }
        monitor.onChange = { [weak self] change in self?.systemActivityDidChange(change) }
        monitor.start()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // `.common` keeps the timer firing while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()

        if !defaults.bool(forKey: Self.onboardingCompletedKey) {
            settingsWindow.show(welcome: true)
        }
    }

    func showSettings() {
        settingsWindow.show(welcome: false)
    }

    func showAbout() {
        // An accessory app must activate itself, or the panel opens behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // MARK: - Driving the scheduler

    private func tick() {
        let now = Date()
        tickTime = now
        defer { tickTime = nil }

        handle(scheduler.observeIdle(seconds: idleTime.seconds(), now: now), now: now)
        monitor.poll(now: now)
        handle(scheduler.tick(now: now, holdBreak: shouldHoldBreakForCall(now: now)), now: now)
        syncUI(now: now)
    }

    /// Whether a due break should wait because the user is on a call. The camera and microphone are only queried
    /// close to a break, not every second of the day.
    private func shouldHoldBreakForCall(now: Date) -> Bool {
        guard scheduler.settings.holdDuringCalls else { return false }
        let breakIsNear = scheduler.timeUntilNextBreak(now: now).map { $0 <= Self.callCheckLeadTime } ?? false
        guard breakIsNear || scheduler.isHoldingBreak else { return false }
        return CallDetector.isInCall()
    }

    /// Runs one scheduler call, handles its events and brings the UI in line with the resulting state.
    private func perform(at now: Date = Date(), _ call: (inout BreakScheduler, Date) -> [SchedulerEvent]) {
        handle(call(&scheduler, now), now: now)
        syncUI(now: now)
    }

    private func systemActivityDidChange(_ change: SystemActivityMonitor.Change) {
        perform(at: tickTime ?? Date()) { scheduler, now in
            switch change {
            case let .began(reason, since): scheduler.beginAway(reason, since: since, now: now)
            case let .ended(reason): scheduler.endAway(reason, now: now)
            }
        }
    }

    private func settingsDidChange(_ settings: EyeRestSettings) {
        let now = Date()
        let events = scheduler.updateSettings(settings, now: now)
        settingsStore.save(scheduler.settings)
        handle(events, now: now)
        syncUI(now: now)
    }

    /// Reacts to scheduler events in order. This is the only place stats are recorded and sounds are played.
    private func handle(_ events: [SchedulerEvent], now: Date) {
        for event in events {
            switch event {
            case .breakStarted:
                statusItem.cancelMenuTracking()
            case let .breakEnded(outcome):
                lastBreakOutcome = outcome
                stats.record(outcome, at: now)
                statsStore.save(stats)
                if outcome == .completed && scheduler.settings.playSounds {
                    soundPlayer.playBreakEnded()
                }
            case .paused, .resumed, .wentAway, .returned, .cycleRestarted:
                break
            }
        }
    }

    // MARK: - UI

    /// Makes every piece of UI match the scheduler's current state.
    private func syncUI(now: Date) {
        // The heads-up goes first so it is gone before the overlay appears.
        syncHeadsUp(now: now)
        syncOverlay(now: now)
        statusItem.update(statusDisplay(now: now))
    }

    private func syncHeadsUp(now: Date) {
        let settings = scheduler.settings
        guard settings.showHeadsUp, !scheduler.isHoldingBreak,
              let remaining = scheduler.timeUntilNextBreak(now: now), remaining <= Self.headsUpLeadTime
        else {
            headsUp.hide()
            return
        }
        headsUp.show(
            secondsLeft: max(1, Int(remaining.rounded(.up))),
            allowSnooze: settings.allowPostpone,
            snoozeMinutes: settings.postponeMinutes
        )
    }

    private func syncOverlay(now: Date) {
        guard case let .onBreak(startedAt, endsAt) = scheduler.state else {
            if overlay.isVisible { overlay.hide(completed: lastBreakOutcome == .completed) }
            return
        }
        let remaining = scheduler.breakTimeRemaining(now: now) ?? 0
        let progress = scheduler.breakProgress(now: now) ?? 1
        if overlay.isVisible {
            overlay.update(remaining: remaining, progress: progress)
        } else {
            let settings = scheduler.settings
            let content = BreakOverlayContent(
                // A different tip for each minute a break can start in.
                tip: BreakTips.tip(for: Int(startedAt.timeIntervalSinceReferenceDate / 60)),
                breakDuration: endsAt.timeIntervalSince(startedAt),
                allowSkip: settings.allowSkip,
                allowSnooze: settings.allowPostpone,
                snoozeMinutes: settings.postponeMinutes
            )
            overlay.show(content: content, endsAt: endsAt, remaining: remaining, progress: progress)
        }
    }

    private func statusDisplay(now: Date) -> StatusItemController.Display {
        StatusItemController.Display(
            phase: StatusItemController.Display.Phase(scheduler.state),
            countdown: StatusText.menuBarTitle(scheduler, now: now),
            statusLine: StatusText.statusLine(scheduler, now: now) { $0.formatted(Self.pausedUntilStyle) },
            statsLine: StatusText.statsLine(stats.normalized(for: now))
        )
    }
}

private extension StatusItemController.Display.Phase {
    init(_ state: SchedulerState) {
        switch state {
        case .working: self = .working
        case .onBreak: self = .onBreak
        case .paused: self = .paused
        case .away: self = .away
        }
    }
}

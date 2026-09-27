import AppKit
import EyeRestCore
import EyeRestUI

/// Wires the reminder scheduler to the clock, the system's sleep and lock events, the settings store and the UI.
///
/// Two rules keep the app consistent with the scheduler:
/// - The sound plays only when a `.shown` event leaves the scheduler reminding, that is, when the card actually
///   appears, so each card chimes exactly once.
/// - The UI follows the scheduler's state after every scheduler call, so it can never get stuck out of step.
@MainActor
final class AppController {
    private static let pausedUntilStyle = Date.FormatStyle(date: .omitted, time: .shortened)
    /// Ticks land this long after each whole second of the current countdown (timers fire late, never early).
    private static let tickOffset: TimeInterval = 0.05

    private let settingsStore: SettingsStore
    private var scheduler: ReminderScheduler
    private let settingsModel: SettingsModel
    private let launchAtLogin = LaunchAtLoginModel()
    private let systemEvents = SystemEvents()
    /// Keeps App Nap from throttling the timer for the app's whole lifetime; idle and display sleep still happen.
    private let activity: NSObjectProtocol
    private var tickTimer: Timer?
    /// When the countdown the ticks are aligned to started.
    private var tickAnchor: Date?

    /// Loaded on first use and reused.
    private lazy var reminderSound: NSSound? = {
        let sound = NSSound(named: "Glass")
        sound?.volume = 0.5
        return sound
    }()

    private lazy var settingsWindow = SettingsWindowController(model: settingsModel, launchAtLogin: launchAtLogin)

    private lazy var reminderPanel = ReminderPanelController { [weak self] in
        self?.perform { $0.dismiss(now: $1) }
    }

    private lazy var statusItem = StatusItemController(display: statusDisplay(now: Date()), actions: .init(
        remindNow: { [weak self] in self?.perform { $0.remindNow(now: $1) } },
        pause: { [weak self] duration in self?.perform { $0.pause(for: duration, now: $1) } },
        resume: { [weak self] in self?.perform { $0.resume(now: $1) } },
        resetTimer: { [weak self] in self?.perform { $0.reset(now: $1) } },
        showSettings: { [weak self] in self?.showSettings() },
        showAbout: { [weak self] in self?.showAbout() }
    ))

    init(defaults: UserDefaults = .standard) {
        settingsStore = SettingsStore(defaults: defaults)
        scheduler = ReminderScheduler(settings: settingsStore.load(), now: Date())
        settingsModel = SettingsModel(settings: scheduler.settings)
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Eye-rest reminder timer"
        )
    }

    /// Starts the system observers and the 1 Hz timer, then runs a first tick, which puts the icon in the menu bar.
    func start() {
        settingsModel.onChange = { [weak self] settings in
            guard let self else { return }
            perform { $0.updateSettings(settings, now: $1) }
            settingsStore.save(scheduler.settings)
        }
        systemEvents.start { [weak self] change, now in
            self?.perform(at: now) { scheduler, now in
                switch change {
                case let .began(reason): scheduler.suspend(reason, now: now)
                case let .ended(reason): scheduler.unsuspend(reason, now: now)
                }
            }
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // `.common` keeps the timer firing while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        tick()
    }

    func showSettings() {
        settingsWindow.show()
    }

    func showAbout() {
        // An accessory app must activate itself, or the panel opens behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // MARK: - Driving the scheduler

    private func tick() {
        let now = Date()
        systemEvents.poll(now: now)
        perform(at: now) { $0.tick(now: $1) }
    }

    /// Runs one scheduler call, realigns the ticks, chimes if it showed the card and brings the UI in line with the
    /// resulting state.
    private func perform(at now: Date = Date(), _ call: (inout ReminderScheduler, Date) -> [ReminderEvent]) {
        let events = call(&scheduler, now)
        alignTicks()
        // Show the card before the chime: the first play starts CoreAudio synchronously, which would delay it.
        syncUI(now: now)
        // A batch holds at most one `.shown`; a pause, reset or suspension in the same call can close it again.
        if scheduler.settings.playSound, case let .reminding(_, endsAt) = scheduler.state,
           events.contains(.shown(endsAt: endsAt)) {
            playReminderSound()
        }
    }

    /// Moves the ticks to just after each whole second since the current countdown or card started. Unaligned, the
    /// timer's jitter decides whether a tick lands just before or just after a deadline, so the card could show its
    /// first second twice and stay up a second too long, and a reminder could appear a second late.
    private func alignTicks() {
        let anchor: Date
        switch scheduler.state {
        case let .counting(cycleStart, _): anchor = cycleStart
        case let .reminding(shownAt, _): anchor = shownAt
        case .paused, .suspended: return
        }
        guard anchor != tickAnchor else { return }
        tickAnchor = anchor
        tickTimer?.fireDate = anchor + 1 + Self.tickOffset
    }

    private func playReminderSound() {
        guard let sound = reminderSound else { return }
        sound.stop()
        sound.play()
    }

    // MARK: - UI

    /// Makes every piece of UI match the scheduler's current state.
    private func syncUI(now: Date) {
        if case let .reminding(_, endsAt) = scheduler.state {
            let remaining = scheduler.reminderTimeRemaining(now: now) ?? 0
            let progress = scheduler.reminderProgress(now: now) ?? 1
            if reminderPanel.isVisible {
                reminderPanel.update(remaining: remaining, progress: progress)
            } else {
                reminderPanel.show(endsAt: endsAt, remaining: remaining, progress: progress)
            }
        } else {
            reminderPanel.hide()
        }
        statusItem.update(statusDisplay(now: now))
    }

    private func statusDisplay(now: Date) -> StatusItemController.Display {
        StatusItemController.Display(
            phase: StatusItemController.Display.Phase(scheduler.state),
            countdown: StatusText.menuBarTitle(scheduler, now: now),
            statusLine: StatusText.statusLine(scheduler, now: now) { $0.formatted(Self.pausedUntilStyle) }
        )
    }
}

private extension StatusItemController.Display.Phase {
    init(_ state: ReminderState) {
        switch state {
        case .counting: self = .counting
        case .reminding: self = .reminding
        case .paused: self = .paused
        case .suspended: self = .suspended
        }
    }
}

import AppKit
import CoreGraphics
import EyeRestCore

/// Turns the Mac's own sleep, display-sleep, screen-lock and user-switch notifications into the scheduler's suspend
/// reasons.
///
/// Only system events are observed; nothing here looks at keyboard or mouse activity, the camera or the microphone.
/// `poll(now:)`, called on every tick, repairs a missed notification from system state.
@MainActor
final class SystemEvents {
    enum Change: Sendable {
        case began(SuspendReason)
        case ended(SuspendReason)
    }

    /// Ticks further apart than this mean the app was not running in between (the Mac was asleep).
    private static let maximumTickGap: TimeInterval = 5

    /// NSWorkspace posts these only on its own notification center, never on the default one.
    private static let workspaceNotifications: [(Notification.Name, Change)] = [
        (NSWorkspace.willSleepNotification, .began(.systemAsleep)),
        (NSWorkspace.didWakeNotification, .ended(.systemAsleep)),
        (NSWorkspace.screensDidSleepNotification, .began(.displayAsleep)),
        (NSWorkspace.screensDidWakeNotification, .ended(.displayAsleep)),
        (NSWorkspace.sessionDidResignActiveNotification, .began(.sessionInactive)),
        (NSWorkspace.sessionDidBecomeActiveNotification, .ended(.sessionInactive)),
    ]

    private static let distributedNotifications: [(Notification.Name, Change)] = [
        (Notification.Name("com.apple.screenIsLocked"), .began(.screenLocked)),
        (Notification.Name("com.apple.screenIsUnlocked"), .ended(.screenLocked)),
    ]

    private var onChange: ((Change, Date) -> Void)?
    /// When each active reason began.
    private var began: [SuspendReason: Date] = [:]
    /// Since when the system state has said, without interruption, that each reason is over.
    private var overSince: [SuspendReason: Date] = [:]
    private var lastPoll: Date?

    /// Starts observing. `onChange` runs on the main thread for every notification (the scheduler ignores
    /// repeats) and for every repair `poll(now:)` makes, with the time to pass to the scheduler.
    func start(onChange: @escaping (Change, Date) -> Void) {
        self.onChange = onChange
        observe(Self.workspaceNotifications, on: NSWorkspace.shared.notificationCenter)
        observe(Self.distributedNotifications, on: DistributedNotificationCenter.default())
    }

    /// Repairs missed notifications. Call it on every tick.
    ///
    /// - `.systemAsleep` ends once the app has been ticking for 10 s since it began (the wake was missed).
    /// - `.displayAsleep` ends once the main display has reported awake for 5 s since it began.
    /// - `.screenLocked` and `.sessionInactive` follow the login-session dictionary: they begin while it reports
    ///   them (a missed notification, or the state at launch) and end once it has reported them over for 5 s.
    func poll(now: Date) {
        let wasTicking = lastPoll.map { now.timeIntervalSince($0) <= Self.maximumTickGap } ?? false
        lastPoll = now
        heal(.systemAsleep, isOver: wasTicking, after: 10, now: now)
        heal(.displayAsleep, isOver: CGDisplayIsAsleep(CGMainDisplayID()) == 0, after: 5, now: now)
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return }
        // The lock key is absent while the screen is unlocked.
        follow(.screenLocked, isActive: session["CGSSessionScreenIsLocked"] as? Bool == true, now: now)
        follow(.sessionInactive, isActive: session[kCGSessionOnConsoleKey] as? Bool == false, now: now)
    }

    /// The observers stay for the life of the app, so their tokens are not kept.
    private func observe(_ notifications: [(Notification.Name, Change)], on center: NotificationCenter) {
        for (name, change) in notifications {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply(change, now: Date()) }
            }
        }
    }

    /// Keeps a reason the login-session dictionary reports in step with it.
    private func follow(_ reason: SuspendReason, isActive: Bool, now: Date) {
        if isActive, began[reason] == nil { apply(.began(reason), now: now) }
        heal(reason, isOver: !isActive, after: 5, now: now)
    }

    /// Ends `reason` once `isOver` has held for `delay` seconds, counted from when the reason began at the earliest.
    private func heal(_ reason: SuspendReason, isOver: Bool, after delay: TimeInterval, now: Date) {
        overSince[reason] = isOver ? overSince[reason] ?? now : nil
        guard let start = began[reason], let since = overSince[reason],
              now.timeIntervalSince(max(start, since)) >= delay
        else { return }
        apply(.ended(reason), now: now)
    }

    private func apply(_ change: Change, now: Date) {
        switch change {
        case let .began(reason): began[reason] = began[reason] ?? now
        case let .ended(reason): began[reason] = nil
        }
        onChange?(change, now)
    }
}

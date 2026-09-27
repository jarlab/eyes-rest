import AppKit
import CoreGraphics
import EyeRestCore

/// Reports the OS-level away reasons (screen lock, system sleep, display sleep, inactive login session) as changes.
///
/// Idle time is not handled here; the scheduler reads it directly. Each reason is reported at most once per episode:
/// `began` only when it is not already active and `ended` only when it is, no matter how many signals arrive.
/// `poll` also ends a reason whose ending notification was missed, once fresh input contradicts it.
@MainActor
public final class SystemActivityMonitor {
    public enum Change: Equatable, Sendable {
        case began(AwayReason, since: Date)
        case ended(AwayReason)
    }

    /// Called synchronously on the main thread for every change.
    public var onChange: ((Change) -> Void)?

    /// Login-session flags from `CGSessionCopyCurrentDictionary`.
    struct SessionState: Equatable {
        var isScreenLocked: Bool
        var isOnConsole: Bool

        /// The current session's flags, or nil if the dictionary cannot be read.
        static func current() -> SessionState? {
            guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
            return SessionState(
                // The key is absent while the screen is unlocked.
                isScreenLocked: session["CGSSessionScreenIsLocked"] as? Bool == true,
                isOnConsole: session[kCGSessionOnConsoleKey] as? Int != 0
            )
        }
    }

    private enum Transition: Sendable {
        case begin(AwayReason)
        case end(AwayReason)
    }

    /// NSWorkspace notifications are only posted on `NSWorkspace.shared.notificationCenter`, never on the default center.
    private static let workspaceTransitions: [(Notification.Name, Transition)] = [
        (NSWorkspace.willSleepNotification, .begin(.systemAsleep)),
        (NSWorkspace.didWakeNotification, .end(.systemAsleep)),
        (NSWorkspace.screensDidSleepNotification, .begin(.displayAsleep)),
        (NSWorkspace.screensDidWakeNotification, .end(.displayAsleep)),
        (NSWorkspace.sessionDidResignActiveNotification, .begin(.sessionInactive)),
        (NSWorkspace.sessionDidBecomeActiveNotification, .end(.sessionInactive)),
    ]

    private static let distributedTransitions: [(Notification.Name, Transition)] = [
        (Notification.Name("com.apple.screenIsLocked"), .begin(.screenLocked)),
        (Notification.Name("com.apple.screenIsUnlocked"), .end(.screenLocked)),
    ]

    /// The self-heal only ends a reason that has been active at least this long…
    private static let selfHealMinimumActiveDuration: TimeInterval = 5
    /// …and only while the user is actually giving input.
    private static let selfHealMaximumIdle: TimeInterval = 2

    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private let sessionState: () -> SessionState?
    /// Raw input idle time, the evidence for the self-heal.
    private let idleSeconds: () -> TimeInterval
    /// Idle time used to date the start of a lock, display sleep or session switch.
    private let awayIdleSeconds: () -> TimeInterval

    /// The reasons this monitor has reported as begun and not yet ended, with the time each began.
    private var activeReasons: [AwayReason: Date] = [:]
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// `awayIdleSeconds` dates the start of a lock, display sleep or session switch (the absence began at the last
    /// sign of the user). Pass the scheduler's effective idle time, so time spent watching a video just before the
    /// display sleeps is not counted as time away.
    public convenience init(awayIdleSeconds: @escaping () -> TimeInterval = IdleTime.seconds) {
        self.init(
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            distributedCenter: DistributedNotificationCenter.default(),
            sessionState: SessionState.current,
            idleSeconds: IdleTime.seconds,
            awayIdleSeconds: awayIdleSeconds
        )
    }

    init(
        workspaceCenter: NotificationCenter,
        distributedCenter: NotificationCenter,
        sessionState: @escaping () -> SessionState?,
        idleSeconds: @escaping () -> TimeInterval,
        awayIdleSeconds: @escaping () -> TimeInterval
    ) {
        self.workspaceCenter = workspaceCenter
        self.distributedCenter = distributedCenter
        self.sessionState = sessionState
        self.idleSeconds = idleSeconds
        self.awayIdleSeconds = awayIdleSeconds
    }

    /// Starts observing sleep/wake, display sleep, session switches and screen lock. Calling it again is a no-op.
    public func start() {
        guard observers.isEmpty else { return }
        for (name, transition) in Self.workspaceTransitions {
            observe(name, on: workspaceCenter, transition)
        }
        for (name, transition) in Self.distributedTransitions {
            observe(name, on: distributedCenter, transition)
        }
    }

    /// Removes every observer. Active reasons are kept, so a later `start()` continues from the same state.
    public func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    /// Repairs missed notifications. Call it every tick.
    ///
    /// Ends `.systemAsleep` / `.displayAsleep` once they have been active for at least 5 s and the user gave input
    /// in the last 2 s: fresh input proves the Mac and its display are awake (a missed wake notification).
    ///
    /// Reconciles screen lock and session state with the login-session dictionary: begins `.screenLocked` /
    /// `.sessionInactive` when the session reports them (state at launch, or a missed notification), and ends them
    /// when the session no longer reports them, under the same 5 s / 2 s guard (a missed unlock or
    /// session-activation notification).
    public func poll(now: Date) {
        let idle = idleSeconds()
        endIfContradictedByInput(.systemAsleep, now: now, idleSeconds: idle)
        endIfContradictedByInput(.displayAsleep, now: now, idleSeconds: idle)
        guard let session = sessionState() else { return }
        reconcile(.screenLocked, isReported: session.isScreenLocked, now: now, idleSeconds: idle)
        reconcile(.sessionInactive, isReported: !session.isOnConsole, now: now, idleSeconds: idle)
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, _ transition: Transition) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(transition) }
        }
        observers.append((center, token))
    }

    private func apply(_ transition: Transition) {
        switch transition {
        case .begin(let reason): begin(reason, now: Date())
        case .end(let reason): end(reason)
        }
    }

    private func reconcile(_ reason: AwayReason, isReported: Bool, now: Date, idleSeconds: TimeInterval) {
        if isReported {
            begin(reason, now: now)
        } else {
            endIfContradictedByInput(reason, now: now, idleSeconds: idleSeconds)
        }
    }

    /// Ends `reason` if it has been active for a while and yet the user is giving input.
    private func endIfContradictedByInput(_ reason: AwayReason, now: Date, idleSeconds: TimeInterval) {
        guard let began = activeReasons[reason],
              now.timeIntervalSince(began) >= Self.selfHealMinimumActiveDuration,
              idleSeconds < Self.selfHealMaximumIdle
        else { return }
        end(reason)
    }

    private func begin(_ reason: AwayReason, now: Date) {
        guard activeReasons[reason] == nil else { return }
        activeReasons[reason] = now
        // System sleep starts now. Lock, display sleep and session switches often follow inactivity (auto-lock,
        // display sleep timer), so they count from the last sign of the user.
        let since = reason == .systemAsleep ? now : now.addingTimeInterval(-awayIdleSeconds())
        onChange?(.began(reason, since: since))
    }

    private func end(_ reason: AwayReason) {
        guard activeReasons.removeValue(forKey: reason) != nil else { return }
        onChange?(.ended(reason))
    }
}

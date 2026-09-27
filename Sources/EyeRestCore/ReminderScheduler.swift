import Foundation

/// A system condition during which the timer is suspended. The scheduler is suspended while at least one is active.
public enum SuspendReason: String, CaseIterable, Sendable {
    case screenLocked, systemAsleep, displayAsleep, sessionInactive
}

public enum ReminderState: Equatable, Sendable {
    /// Counting down to the next reminder, due at `nextAt`.
    case counting(cycleStart: Date, nextAt: Date)
    /// The reminder card is visible until `endsAt`.
    case reminding(shownAt: Date, endsAt: Date)
    /// `until == nil` means paused until the user resumes.
    case paused(until: Date?)
    /// The Mac is asleep, locked or otherwise not in use; a fresh interval starts once every reason clears.
    case suspended
}

public enum ReminderEvent: Equatable, Sendable {
    /// The reminder card should appear; it closes itself at `endsAt`.
    case shown(endsAt: Date)
    /// The reminder card should close.
    case hidden
    case paused(until: Date?)
    case resumed
    /// A fresh interval started without the card closing (reset, clock gap, settings change, end of suspension).
    case restarted
}

/// The reminder timer as a pure, clock-injected state machine.
///
/// Every mutating method first reconciles with `now` (backward clock jumps, missed ticks, at most one due
/// deadline) and returns those events ahead of its own. The caller drives it with `tick` at about 1 Hz and
/// forwards user actions and suspend signals; it never reads the clock itself.
///
/// Invariants after every call: `.shown` and `.hidden` strictly alternate; the state is `reminding` exactly when
/// the last of them was `.shown`; `counting` implies `now < nextAt`; `suspended` implies at least one reason.
public struct ReminderScheduler: Sendable {
    /// A forward jump between calls longer than this while counting or reminding (e.g. sleep without a
    /// notification) starts a fresh interval instead of catching up.
    public static let gapThreshold: TimeInterval = 60

    public private(set) var state: ReminderState
    public private(set) var settings: EyeRestSettings
    /// Active suspend reasons, recorded in every state.
    public private(set) var suspendReasons: Set<SuspendReason> = []
    /// The `now` of the most recent mutating call.
    private(set) var lastSeen: Date

    public init(settings: EyeRestSettings, now: Date) {
        let settings = settings.clamped()
        self.settings = settings
        self.state = .counting(cycleStart: now, nextAt: now + settings.interval)
        self.lastSeen = now
    }

    // MARK: - Clock and user actions

    /// Advances the clock.
    public mutating func tick(now: Date) -> [ReminderEvent] {
        reconcile(now)
    }

    /// Shows the reminder card now. Leaves a pause; does nothing while the card is already visible.
    public mutating func remindNow(now: Date) -> [ReminderEvent] {
        var events = reconcileUserAction(now)
        switch state {
        case .counting:
            events += showReminder(now)
        case .paused:
            events.append(.resumed)
            events += showReminder(now)
        case .reminding, .suspended:
            break
        }
        return events
    }

    /// Closes a visible card early; the next interval starts now.
    public mutating func dismiss(now: Date) -> [ReminderEvent] {
        var events = reconcileUserAction(now)
        if case .reminding = state {
            events.append(.hidden)
            state = freshCount(now)
        }
        return events
    }

    /// Pauses for `duration` seconds, or until resumed when `duration` is nil, closing a visible card first.
    /// Durations that are not finite and positive are ignored.
    public mutating func pause(for duration: TimeInterval?, now: Date) -> [ReminderEvent] {
        if let duration, !(duration.isFinite && duration > 0) { return reconcile(now) }
        var events = reconcileUserAction(now)
        let until = duration.map { now + $0 }
        if case let .paused(current) = state, current == until { return events }
        if case .reminding = state { events.append(.hidden) }
        state = .paused(until: until)
        events.append(.paused(until: until))
        return events
    }

    /// Ends a pause; a fresh interval starts now.
    public mutating func resume(now: Date) -> [ReminderEvent] {
        var events = reconcileUserAction(now)
        if case .paused = state {
            events.append(.resumed)
            state = freshCount(now)
        }
        return events
    }

    /// Starts a fresh interval now from any state: a visible card closes (`.hidden`), a pause ends (`.resumed`),
    /// and `.restarted` follows. Does nothing if a fresh interval already started at `now`.
    public mutating func reset(now: Date) -> [ReminderEvent] {
        var events = reconcileUserAction(now)
        let fresh = freshCount(now)
        guard state != fresh else { return events }
        switch state {
        case .reminding: events.append(.hidden)
        case .paused: events.append(.resumed)
        case .counting, .suspended: break
        }
        state = fresh
        events.append(.restarted)
        return events
    }

    // MARK: - System signals

    /// Records a suspend reason. Counting or reminding becomes suspended (closing a visible card);
    /// a pause stays a pause and only records the reason.
    public mutating func suspend(_ reason: SuspendReason, now: Date) -> [ReminderEvent] {
        var events = reconcile(now)
        guard suspendReasons.insert(reason).inserted else { return events }
        switch state {
        case .counting:
            state = .suspended
        case .reminding:
            events.append(.hidden)
            state = .suspended
        case .paused, .suspended:
            break
        }
        return events
    }

    /// Clears a suspend reason. When the last one clears while suspended, a fresh interval starts now.
    public mutating func unsuspend(_ reason: SuspendReason, now: Date) -> [ReminderEvent] {
        var events = reconcile(now)
        guard suspendReasons.remove(reason) != nil else { return events }
        if case .suspended = state, suspendReasons.isEmpty {
            state = freshCount(now)
            events.append(.restarted)
        }
        return events
    }

    /// Applies new settings (clamped). Changing the interval while counting starts a fresh interval
    /// (`.restarted`; an interval that already started at `now` is just re-timed). A visible card keeps its end
    /// time, and paused or suspended timers pick the new values up when they start counting.
    public mutating func updateSettings(_ new: EyeRestSettings, now: Date) -> [ReminderEvent] {
        var events = reconcile(now)
        let new = new.clamped()
        guard new != settings else { return events }
        let intervalChanged = new.interval != settings.interval
        settings = new
        if intervalChanged, case let .counting(cycleStart, _) = state {
            state = freshCount(now)
            if cycleStart != now { events.append(.restarted) }
        }
        return events
    }

    // MARK: - Queries

    /// Seconds until the next reminder (≥ 0); nil unless counting.
    public func timeUntilNextReminder(now: Date) -> TimeInterval? {
        guard case let .counting(_, nextAt) = state else { return nil }
        return max(0, nextAt.timeIntervalSince(now))
    }

    /// Seconds until the visible card closes itself (≥ 0); nil unless reminding.
    public func reminderTimeRemaining(now: Date) -> TimeInterval? {
        guard case let .reminding(_, endsAt) = state else { return nil }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// Fraction of the visible card's countdown elapsed (0...1); nil unless reminding.
    public func reminderProgress(now: Date) -> Double? {
        guard case let .reminding(shownAt, endsAt) = state else { return nil }
        let total = endsAt.timeIntervalSince(shownAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(shownAt) / total))
    }

    // MARK: - Internals

    private func freshCount(_ now: Date) -> ReminderState {
        .counting(cycleStart: now, nextAt: now + settings.interval)
    }

    private mutating func showReminder(_ now: Date) -> [ReminderEvent] {
        let endsAt = now + settings.reminderDuration
        state = .reminding(shownAt: now, endsAt: endsAt)
        return [.shown(endsAt: endsAt)]
    }

    /// The prologue of every user action: reconcile with the clock, then register presence.
    private mutating func reconcileUserAction(_ now: Date) -> [ReminderEvent] {
        let events = reconcile(now)
        return events + registerPresence(now)
    }

    /// Any user action proves the user is at the Mac: drop every reason (some may be stale, e.g. a missed
    /// unlock notification) and leave suspension with a fresh interval.
    private mutating func registerPresence(_ now: Date) -> [ReminderEvent] {
        suspendReasons.removeAll()
        guard case .suspended = state else { return [] }
        state = freshCount(now)
        return [.restarted]
    }

    /// Moves every stored instant by `delta` so remaining times survive a wall-clock jump.
    private mutating func shift(by delta: TimeInterval) {
        switch state {
        case let .counting(cycleStart, nextAt):
            state = .counting(cycleStart: cycleStart + delta, nextAt: nextAt + delta)
        case let .reminding(shownAt, endsAt):
            state = .reminding(shownAt: shownAt + delta, endsAt: endsAt + delta)
        case let .paused(until):
            state = .paused(until: until.map { $0 + delta })
        case .suspended:
            break
        }
    }

    /// The prologue of every mutating call: absorb clock jumps, then handle at most one due deadline.
    private mutating func reconcile(_ now: Date) -> [ReminderEvent] {
        var events: [ReminderEvent] = []
        let delta = now.timeIntervalSince(lastSeen)
        lastSeen = now
        if delta < 0 {
            shift(by: delta)
        } else if delta > Self.gapThreshold {
            // Missed ticks are unobserved time away: start over rather than pop up the moment the user is back.
            switch state {
            case .counting:
                state = freshCount(now)
                events.append(.restarted)
            case .reminding:
                state = freshCount(now)
                events += [.hidden, .restarted]
            case .paused, .suspended:
                break
            }
        }
        switch state {
        case let .counting(_, nextAt) where now >= nextAt:
            events += showReminder(now)
        case let .reminding(_, endsAt) where now >= endsAt:
            events.append(.hidden)
            state = freshCount(now)
        case let .paused(until?) where now >= until:
            events.append(.resumed)
            state = suspendReasons.isEmpty ? freshCount(now) : .suspended
        default:
            break
        }
        return events
    }
}

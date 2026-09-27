import Foundation

/// Why the user is considered away from the Mac. The scheduler is away while at least one reason is active.
public enum AwayReason: String, Codable, CaseIterable, Sendable {
    case idle, screenLocked, systemAsleep, displayAsleep, sessionInactive
}

public enum SchedulerState: Equatable, Sendable {
    case working(cycleStart: Date, nextBreakAt: Date)
    case onBreak(startedAt: Date, endsAt: Date)
    /// `until == nil` means paused until the user resumes.
    case paused(until: Date?)
    /// The countdown is frozen with `frozenRemaining` seconds left while the user is away.
    case away(since: Date, frozenRemaining: TimeInterval)

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

public enum BreakOutcome: String, Codable, Sendable {
    case completed, skipped, postponed
}

public enum SchedulerEvent: Equatable, Sendable {
    case breakStarted(endsAt: Date)
    case breakEnded(BreakOutcome)
    case paused(until: Date?)
    case resumed
    case wentAway
    case returned(cycleReset: Bool)
    case cycleRestarted
}

/// The break timer as a pure, clock-injected state machine.
///
/// Every mutating method first reconciles with `now` (clock jumps, missed ticks, due deadlines) and returns
/// those events ahead of its own. The caller drives it with `tick` at 1 Hz and forwards user actions and
/// away signals; it never reads the clock itself.
public struct BreakScheduler: Sendable {
    /// A pause between calls longer than this (and at least one break long) counts as unobserved time away.
    public static let gapThreshold: TimeInterval = 60
    /// While a break is held for a call, it stays this far in the future.
    public static let holdLeadTime: TimeInterval = 30
    /// A countdown restored after a short absence never has less than this left.
    public static let minimumRestoredRemaining: TimeInterval = 15

    public private(set) var state: SchedulerState {
        didSet { if !state.isWorking { isHoldingBreak = false } }
    }
    public private(set) var settings: EyeRestSettings
    /// Reported away reasons, tracked in every state.
    public private(set) var awayReasons: Set<AwayReason> = []
    /// The `now` of the most recent mutating call.
    public private(set) var lastSeen: Date
    /// True while a due break is being pushed back because the user is on a call. Only ever true while working.
    public private(set) var isHoldingBreak = false

    public init(settings: EyeRestSettings, now: Date) {
        let settings = settings.clamped()
        self.settings = settings
        self.state = .working(cycleStart: now, nextBreakAt: now + settings.workInterval)
        self.lastSeen = now
    }

    // MARK: - Entry points

    /// Advances the clock. `holdBreak` is true while the user is on a call and a due break should wait.
    public mutating func tick(now: Date, holdBreak: Bool = false) -> [SchedulerEvent] {
        reconcile(now, holdBreak: holdBreak)
    }

    public mutating func takeBreakNow(now: Date) -> [SchedulerEvent] {
        var events = reconcile(now)
        events += registerPresence(now)
        switch state {
        case .working:
            events += startBreak(now)
        case .paused:
            events.append(.resumed)
            events += startBreak(now)
        case .onBreak, .away:
            break
        }
        return events
    }

    public mutating func skipBreak(now: Date) -> [SchedulerEvent] {
        var events = reconcile(now)
        events += registerPresence(now)
        if case .onBreak = state {
            events.append(.breakEnded(.skipped))
            state = freshCycle(now)
        }
        return events
    }

    /// Snoozes: ends a running break as postponed, or pushes the upcoming break back (stacking, no event).
    public mutating func postpone(now: Date) -> [SchedulerEvent] {
        var events = reconcile(now)
        events += registerPresence(now)
        switch state {
        case .onBreak:
            events.append(.breakEnded(.postponed))
            state = .working(cycleStart: now, nextBreakAt: now + settings.postponeDuration)
        case let .working(cycleStart, nextBreakAt):
            state = .working(cycleStart: cycleStart, nextBreakAt: nextBreakAt + settings.postponeDuration)
        case .paused, .away:
            break
        }
        return events
    }

    /// Pauses for `duration` seconds, or until resumed when `duration` is nil. Invalid durations are ignored.
    public mutating func pause(for duration: TimeInterval?, now: Date) -> [SchedulerEvent] {
        if let duration, !(duration.isFinite && duration > 0) { return reconcile(now) }
        var events = reconcile(now)
        events += registerPresence(now)
        let until = duration.map { now + $0 }
        if case let .paused(current) = state, current == until { return events }
        if case .onBreak = state { events.append(.breakEnded(.skipped)) }
        state = .paused(until: until)
        events.append(.paused(until: until))
        return events
    }

    public mutating func resume(now: Date) -> [SchedulerEvent] {
        var events = reconcile(now)
        events += registerPresence(now)
        if case .paused = state {
            events.append(.resumed)
            state = freshCycle(now)
        }
        return events
    }

    public mutating func resetCycle(now: Date) -> [SchedulerEvent] {
        var events = reconcile(now)
        events += registerPresence(now)
        switch state {
        case .working: events.append(.cycleRestarted)
        case .onBreak: events.append(.breakEnded(.skipped))
        case .paused: events.append(.resumed)
        case .away: break  // unreachable: registerPresence always leaves away
        }
        state = freshCycle(now)
        return events
    }

    /// Records an away reason. `since` is when the absence really began (e.g. the last input before a lock).
    public mutating func beginAway(_ reason: AwayReason, since: Date, now: Date) -> [SchedulerEvent] {
        reconcile(now) + insertAwayReason(reason, since: since, now: now)
    }

    public mutating func endAway(_ reason: AwayReason, now: Date) -> [SchedulerEvent] {
        reconcile(now) + removeAwayReason(reason, now: now)
    }

    /// Feeds the current idle time (seconds since the last input) into the `.idle` away reason.
    public mutating func observeIdle(seconds: TimeInterval, now: Date) -> [SchedulerEvent] {
        var events = reconcile(now)
        let seconds = seconds.isFinite ? max(0, seconds) : 0
        let isIdle = awayReasons.contains(.idle)
        if settings.pauseWhenIdle, seconds >= settings.idleThreshold, !isIdle {
            events += insertAwayReason(.idle, since: now - seconds, now: now)
        } else if isIdle, seconds < settings.idleThreshold {
            events += removeAwayReason(.idle, now: now)
        }
        return events
    }

    /// Applies new settings (clamped). Only a work-interval change affects the running countdown.
    public mutating func updateSettings(_ new: EyeRestSettings, now: Date) -> [SchedulerEvent] {
        var events = reconcile(now)
        let new = new.clamped()
        guard new != settings else { return events }
        let old = settings
        settings = new
        if !new.pauseWhenIdle, awayReasons.contains(.idle) {
            events += removeAwayReason(.idle, now: now)
        }
        if new.workInterval != old.workInterval {
            switch state {
            case .working:
                state = freshCycle(now)
                events.append(.cycleRestarted)
            case let .away(since, _):
                state = .away(since: since, frozenRemaining: new.workInterval)
            case .onBreak, .paused:
                break
            }
        }
        return events
    }

    // MARK: - Queries

    /// Seconds until the next break (≥ 0); nil unless working.
    public func timeUntilNextBreak(now: Date) -> TimeInterval? {
        guard case let .working(_, nextBreakAt) = state else { return nil }
        return max(0, nextBreakAt.timeIntervalSince(now))
    }

    /// Seconds left in the current break (≥ 0); nil unless on a break.
    public func breakTimeRemaining(now: Date) -> TimeInterval? {
        guard case let .onBreak(_, endsAt) = state else { return nil }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// Fraction of the current break elapsed (0...1); nil unless on a break.
    public func breakProgress(now: Date) -> Double? {
        guard case let .onBreak(startedAt, endsAt) = state else { return nil }
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(startedAt) / total))
    }

    // MARK: - Internals

    private func freshCycle(_ now: Date) -> SchedulerState {
        .working(cycleStart: now, nextBreakAt: now + settings.workInterval)
    }

    private mutating func startBreak(_ now: Date) -> [SchedulerEvent] {
        let endsAt = now + settings.breakDuration
        state = .onBreak(startedAt: now, endsAt: endsAt)
        return [.breakStarted(endsAt: endsAt)]
    }

    /// Starts a fresh cycle, or goes away if reasons are pending (after a break completes or a pause expires).
    private mutating func enterWorkingOrAway(_ now: Date) -> [SchedulerEvent] {
        guard !awayReasons.isEmpty else {
            state = freshCycle(now)
            return []
        }
        state = .away(since: now, frozenRemaining: settings.workInterval)
        return [.wentAway]
    }

    /// Any user action proves presence: drop all reasons (some may be stale) and leave away via the return rule.
    private mutating func registerPresence(_ now: Date) -> [SchedulerEvent] {
        guard !awayReasons.isEmpty else { return [] }
        awayReasons.removeAll()
        return returnIfAway(now)
    }

    /// Leaves away once no reasons remain. An absence of at least one break length counts as a break.
    private mutating func returnIfAway(_ now: Date) -> [SchedulerEvent] {
        guard case let .away(since, frozenRemaining) = state, awayReasons.isEmpty else { return [] }
        if now.timeIntervalSince(since) >= settings.breakDuration {
            state = freshCycle(now)
            return [.returned(cycleReset: true)]
        }
        let remaining = max(frozenRemaining, Self.minimumRestoredRemaining)
        state = .working(cycleStart: now, nextBreakAt: now + remaining)
        return [.returned(cycleReset: false)]
    }

    private mutating func insertAwayReason(_ reason: AwayReason, since: Date, now: Date) -> [SchedulerEvent] {
        if reason == .idle && !settings.pauseWhenIdle { return [] }
        guard awayReasons.insert(reason).inserted else { return [] }
        switch state {
        case let .working(cycleStart, nextBreakAt):
            let start = min(max(since, cycleStart), now)
            state = .away(since: start, frozenRemaining: nextBreakAt.timeIntervalSince(start))
            return [.wentAway]
        case let .onBreak(startedAt, _):
            if reason == .idle { return [] }  // a resting user is idle, so idle never interrupts a break
            let start = min(max(since, startedAt), now)
            state = .away(since: start, frozenRemaining: settings.workInterval)
            return [.breakEnded(.completed), .wentAway]
        case .paused, .away:
            return []  // only recorded; an existing absence keeps its start
        }
    }

    private mutating func removeAwayReason(_ reason: AwayReason, now: Date) -> [SchedulerEvent] {
        guard awayReasons.remove(reason) != nil else { return [] }
        return returnIfAway(now)
    }

    /// Moves every stored instant by `delta` so remaining times survive a wall-clock jump.
    private mutating func shift(by delta: TimeInterval) {
        switch state {
        case let .working(cycleStart, nextBreakAt):
            state = .working(cycleStart: cycleStart + delta, nextBreakAt: nextBreakAt + delta)
        case let .onBreak(startedAt, endsAt):
            state = .onBreak(startedAt: startedAt + delta, endsAt: endsAt + delta)
        case let .paused(until):
            state = .paused(until: until.map { $0 + delta })
        case let .away(since, frozenRemaining):
            state = .away(since: since + delta, frozenRemaining: frozenRemaining)
        }
    }

    /// The prologue of every entry point. `holdBreak` is non-nil only for `tick`.
    private mutating func reconcile(_ now: Date, holdBreak: Bool? = nil) -> [SchedulerEvent] {
        var events: [SchedulerEvent] = []
        let delta = now.timeIntervalSince(lastSeen)
        if delta < 0 {
            shift(by: delta)
        } else if delta > Self.gapThreshold, delta >= settings.breakDuration, state.isWorking {
            // Missed ticks (e.g. sleep without notifications) are an unobserved absence: start over.
            state = freshCycle(now)
            events.append(.cycleRestarted)
        }
        lastSeen = now
        if let holdBreak { applyHold(holdBreak, now: now) }
        switch state {
        case let .working(_, nextBreakAt) where now >= nextBreakAt:
            events += startBreak(now)
        case let .onBreak(_, endsAt) where now >= endsAt:
            events.append(.breakEnded(.completed))
            events += enterWorkingOrAway(now)
        case let .paused(until?) where now >= until:
            events.append(.resumed)
            events += enterWorkingOrAway(now)
        default:
            break
        }
        return events
    }

    /// Keeps a break that is less than `holdLeadTime` away exactly that far away while the user is on a call.
    private mutating func applyHold(_ holdBreak: Bool, now: Date) {
        guard holdBreak, case let .working(cycleStart, nextBreakAt) = state,
              nextBreakAt.timeIntervalSince(now) < Self.holdLeadTime
        else {
            isHoldingBreak = false
            return
        }
        state = .working(cycleStart: cycleStart, nextBreakAt: now + Self.holdLeadTime)
        isHoldingBreak = true
    }
}

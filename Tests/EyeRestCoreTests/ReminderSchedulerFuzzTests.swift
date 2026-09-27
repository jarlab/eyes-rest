import Foundation
import Testing
@testable import EyeRestCore

/// SplitMix64: a tiny, fast, seedable generator so fuzz runs are reproducible.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("ReminderScheduler fuzz")
struct ReminderSchedulerFuzzTests {
    private enum Operation {
        case tick, remindNow, dismiss, pause(TimeInterval?), resume, reset
        case suspend(SuspendReason), unsuspend(SuspendReason), updateSettings(EyeRestSettings)

        func apply(to s: inout ReminderScheduler, now: Date) -> [ReminderEvent] {
            switch self {
            case .tick: s.tick(now: now)
            case .remindNow: s.remindNow(now: now)
            case .dismiss: s.dismiss(now: now)
            case let .pause(duration): s.pause(for: duration, now: now)
            case .resume: s.resume(now: now)
            case .reset: s.reset(now: now)
            case let .suspend(reason): s.suspend(reason, now: now)
            case let .unsuspend(reason): s.unsuspend(reason, now: now)
            case let .updateSettings(settings): s.updateSettings(settings, now: now)
            }
        }
    }

    /// How often the interesting paths ran, so the invariant checks cannot pass vacuously.
    private struct Coverage {
        var shownByDeadline = 0
        var hiddenByDeadline = 0
        var gapRestarts = 0
        var gapRestartsHidingACard = 0
        var backwardJumps = 0
        var pauseExpiries = 0
        var pauseExpiriesIntoSuspension = 0
        var unsuspendRestarts = 0
        var presenceRestarts = 0
    }

    /// Drives random operations, clock gaps and backward jumps, asserting the scheduler's invariants after every
    /// call, and that repeating any call at the same instant changes nothing.
    ///
    /// Each run alternates between two regimes. The chaotic one fires frequent user actions, suspend signals,
    /// gaps and backward jumps. The calm one mostly ticks at 1 Hz and is left alone, so countdowns and cards
    /// actually reach their deadlines (the chaotic regime interrupts them long before).
    @Test(arguments: 1...10)
    func invariantsHoldUnderRandomOperations(seed: Int) {
        var rng = SplitMix64(state: UInt64(seed))
        var config = defaultSettings
        config.intervalMinutes = 2
        config.reminderSeconds = 30
        var s = ReminderScheduler(settings: config, now: t0)
        var t: TimeInterval = 0
        var visibleByEvents = false
        var calm = false
        var coverage = Coverage()
        let tolerance = 1e-6  // Date arithmetic on non-integral offsets is not exact

        for _ in 0..<10_000 {
            if Int.random(in: 0..<400, using: &rng) == 0 { calm.toggle() }
            let r = Int.random(in: 0..<1000, using: &rng)
            let dt: TimeInterval
            if calm {
                dt = r < 2 ? .random(in: 61...5000, using: &rng) : (r < 4 ? -.random(in: 1...4000, using: &rng) : 1)
            } else if r < 20 {
                dt = .random(in: 61...8000, using: &rng)
            } else if r < 40 {
                dt = -.random(in: 0.001...4000, using: &rng)
            } else if r < 100 {
                dt = .random(in: 0...60, using: &rng)
            } else if r < 130 {
                dt = 0
            } else {
                dt = 1
            }
            t += dt
            let now = at(t)
            if dt < 0 { coverage.backwardJumps += 1 }

            let reason = SuspendReason.allCases.randomElement(using: &rng)!
            let operation: Operation
            if calm && Int.random(in: 0..<1000, using: &rng) < 995 {
                operation = .tick
            } else {
                switch Int.random(in: 0..<13, using: &rng) {
                case 0...3: operation = .tick
                case 4: operation = .remindNow
                case 5: operation = .dismiss
                case 6: operation = .pause([nil, 3, 10, 60, 1800, 0, -1, Double.nan].randomElement(using: &rng)!)
                case 7: operation = .resume
                case 8: operation = .reset
                case 9, 10: operation = .suspend(reason)
                case 11: operation = .unsuspend(reason)
                default:
                    var c = config
                    c.intervalMinutes = .random(in: 0...5, using: &rng)  // 0 is clamped to 1
                    c.reminderSeconds = [3, 5, 20, 30, 60, 120, 500].randomElement(using: &rng)!
                    c.playSound = Bool.random(using: &rng)
                    c.showCountdownInMenuBar = Bool.random(using: &rng)
                    operation = .updateSettings(c)
                }
            }

            let stateBefore = s.state
            let reasonsBefore = s.suspendReasons
            let events = operation.apply(to: &s, now: now)

            // .shown and .hidden strictly alternate, and each appears at most once per call.
            for event in events {
                switch event {
                case .shown:
                    #expect(!visibleByEvents)
                    visibleByEvents = true
                case .hidden:
                    #expect(visibleByEvents)
                    visibleByEvents = false
                case .paused, .resumed, .restarted:
                    break
                }
            }
            #expect(events.filter { $0 == .hidden }.count <= 1)
            #expect(events.filter { $0 == .restarted }.count <= 1)
            #expect(events.filter { if case .shown = $0 { return true }; return false }.count <= 1)

            // reminding ⇔ the last visibility event was .shown.
            let isReminding: Bool = { if case .reminding = s.state { return true }; return false }()
            #expect(isReminding == visibleByEvents)
            #expect(s.lastSeen == now)

            switch s.state {
            case let .counting(cycleStart, nextAt):
                #expect(now < nextAt)
                #expect(abs(nextAt.timeIntervalSince(cycleStart) - s.settings.interval) < tolerance)
                #expect(s.suspendReasons.isEmpty)
                let remaining = s.timeUntilNextReminder(now: now) ?? -1
                #expect(remaining > 0 && remaining <= s.settings.interval + tolerance)
            case let .reminding(shownAt, endsAt):
                #expect(now < endsAt)
                #expect(shownAt <= now)
                let length = endsAt.timeIntervalSince(shownAt)
                #expect(length > Double(EyeRestSettings.reminderRange.lowerBound) - tolerance)
                #expect(length < Double(EyeRestSettings.reminderRange.upperBound) + tolerance)
                #expect(s.suspendReasons.isEmpty)
                let progress = s.reminderProgress(now: now) ?? -1
                #expect((0...1).contains(progress))
                #expect(s.reminderTimeRemaining(now: now)! > 0)
            case let .paused(until):
                if let until { #expect(now < until) }
            case .suspended:
                #expect(!s.suspendReasons.isEmpty)
            }
            #expect(EyeRestSettings.intervalRange.contains(s.settings.intervalMinutes))
            #expect(EyeRestSettings.reminderRange.contains(s.settings.reminderSeconds))

            // Repeating any call at the same instant is a no-op.
            if Int.random(in: 0..<4, using: &rng) == 0 {
                let stateAfter = s.state
                let reasonsAfter = s.suspendReasons
                #expect(operation.apply(to: &s, now: now).isEmpty)
                #expect(s.state == stateAfter)
                #expect(s.suspendReasons == reasonsAfter)
            }

            // Coverage bookkeeping.
            switch operation {
            case .tick:
                if case .shown = events.last { coverage.shownByDeadline += 1 }
                if events == [.hidden] { coverage.hiddenByDeadline += 1 }
                if events.last == .restarted {
                    coverage.gapRestarts += 1
                    if events.first == .hidden { coverage.gapRestartsHidingACard += 1 }
                }
                if events == [.resumed] {
                    coverage.pauseExpiries += 1
                    if s.state == .suspended { coverage.pauseExpiriesIntoSuspension += 1 }
                }
            case .unsuspend:
                if events.last == .restarted, stateBefore == .suspended { coverage.unsuspendRestarts += 1 }
            case .remindNow, .dismiss, .pause, .resume, .reset:
                if stateBefore == .suspended, !reasonsBefore.isEmpty, events.contains(.restarted) {
                    coverage.presenceRestarts += 1
                }
            case .suspend, .updateSettings:
                break
            }
        }

        // Every interesting path ran, so the checks above did not pass vacuously.
        #expect(coverage.shownByDeadline > 0)
        #expect(coverage.hiddenByDeadline > 0)
        #expect(coverage.gapRestarts > 0)
        #expect(coverage.gapRestartsHidingACard > 0)
        #expect(coverage.backwardJumps > 0)
        #expect(coverage.pauseExpiries > 0)
        #expect(coverage.pauseExpiriesIntoSuspension > 0)
        #expect(coverage.unsuspendRestarts > 0)
        #expect(coverage.presenceRestarts > 0)
    }
}

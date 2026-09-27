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

@Suite("BreakScheduler fuzz")
struct SchedulerFuzzTests {
    /// Drives random operations, clock gaps, backward jumps and call holds, asserting invariants I1–I7
    /// (spec §4) after every call.
    ///
    /// Each run alternates between two regimes. The chaotic one fires frequent user actions, gaps and
    /// backward jumps at a mostly idle user. The calm one is an active user who is left alone, so the
    /// countdown actually reaches its deadline and call holds engage (the chaotic regime alone almost never
    /// gets within 30 s of a break). In the calm regime the user also sometimes locks the screen for a short
    /// while just before a break, which is the only way the RETURN floor ever decides the restored countdown.
    @Test(arguments: 1...20)
    func invariantsHoldUnderRandomOperations(seed: Int) {
        var rng = SplitMix64(state: UInt64(seed))
        var config = defaultSettings
        config.idleThresholdMinutes = 1
        config.breakDurationSeconds = 90
        config.workIntervalMinutes = 3
        var s = BreakScheduler(settings: config, now: t0)
        var t: TimeInterval = 0
        var onBreakByEvents = false
        var idleSeconds: TimeInterval = 0
        var inCall = false
        var calm = false
        /// When the directed short lock ends; nil while none is in progress.
        var unlockAt: TimeInterval?
        /// Restores that the RETURN floor decided (the frozen countdown was below the floor).
        var floorHits = 0
        let tolerance = 1e-6  // Date arithmetic on non-integral offsets is not exact

        for _ in 0..<20_000 {
            if Int.random(in: 0..<1000, using: &rng) == 0 { calm.toggle() }
            if Int.random(in: 0..<100, using: &rng) == 0 { inCall.toggle() }
            let r = Int.random(in: 0..<1000, using: &rng)
            let (gapLimit, jumpLimit) = calm ? (1, 2) : (20, 30)
            let dt: TimeInterval = r < gapLimit
                ? .random(in: 61...8000, using: &rng)
                : (r < jumpLimit ? -.random(in: 1...4000, using: &rng) : 1)
            t += dt
            let inputSeen = Int.random(in: 0..<(calm ? 5 : 60), using: &rng) == 0
            idleSeconds = inputSeen ? 0 : idleSeconds + max(dt, 0)
            let now = at(t)
            let reason = AwayReason.allCases.randomElement(using: &rng)!

            let stateBefore = s.state
            var events: [SchedulerEvent]
            var ticked = false
            let leaveAlone = calm && Int.random(in: 0..<1000, using: &rng) < 995
            let nearDeadline = (s.timeUntilNextBreak(now: now) ?? .infinity) < BreakScheduler.minimumRestoredRemaining
            // The directed short lock near a deadline (see above), otherwise a random operation.
            if let end = unlockAt, t >= end {
                events = s.endAway(.screenLocked, now: now)
                unlockAt = nil
            } else if calm, unlockAt == nil, nearDeadline, Int.random(in: 0..<4, using: &rng) == 0 {
                events = s.beginAway(.screenLocked, since: now, now: now)
                unlockAt = t + .random(in: 1...60, using: &rng)
            } else {
                switch leaveAlone ? 0 : Int.random(in: 0..<14, using: &rng) {
                case 0...5:
                    events = s.observeIdle(seconds: idleSeconds, now: now)
                    events += s.tick(now: now, holdBreak: inCall)
                    ticked = true
                case 6: events = s.takeBreakNow(now: now)
                case 7: events = s.skipBreak(now: now)
                case 8: events = s.postpone(now: now)
                case 9: events = s.pause(for: [nil, 60, 1800].randomElement(using: &rng)!, now: now)
                case 10: events = s.resume(now: now)
                case 11: events = s.beginAway(reason, since: now - .random(in: 0...500, using: &rng), now: now)
                case 12: events = s.endAway(reason, now: now)
                default:
                    var c = config
                    c.pauseWhenIdle = Bool.random(using: &rng)
                    c.workIntervalMinutes = .random(in: 1...5, using: &rng)
                    events = s.updateSettings(c, now: now)
                }
            }

            // I1: breakStarted / breakEnded strictly alternate, and onBreak iff the last one was breakStarted.
            for event in events {
                switch event {
                case .breakStarted:
                    #expect(!onBreakByEvents)
                    onBreakByEvents = true
                case .breakEnded:
                    #expect(onBreakByEvents)
                    onBreakByEvents = false
                default:
                    break
                }
            }
            let isOnBreak: Bool = { if case .onBreak = s.state { return true }; return false }()
            #expect(isOnBreak == onBreakByEvents)

            switch s.state {
            case .away:
                #expect(!s.awayReasons.isEmpty)  // I2
            case let .working(cycleStart, nextBreakAt):
                #expect(s.awayReasons.isEmpty)  // I3
                #expect(cycleStart <= nextBreakAt)
                #expect(now < nextBreakAt)
            case let .onBreak(startedAt, endsAt):
                #expect(s.awayReasons.isSubset(of: [.idle]))  // I4
                #expect(startedAt < endsAt)
                #expect(now < endsAt)
            case .paused:
                break
            }
            if s.awayReasons.contains(.idle) { #expect(s.settings.pauseWhenIdle) }  // I5
            if let progress = s.breakProgress(now: now) { #expect((0...1).contains(progress)) }  // I6
            if s.isHoldingBreak { #expect(s.state.isWorking) }  // I7

            // Hold mechanics: after a tick, a held break is exactly holdLeadTime away, and no call means no hold.
            if ticked {
                if s.isHoldingBreak {
                    #expect(inCall)
                    let remaining = s.timeUntilNextBreak(now: now) ?? -1
                    #expect(abs(remaining - BreakScheduler.holdLeadTime) < tolerance)
                }
                if !inCall { #expect(!s.isHoldingBreak) }
            }
            // RETURN floor: a restored countdown never has less than minimumRestoredRemaining left.
            if events.last == .returned(cycleReset: false) {
                let remaining = s.timeUntilNextBreak(now: now) ?? -1
                #expect(remaining > BreakScheduler.minimumRestoredRemaining - tolerance)
                if case let .away(_, frozenRemaining) = stateBefore,
                   frozenRemaining < BreakScheduler.minimumRestoredRemaining {
                    floorHits += 1
                }
            }
        }
        // The floor check above must not pass vacuously.
        #expect(floorHits > 0)
    }
}

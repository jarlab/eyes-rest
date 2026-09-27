import Foundation
import Testing
@testable import EyeRestCore

/// The app's 1 Hz tick with a scripted user: effective idle feeds `observeIdle`, then the scheduler ticks.
/// Test seconds double as the monotonic clock.
private struct Simulation {
    var scheduler = BreakScheduler(settings: defaultSettings, now: t0)
    var idle = EffectiveIdle()
    var lastInput: TimeInterval = 0

    /// Runs the ticks `from...through`, returning each tick's time with its events (ticks without events omitted).
    mutating func run(
        from: TimeInterval,
        through: TimeInterval,
        input: (TimeInterval) -> Bool = { _ in false },
        displaySleepPrevented: (TimeInterval) -> Bool = { _ in false },
        inCall: (TimeInterval) -> Bool = { _ in false }
    ) -> [(TimeInterval, [SchedulerEvent])] {
        var log: [(TimeInterval, [SchedulerEvent])] = []
        var t = from
        while t <= through {
            if input(t) { lastInput = t }
            let seconds = idle.update(rawIdle: t - lastInput, displaySleepPrevented: displaySleepPrevented(t), now: t)
            let events = scheduler.observeIdle(seconds: seconds, now: at(t)) + scheduler.tick(now: at(t), holdBreak: inCall(t))
            if !events.isEmpty { log.append((t, events)) }
            t += 1
        }
        return log
    }
}

@Suite("EffectiveIdle")
struct EffectiveIdleTests {
    @Test func withoutAnAssertionIdleIsRaw() {
        var idle = EffectiveIdle()
        #expect(idle.update(rawIdle: 0.5, displaySleepPrevented: false, now: 10) == 0.5)
        #expect(idle.update(rawIdle: 400, displaySleepPrevented: false, now: 11) == 400)
        #expect(idle.update(rawIdle: -3, displaySleepPrevented: false, now: 12) == 0)
        #expect(idle.update(rawIdle: .nan, displaySleepPrevented: false, now: 13) == 0)
    }

    @Test func assertionIsNotCheckedWhileTheUserIsActive() {
        var idle = EffectiveIdle()
        var checks = 0
        func prevented() -> Bool {
            checks += 1
            return true
        }
        #expect(idle.update(rawIdle: 1.5, displaySleepPrevented: prevented(), now: 10) == 1.5)
        #expect(checks == 0)
        #expect(idle.update(rawIdle: 2, displaySleepPrevented: prevented(), now: 11) == 0)
        #expect(checks == 1)
    }

    @Test func idleCountsFromWhenTheAppLetGo() {
        var idle = EffectiveIdle()
        #expect(idle.update(rawIdle: 700, displaySleepPrevented: true, now: 1000) == 0)
        #expect(idle.update(rawIdle: 720, displaySleepPrevented: true, now: 1020) == 0)
        #expect(idle.update(rawIdle: 721, displaySleepPrevented: false, now: 1021) == 1)
        #expect(idle.update(rawIdle: 1020, displaySleepPrevented: false, now: 1320) == 300)
        // Input after the release restarts idle from the input, as usual.
        #expect(idle.update(rawIdle: 5, displaySleepPrevented: false, now: 1400) == 5)
    }

    /// A 12-minute video from minute 6 to 18, then a mouse move at 18:10: the user never left, so the break at
    /// minute 20 stays where it was.
    @Test func endOfAVideoIsNotTimeAway() {
        var sim = Simulation()
        let log = sim.run(
            from: 1, through: 1200,
            input: { $0 <= 360 || $0 == 1090 },
            displaySleepPrevented: { (360..<1080).contains($0) }
        )
        #expect(log.count == 1)
        #expect(log.first?.0 == 1200)
        #expect(log.first?.1 == [.breakStarted(endsAt: at(1220))])
    }

    @Test func awayBeginsOneThresholdAfterTheVideoEndsDatedToItsEnd() {
        var sim = Simulation()
        let log = sim.run(
            from: 1, through: 900,
            input: { $0 <= 60 },
            displaySleepPrevented: { (60...600).contains($0) }  // last seen at 600
        )
        #expect(log.count == 1)
        #expect(log.first?.0 == 900)
        #expect(log.first?.1 == [.wentAway])
        #expect(sim.scheduler.state == .away(since: at(600), frozenRemaining: 600))
    }

    /// A one-tick gap in the assertion (e.g. between two videos) long after the last input is not an absence.
    @Test func briefGapInTheAssertionIsIgnored() {
        var sim = Simulation()
        let log = sim.run(
            from: 1, through: 1000,
            input: { $0 <= 60 },
            displaySleepPrevented: { $0 > 60 && $0 != 500 }
        )
        #expect(log.isEmpty)
    }

    /// A listen-only call that the host ends: the held break arrives 30 s later instead of being dropped.
    @Test func heldBreakArrivesAfterAQuietCallEnds() {
        var sim = Simulation()
        let inCall: (TimeInterval) -> Bool = { (60..<2400).contains($0) }
        let log = sim.run(
            from: 1, through: 2440,
            input: { $0 <= 60 },
            displaySleepPrevented: inCall,
            inCall: inCall
        )
        #expect(log.count == 1)
        #expect(log.first?.0 == 2429)
        #expect(log.first?.1 == [.breakStarted(endsAt: at(2449))])
    }
}

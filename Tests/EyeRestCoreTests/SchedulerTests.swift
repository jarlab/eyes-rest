import Foundation
import Testing
@testable import EyeRestCore

@Suite("BreakScheduler")
struct SchedulerTests {
    // MARK: - Cycles and snoozing

    @Test func basicCycle() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        #expect(s.state == .working(cycleStart: t0, nextBreakAt: at(1200)))
        #expect(advance(&s, to: 1200) == [])
        #expect(s.tick(now: at(1200)) == [.breakStarted(endsAt: at(1220))])
        #expect(s.tick(now: at(1200)) == [])  // idempotent
        #expect(advance(&s, to: 1220) == [])
        #expect(s.tick(now: at(1220)) == [.breakEnded(.completed)])
        #expect(s.state == .working(cycleStart: at(1220), nextBreakAt: at(2420)))
    }

    @Test func hundredCyclesAtOneHz() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        let events = run(&s, from: 1, through: 1220 * 100)
        #expect(events.filter { if case .breakStarted = $0 { return true }; return false }.count == 100)
        #expect(events.filter { $0 == .breakEnded(.completed) }.count == 100)
    }

    @Test func stackedPostponeInWorkingIsNotUndoneByClockJumpHeuristic() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        #expect(s.postpone(now: at(1)) == [])
        #expect(s.postpone(now: at(2)) == [])
        _ = s.tick(now: at(3))
        // 1797 s is more than workInterval + postponeDuration, and must survive the next tick.
        #expect(s.timeUntilNextBreak(now: at(3)) == 1797.0)
    }

    @Test func postponeDuringBreak() {
        var s = schedulerOnFirstBreak()
        #expect(s.postpone(now: at(1205)) == [.breakEnded(.postponed)])
        #expect(s.state == .working(cycleStart: at(1205), nextBreakAt: at(1505)))
    }

    // MARK: - Pausing

    @Test func pauseDuringBreakEndsItAsSkipped() {
        var s = schedulerOnFirstBreak()
        #expect(s.pause(for: 1800, now: at(1210)) == [.breakEnded(.skipped), .paused(until: at(3010))])
        #expect(s.tick(now: at(3009)) == [])
        #expect(s.tick(now: at(3010)) == [.resumed])
        #expect(s.state == .working(cycleStart: at(3010), nextBreakAt: at(4210)))
    }

    @Test func pauseIdempotentAndInvalid() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        #expect(s.pause(for: nil, now: at(1)) == [.paused(until: nil)])
        #expect(s.pause(for: nil, now: at(2)) == [])
        #expect(s.pause(for: 0, now: at(3)) == [])
        #expect(s.pause(for: -60, now: at(4)) == [])
        #expect(s.pause(for: .infinity, now: at(5)) == [])
        #expect(s.tick(now: at(100_000)) == [])
        #expect(s.resume(now: at(100_001)) == [.resumed])
        #expect(s.resume(now: at(100_002)) == [])
    }

    @Test func takeBreakNowFromPausedAndAway() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(1))
        #expect(s.takeBreakNow(now: at(2)) == [.resumed, .breakStarted(endsAt: at(22))])
        #expect(s.takeBreakNow(now: at(3)) == [])

        var a = BreakScheduler(settings: defaultSettings, now: t0)
        _ = a.beginAway(.screenLocked, since: at(10), now: at(10))
        #expect(a.takeBreakNow(now: at(15)) == [.returned(cycleReset: false), .breakStarted(endsAt: at(35))])
        #expect(a.awayReasons.isEmpty)
    }

    @Test func pauseExpiresWhileLocked() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 1800, now: at(0))
        #expect(s.beginAway(.screenLocked, since: at(100), now: at(100)) == [])
        #expect(s.tick(now: at(1800)) == [.resumed, .wentAway])
        #expect(s.tick(now: at(5000)) == [])  // no countdown and no break behind the lock screen
        #expect(s.endAway(.screenLocked, now: at(5001)) == [.returned(cycleReset: true)])
    }

    @Test func unlockDuringPauseIsSilent() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(0))
        #expect(s.beginAway(.screenLocked, since: at(1), now: at(1)) == [])
        #expect(s.endAway(.screenLocked, now: at(50)) == [])
        #expect(s.state == .paused(until: nil))
    }

    @Test func pauseExpiresDuringSleepThenWake() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 1800, now: at(0))
        _ = advance(&s, to: 100)
        _ = s.beginAway(.systemAsleep, since: at(100), now: at(100))
        // Wake 3 h later; didWake is delivered before the first tick.
        #expect(s.endAway(.systemAsleep, now: at(10_900)) == [.resumed, .wentAway, .returned(cycleReset: false)])
        #expect(s.state == .working(cycleStart: at(10_900), nextBreakAt: at(12_100)))
    }

    // MARK: - Away: locks, sleep and gaps

    @Test func shortAndLongLock() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 600)
        #expect(s.beginAway(.screenLocked, since: at(600), now: at(600)) == [.wentAway])
        #expect(s.state == .away(since: at(600), frozenRemaining: 600))
        #expect(s.endAway(.screenLocked, now: at(610)) == [.returned(cycleReset: false)])
        #expect(s.state == .working(cycleStart: at(610), nextBreakAt: at(1210)))
        _ = advance(&s, to: 700)
        #expect(s.beginAway(.screenLocked, since: at(700), now: at(700)) == [.wentAway])
        #expect(s.endAway(.screenLocked, now: at(720)) == [.returned(cycleReset: true)])
        #expect(s.state == .working(cycleStart: at(720), nextBreakAt: at(1920)))
    }

    @Test func shortAbsenceRestoresAtLeastTheMinimumRemaining() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1195)
        #expect(s.beginAway(.screenLocked, since: at(1195), now: at(1195)) == [.wentAway])
        #expect(s.state == .away(since: at(1195), frozenRemaining: 5))
        #expect(s.endAway(.screenLocked, now: at(1200)) == [.returned(cycleReset: false)])
        #expect(s.state == .working(cycleStart: at(1200), nextBreakAt: at(1215)))
        #expect(s.timeUntilNextBreak(now: at(1200)) == BreakScheduler.minimumRestoredRemaining)
    }

    /// Any absence shorter than a break that starts less than `minimumRestoredRemaining` before a deadline comes
    /// back to exactly the floor, whatever was left when it began.
    @Test(arguments: [0.25, 7.5, 14.5], [0.0, 10, 89])
    func shortAbsenceBeforeADeadlineRestoresTheFloor(frozen: TimeInterval, away: TimeInterval) throws {
        var settings = defaultSettings
        settings.breakDurationSeconds = 90
        var s = BreakScheduler(settings: settings, now: t0)
        let lockAt = settings.workInterval - frozen
        _ = advance(&s, to: lockAt)
        #expect(s.beginAway(.screenLocked, since: at(lockAt), now: at(lockAt)) == [.wentAway])
        #expect(s.state == .away(since: at(lockAt), frozenRemaining: frozen))
        #expect(s.endAway(.screenLocked, now: at(lockAt + away)) == [.returned(cycleReset: false)])
        let remaining = try #require(s.timeUntilNextBreak(now: at(lockAt + away)))
        #expect(remaining == BreakScheduler.minimumRestoredRemaining)
    }

    @Test func longAbsenceIgnoresTheRestoreFloor() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1195)
        _ = s.beginAway(.screenLocked, since: at(1195), now: at(1195))
        #expect(s.endAway(.screenLocked, now: at(1215)) == [.returned(cycleReset: true)])
        #expect(s.state == .working(cycleStart: at(1215), nextBreakAt: at(2415)))
    }

    @Test func lockSleepWakeUnlockOrdering() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        var events = run(&s, from: 1, through: 600)
        events += s.beginAway(.screenLocked, since: at(600), now: at(600))
        events += run(&s, from: 601, through: 660)
        events += s.beginAway(.displayAsleep, since: at(660), now: at(660))
        events += s.beginAway(.systemAsleep, since: at(661), now: at(661))
        // Asleep for 2 h without ticks. The timer may fire before didWake is delivered.
        events += s.tick(now: at(7861))
        events += s.endAway(.systemAsleep, now: at(7862))
        events += s.observeIdle(seconds: 7200, now: at(7863))  // idle reported while still locked
        events += s.endAway(.displayAsleep, now: at(7864))
        events += s.endAway(.screenLocked, now: at(7870))
        #expect(events == [.wentAway])  // still idle-away until there is input
        events += s.observeIdle(seconds: 0, now: at(7871))
        #expect(events == [.wentAway, .returned(cycleReset: true)])
        #expect(s.state == .working(cycleStart: at(7871), nextBreakAt: at(9071)))
    }

    @Test func sleepWithoutNotificationsIsAGap() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = run(&s, from: 1, through: 1000)
        // A 2 h gap during which the deadline passed must not pop a break on wake.
        #expect(s.observeIdle(seconds: 0, now: at(8200)) == [.cycleRestarted])
        #expect(s.state == .working(cycleStart: at(8200), nextBreakAt: at(9400)))
        #expect(s.tick(now: at(8201)) == [])
    }

    @Test func smallGapBelowBreakDurationProcessesDeadlineNormally() {
        var settings = defaultSettings
        settings.breakDurationSeconds = 300
        var s = BreakScheduler(settings: settings, now: t0)
        _ = run(&s, from: 1, through: 1150)
        #expect(s.tick(now: at(1300)) == [.breakStarted(endsAt: at(1600))])  // 150 s gap < 300 s break
    }

    @Test func hardAwayDuringBreakCompletesIt() {
        var s = schedulerOnFirstBreak()
        #expect(s.beginAway(.screenLocked, since: at(1205), now: at(1205)) == [.breakEnded(.completed), .wentAway])
        #expect(s.state == .away(since: at(1205), frozenRemaining: 1200))
        #expect(s.endAway(.screenLocked, now: at(1210)) == [.returned(cycleReset: false)])
        #expect(s.state == .working(cycleStart: at(1210), nextBreakAt: at(2410)))
    }

    @Test func breakDeadlinePassesWhileLockedDoesNotStartBreak() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1100)
        _ = s.beginAway(.screenLocked, since: at(1100), now: at(1100))
        #expect(advance(&s, to: 5000) == [])
        #expect(s.endAway(.screenLocked, now: at(5000)) == [.returned(cycleReset: true)])
    }

    @Test func duplicateAwayCallsAreIdempotent() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        #expect(s.beginAway(.displayAsleep, since: at(10), now: at(10)) == [.wentAway])
        #expect(s.beginAway(.displayAsleep, since: at(11), now: at(11)) == [])
        #expect(s.beginAway(.screenLocked, since: at(5), now: at(12)) == [])  // since does not move
        #expect(s.state == .away(since: at(10), frozenRemaining: 1190))
        #expect(s.endAway(.sessionInactive, now: at(13)) == [])
    }

    @Test func userActionClearsStaleReasons() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.beginAway(.screenLocked, since: at(100), now: at(100))  // the unlock notification is lost
        #expect(s.resetCycle(now: at(5000)) == [.returned(cycleReset: true), .cycleRestarted])
        #expect(s.endAway(.screenLocked, now: at(5001)) == [])
        #expect(s.state == .working(cycleStart: at(5000), nextBreakAt: at(6200)))
    }

    @Test func backwardClockJumpPreservesRemaining() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 601)
        #expect(s.tick(now: at(600 - 3600)) == [])
        #expect(s.timeUntilNextBreak(now: at(-3000)) == 600)
        _ = s.pause(for: 1800, now: at(-3000))
        _ = s.tick(now: at(-7000))
        #expect(s.state == .paused(until: at(-5200)))
    }

    // MARK: - Idle

    @Test func idleSinceInThePastFreezesFromIdleStart() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = run(&s, from: 1, through: 700)
        // Idle since 400, detected at 700.
        #expect(s.observeIdle(seconds: 300, now: at(700)) == [.wentAway])
        #expect(s.state == .away(since: at(400), frozenRemaining: 800))
    }

    @Test func idleSinceBeforeCycleStartIsClamped() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 600, now: at(0))
        _ = run(&s, from: 1, through: 600)  // resumes at 600
        #expect(s.observeIdle(seconds: 900, now: at(601)) == [.wentAway])
        #expect(s.state == .away(since: at(600), frozenRemaining: 1200))  // not 1500
    }

    @Test func idleDuringLongBreakDoesNotCutItShort() {
        var settings = defaultSettings
        settings.breakDurationSeconds = 300
        settings.idleThresholdMinutes = 1
        var s = schedulerOnFirstBreak(settings: settings)
        var events: [SchedulerEvent] = []
        for t in stride(from: 1201.0, through: 1499, by: 1) {
            events += s.observeIdle(seconds: t - 1200, now: at(t))
        }
        #expect(events == [])
        #expect(s.breakTimeRemaining(now: at(1499)) == 1)
        #expect(s.observeIdle(seconds: 300, now: at(1500)) == [.breakEnded(.completed), .wentAway])
        // 30 s away < 300 s break, so the countdown restores to the full interval frozen at break end.
        #expect(s.observeIdle(seconds: 0, now: at(1530)) == [.returned(cycleReset: false)])
        #expect(s.state == .working(cycleStart: at(1530), nextBreakAt: at(2730)))
    }

    @Test func pauseWhenIdleToggledOffWhileIdleAway() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 400)
        #expect(s.observeIdle(seconds: 300, now: at(400)) == [.wentAway])
        var off = defaultSettings
        off.pauseWhenIdle = false
        #expect(s.updateSettings(off, now: at(401)) == [.returned(cycleReset: true)])
        #expect(s.observeIdle(seconds: 9999, now: at(402)) == [])
        #expect(s.beginAway(.idle, since: at(403), now: at(403)) == [])
    }

    @Test func pauseWhenIdleOffKeepsHardReasons() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 100)
        _ = s.beginAway(.screenLocked, since: at(100), now: at(100))
        _ = advance(&s, to: 500)
        _ = s.observeIdle(seconds: 400, now: at(500))
        var off = defaultSettings
        off.pauseWhenIdle = false
        #expect(s.updateSettings(off, now: at(501)) == [])
        #expect(s.awayReasons == [.screenLocked])
    }

    // MARK: - Settings

    @Test func settingsChanges() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        var c = defaultSettings
        c.workIntervalMinutes = 30
        #expect(s.updateSettings(defaultSettings, now: at(10)) == [])
        #expect(s.updateSettings(c, now: at(10)) == [.cycleRestarted])
        #expect(s.state == .working(cycleStart: at(10), nextBreakAt: at(1810)))

        c.breakDurationSeconds = 60
        #expect(s.updateSettings(c, now: at(11)) == [])
        #expect(s.state == .working(cycleStart: at(10), nextBreakAt: at(1810)))

        _ = advance(&s, to: 1810)
        _ = s.tick(now: at(1810))
        var d = c
        d.workIntervalMinutes = 10
        d.breakDurationSeconds = 10
        #expect(s.updateSettings(d, now: at(1815)) == [])
        #expect(s.state == .onBreak(startedAt: at(1810), endsAt: at(1870)))  // unchanged mid-break

        _ = advance(&s, to: 1870)
        _ = s.tick(now: at(1870))
        #expect(s.state == .working(cycleStart: at(1870), nextBreakAt: at(2470)))  // new interval next cycle

        var bad = d
        bad.workIntervalMinutes = 0
        bad.breakDurationSeconds = 5000
        _ = s.updateSettings(bad, now: at(1871))
        #expect(s.settings.workIntervalMinutes == 1)
        #expect(s.settings.breakDurationSeconds == 300)
    }

    @Test func workIntervalChangeWhileAwayResetsFrozenRemaining() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 600)
        _ = s.beginAway(.screenLocked, since: at(600), now: at(600))
        var c = defaultSettings
        c.workIntervalMinutes = 45
        #expect(s.updateSettings(c, now: at(601)) == [])
        #expect(s.state == .away(since: at(600), frozenRemaining: 2700))
    }

    @Test func initClampsSettings() {
        var raw = defaultSettings
        raw.workIntervalMinutes = 500
        let s = BreakScheduler(settings: raw, now: t0)
        #expect(s.settings.workIntervalMinutes == 120)
        #expect(s.state == .working(cycleStart: t0, nextBreakAt: at(7200)))
    }

    // MARK: - Queries

    @Test func queriesAreStateSpecific() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        #expect(s.timeUntilNextBreak(now: at(100)) == 1100)
        #expect(s.timeUntilNextBreak(now: at(5000)) == 0)  // clamped at 0
        #expect(s.breakTimeRemaining(now: at(100)) == nil)
        #expect(s.breakProgress(now: at(100)) == nil)

        _ = s.takeBreakNow(now: at(100))
        #expect(s.timeUntilNextBreak(now: at(105)) == nil)
        #expect(s.breakTimeRemaining(now: at(105)) == 15)
        #expect(s.breakProgress(now: at(105)) == 0.25)
        #expect(s.breakProgress(now: at(50)) == 0)  // clamped to 0...1
        #expect(s.breakProgress(now: at(500)) == 1)
        #expect(s.breakTimeRemaining(now: at(500)) == 0)
    }
}

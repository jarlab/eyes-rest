import Foundation
import Testing
@testable import EyeRestCore

@Suite("BreakScheduler call hold")
struct CallHoldTests {
    @Test func holdAtDueTimeDefersTheBreak() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        #expect(s.tick(now: at(1200), holdBreak: true) == [])
        #expect(s.state == .working(cycleStart: t0, nextBreakAt: at(1230)))
        #expect(s.isHoldingBreak)
        #expect(s.timeUntilNextBreak(now: at(1200)) == BreakScheduler.holdLeadTime)
    }

    @Test func releasedHoldStartsTheBreakThirtySecondsAfterTheLastHeldTick() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        #expect(run(&s, from: 1200, through: 1300, holdBreak: true) == [])
        #expect(s.state == .working(cycleStart: t0, nextBreakAt: at(1330)))
        #expect(s.isHoldingBreak)

        #expect(s.tick(now: at(1301)) == [])
        #expect(!s.isHoldingBreak)
        #expect(advance(&s, to: 1330) == [])
        #expect(s.tick(now: at(1330)) == [.breakStarted(endsAt: at(1350))])
    }

    @Test func holdOnlyEngagesInsideTheLeadTime() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        #expect(run(&s, from: 1, through: 1170, holdBreak: true) == [])  // remaining 1199 down to 30
        #expect(s.state == .working(cycleStart: t0, nextBreakAt: at(1200)))
        #expect(!s.isHoldingBreak)

        #expect(s.tick(now: at(1171), holdBreak: true) == [])  // remaining 29 < 30
        #expect(s.state == .working(cycleStart: t0, nextBreakAt: at(1201)))
        #expect(s.isHoldingBreak)
    }

    @Test func holdIsIgnoredWhilePaused() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 60, now: at(1))
        #expect(run(&s, from: 2, through: 60, holdBreak: true) == [])
        #expect(!s.isHoldingBreak)
        #expect(s.tick(now: at(61), holdBreak: true) == [.resumed])
        #expect(s.state == .working(cycleStart: at(61), nextBreakAt: at(1261)))
        #expect(!s.isHoldingBreak)
    }

    @Test func holdIsIgnoredWhileAway() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1190)
        _ = s.beginAway(.screenLocked, since: at(1190), now: at(1190))
        #expect(run(&s, from: 1191, through: 1300, holdBreak: true) == [])
        #expect(s.state == .away(since: at(1190), frozenRemaining: 10))
        #expect(!s.isHoldingBreak)
    }

    @Test func holdDoesNotExtendABreak() {
        var s = schedulerOnFirstBreak()
        #expect(run(&s, from: 1201, through: 1219, holdBreak: true) == [])
        #expect(!s.isHoldingBreak)
        #expect(s.tick(now: at(1220), holdBreak: true) == [.breakEnded(.completed)])
        #expect(s.state == .working(cycleStart: at(1220), nextBreakAt: at(2420)))
        #expect(!s.isHoldingBreak)
    }

    @Test func takeBreakNowOverridesTheHold() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        _ = s.tick(now: at(1200), holdBreak: true)
        #expect(s.takeBreakNow(now: at(1201)) == [.breakStarted(endsAt: at(1221))])
        #expect(!s.isHoldingBreak)
    }

    enum LeaveWorking: String, CaseIterable, Sendable {
        case takeBreakNow, pause, screenLock, deadlineReachedByNonTickCall
    }

    @Test(arguments: LeaveWorking.allCases)
    func holdClearsWhenStateLeavesWorking(_ action: LeaveWorking) {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        _ = s.tick(now: at(1200), holdBreak: true)
        #expect(s.isHoldingBreak)
        switch action {
        case .takeBreakNow: _ = s.takeBreakNow(now: at(1201))
        case .pause: _ = s.pause(for: nil, now: at(1201))
        case .screenLock: _ = s.beginAway(.screenLocked, since: at(1201), now: at(1201))
        case .deadlineReachedByNonTickCall:
            #expect(s.observeIdle(seconds: 0, now: at(1230)) == [.breakStarted(endsAt: at(1250))])
        }
        #expect(!s.state.isWorking)
        #expect(!s.isHoldingBreak)
    }

    @Test func nonTickCallsLeaveTheHoldFlagUntilTheNextTick() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        _ = s.tick(now: at(1200), holdBreak: true)
        #expect(s.postpone(now: at(1201)) == [])
        #expect(s.state == .working(cycleStart: t0, nextBreakAt: at(1530)))
        #expect(s.isHoldingBreak)
        #expect(s.tick(now: at(1202), holdBreak: true) == [])  // 328 s left: nothing to hold
        #expect(!s.isHoldingBreak)
        #expect(s.state == .working(cycleStart: t0, nextBreakAt: at(1530)))
    }
}

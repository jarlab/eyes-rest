import Foundation
import Testing
@testable import EyeRestCore

/// Default settings throughout unless a test says otherwise: a 20 min (1200 s) interval and a 20 s reminder,
/// so the first card appears at 1200 and closes itself at 1220.
@Suite("ReminderScheduler")
struct ReminderSchedulerTests {
    private func settings(interval: Int = 20, reminder: Int = 20) -> EyeRestSettings {
        var s = defaultSettings
        s.intervalMinutes = interval
        s.reminderSeconds = reminder
        return s
    }

    private func counting(_ start: TimeInterval, _ next: TimeInterval) -> ReminderState {
        .counting(cycleStart: at(start), nextAt: at(next))
    }

    private func reminding(_ shown: TimeInterval, _ ends: TimeInterval) -> ReminderState {
        .reminding(shownAt: at(shown), endsAt: at(ends))
    }

    // MARK: - Initial state

    @Test func startsCountingAFullInterval() {
        let s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.state == counting(0, 1200))
        #expect(s.settings == defaultSettings)
        #expect(s.suspendReasons.isEmpty)
        #expect(s.lastSeen == t0)
        #expect(s.timeUntilNextReminder(now: t0) == 1200)
        #expect(s.reminderTimeRemaining(now: t0) == nil)
        #expect(s.reminderProgress(now: t0) == nil)
    }

    @Test func initClampsSettings() {
        let s = ReminderScheduler(settings: settings(interval: 0, reminder: 500), now: t0)
        #expect(s.settings.intervalMinutes == 1)
        #expect(s.settings.reminderSeconds == 120)
        #expect(s.state == counting(0, 60))
    }

    @Test func gapThresholdIsOneMinute() {
        #expect(ReminderScheduler.gapThreshold == 60)
    }

    // MARK: - Counting and deadlines

    @Test func ticksBeforeTheDeadlineChangeNothing() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(advance(&s, to: 1200).isEmpty)
        #expect(s.state == counting(0, 1200))
        #expect(s.timeUntilNextReminder(now: at(1199)) == 1)
    }

    @Test func deadlineShowsTheCard() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        #expect(s.tick(now: at(1200)) == [.shown(endsAt: at(1220))])
        #expect(s.state == reminding(1200, 1220))
        #expect(s.timeUntilNextReminder(now: at(1200)) == nil)
    }

    @Test func cardClosesItselfAndTheNextIntervalStartsThen() {
        var s = schedulerReminding()
        #expect(advance(&s, to: 1220).isEmpty)
        #expect(s.state == reminding(1200, 1220))
        #expect(s.tick(now: at(1220)) == [.hidden])
        #expect(s.state == counting(1220, 2420))
    }

    @Test func cyclesRepeatWithAlternatingEvents() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        let events = run(&s, from: 1, through: 5000)
        #expect(events == [
            .shown(endsAt: at(1220)), .hidden,
            .shown(endsAt: at(2440)), .hidden,
            .shown(endsAt: at(3660)), .hidden,
            .shown(endsAt: at(4880)), .hidden,
        ])
        #expect(s.state == counting(4880, 6080))
    }

    @Test func cardLengthFollowsTheSetting() {
        let s = schedulerReminding(settings: settings(interval: 1, reminder: 45))
        #expect(s.state == reminding(60, 105))
    }

    @Test func lateTickWithinTheThresholdShowsTheCardAtNow() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1190)  // last tick at 1189
        #expect(s.tick(now: at(1240)) == [.shown(endsAt: at(1260))])  // 51 s later
        #expect(s.state == reminding(1240, 1260))
    }

    @Test func aJumpOfExactlyTheThresholdIsNotAGap() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1190)  // last tick at 1189
        #expect(s.tick(now: at(1249)) == [.shown(endsAt: at(1269))])
    }

    @Test func atMostOneDeadlinePerCall() {
        // The card's end passed, but the next interval starts at now rather than also firing.
        var s = schedulerReminding()
        #expect(s.tick(now: at(1250)) == [.hidden])
        #expect(s.state == counting(1250, 2450))

        // A pause that expires starts counting; it never shows a card in the same call.
        var p = ReminderScheduler(settings: settings(interval: 1), now: t0)
        _ = p.pause(for: 60, now: at(10))
        _ = p.tick(now: at(69))
        #expect(p.tick(now: at(70)) == [.resumed])
        #expect(p.state == counting(70, 130))
    }

    @Test func repeatedTicksAtTheSameInstantAreIdempotent() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.tick(now: t0).isEmpty)
        #expect(s.state == counting(0, 1200))

        var r = schedulerReminding()
        #expect(r.tick(now: at(1200)).isEmpty)
        #expect(r.state == reminding(1200, 1220))
        _ = advance(&r, to: 1220)
        #expect(r.tick(now: at(1220)) == [.hidden])
        #expect(r.tick(now: at(1220)).isEmpty)
        #expect(r.state == counting(1220, 2420))
    }

    // MARK: - Queries

    @Test func timeUntilNextReminderIsNeverNegative() {
        let s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.timeUntilNextReminder(now: at(600)) == 600)
        #expect(s.timeUntilNextReminder(now: at(1500)) == 0)  // queried past the deadline without a tick
    }

    @Test func reminderTimeRemainingAndProgress() {
        let s = schedulerReminding()
        #expect(s.reminderTimeRemaining(now: at(1200)) == 20)
        #expect(s.reminderTimeRemaining(now: at(1205)) == 15)
        #expect(s.reminderTimeRemaining(now: at(1230)) == 0)
        #expect(s.reminderProgress(now: at(1200)) == 0)
        #expect(s.reminderProgress(now: at(1210)) == 0.5)
        #expect(s.reminderProgress(now: at(1220)) == 1)
        #expect(s.reminderProgress(now: at(1300)) == 1)  // clamped
        #expect(s.reminderProgress(now: at(1100)) == 0)  // clamped
    }

    @Test func queriesAreNilOutsideTheirState() {
        var paused = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = paused.pause(for: nil, now: at(1))
        var suspended = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = suspended.suspend(.screenLocked, now: at(1))
        for s in [paused, suspended] {
            #expect(s.timeUntilNextReminder(now: at(2)) == nil)
            #expect(s.reminderTimeRemaining(now: at(2)) == nil)
            #expect(s.reminderProgress(now: at(2)) == nil)
        }
    }

    @Test func queriesDoNotMoveTheClock() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.tick(now: at(5))
        _ = s.timeUntilNextReminder(now: at(900))
        _ = s.reminderTimeRemaining(now: at(900))
        _ = s.reminderProgress(now: at(900))
        #expect(s.lastSeen == at(5))
    }

    // MARK: - Remind Me Now

    @Test func remindNowWhileCounting() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 100)
        #expect(s.remindNow(now: at(100)) == [.shown(endsAt: at(120))])
        #expect(s.state == reminding(100, 120))
        _ = advance(&s, to: 120)
        #expect(s.tick(now: at(120)) == [.hidden])
        #expect(s.state == counting(120, 1320))
    }

    @Test func remindNowUsesTheCurrentReminderLength() {
        var s = ReminderScheduler(settings: settings(reminder: 45), now: t0)
        #expect(s.remindNow(now: at(10)) == [.shown(endsAt: at(55))])
    }

    @Test(arguments: [nil, 1800] as [TimeInterval?])
    func remindNowWhilePausedResumesAndShows(duration: TimeInterval?) {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: duration, now: at(10))
        #expect(s.remindNow(now: at(20)) == [.resumed, .shown(endsAt: at(40))])
        #expect(s.state == reminding(20, 40))
    }

    @Test func remindNowWhileTheCardIsVisibleDoesNothing() {
        var s = schedulerReminding()
        #expect(s.remindNow(now: at(1205)).isEmpty)
        #expect(s.state == reminding(1200, 1220))
    }

    @Test func remindNowWhileSuspendedStartsFreshThenShows() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.screenLocked, now: at(10))
        #expect(s.remindNow(now: at(20)) == [.restarted, .shown(endsAt: at(40))])
        #expect(s.state == reminding(20, 40))
        #expect(s.suspendReasons.isEmpty)
    }

    @Test func remindNowTwiceIsIdempotent() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.remindNow(now: at(10)) == [.shown(endsAt: at(30))])
        #expect(s.remindNow(now: at(10)).isEmpty)
        #expect(s.state == reminding(10, 30))
    }

    @Test func remindNowAtTheDeadlineShowsOnce() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        #expect(s.remindNow(now: at(1200)) == [.shown(endsAt: at(1220))])
    }

    // MARK: - Dismiss (Done / ×)

    @Test func dismissClosesTheCardAndStartsTheNextInterval() {
        var s = schedulerReminding()
        _ = advance(&s, to: 1205)
        #expect(s.dismiss(now: at(1205)) == [.hidden])
        #expect(s.state == counting(1205, 2405))
    }

    @Test func dismissTwiceIsIdempotent() {
        var s = schedulerReminding()
        #expect(s.dismiss(now: at(1205)) == [.hidden])
        #expect(s.dismiss(now: at(1205)).isEmpty)
        #expect(s.dismiss(now: at(1206)).isEmpty)
        #expect(s.state == counting(1205, 2405))
    }

    @Test func dismissAfterTheCardClosedItselfHidesOnlyOnce() {
        var s = schedulerReminding()
        _ = advance(&s, to: 1220)
        #expect(s.dismiss(now: at(1220)) == [.hidden])  // from reconciling, not a second hide
        #expect(s.state == counting(1220, 2420))
    }

    @Test func dismissWithoutACardDoesNothing() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.dismiss(now: at(10)).isEmpty)
        #expect(s.state == counting(0, 1200))

        _ = s.pause(for: 1800, now: at(20))
        #expect(s.dismiss(now: at(30)).isEmpty)
        #expect(s.state == .paused(until: at(1820)))
    }

    @Test func dismissWhileSuspendedIsPresenceProof() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.displayAsleep, now: at(10))
        #expect(s.dismiss(now: at(20)) == [.restarted])
        #expect(s.state == counting(20, 1220))
        #expect(s.suspendReasons.isEmpty)
    }

    // MARK: - Pause

    @Test func pauseForADurationWhileCounting() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.pause(for: 1800, now: at(10)) == [.paused(until: at(1810))])
        #expect(s.state == .paused(until: at(1810)))
    }

    @Test func pauseUntilResumed() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.pause(for: nil, now: at(10)) == [.paused(until: nil)])
        #expect(s.state == .paused(until: nil))
    }

    @Test func pauseWhileRemindingHidesTheCardFirst() {
        var s = schedulerReminding()
        #expect(s.pause(for: 1800, now: at(1205)) == [.hidden, .paused(until: at(3005))])
        #expect(s.state == .paused(until: at(3005)))
    }

    @Test func pausingAgainWithTheSameEndIsIdempotent() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 1800, now: at(10))
        #expect(s.pause(for: 1800, now: at(10)).isEmpty)
        _ = s.pause(for: nil, now: at(20))
        #expect(s.pause(for: nil, now: at(30)).isEmpty)
        #expect(s.state == .paused(until: nil))
    }

    @Test func pausingAgainReplacesTheEnd() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 1800, now: at(10))
        #expect(s.pause(for: 3600, now: at(20)) == [.paused(until: at(3620))])
        #expect(s.pause(for: nil, now: at(30)) == [.paused(until: nil)])
        #expect(s.pause(for: 60, now: at(40)) == [.paused(until: at(100))])
        #expect(s.state == .paused(until: at(100)))
    }

    @Test(arguments: [0, -5, .nan, .infinity, -.infinity] as [TimeInterval])
    func invalidPauseDurationsAreIgnored(duration: TimeInterval) {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.pause(for: duration, now: at(10)).isEmpty)
        #expect(s.state == counting(0, 1200))
        #expect(s.lastSeen == at(10))  // still reconciled

        // Not a user action either, so stale reasons stay.
        _ = s.suspend(.screenLocked, now: at(20))
        #expect(s.pause(for: duration, now: at(30)).isEmpty)
        #expect(s.state == .suspended)
        #expect(s.suspendReasons == [.screenLocked])
    }

    @Test func timedPauseExpires() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 60, now: at(10))
        #expect(advance(&s, to: 70).isEmpty)
        #expect(s.tick(now: at(70)) == [.resumed])
        #expect(s.state == counting(70, 1270))
    }

    @Test func timedPauseExpiresAfterAGap() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 60, now: at(10))
        #expect(s.tick(now: at(5000)) == [.resumed])
        #expect(s.state == counting(5000, 6200))
    }

    @Test func indefinitePauseIgnoresTimeAndGaps() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        #expect(s.tick(now: at(100_000)).isEmpty)
        #expect(s.tick(now: at(100_001)).isEmpty)
        #expect(s.state == .paused(until: nil))
    }

    // MARK: - Resume

    @Test func resumeStartsAFreshInterval() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        #expect(s.resume(now: at(500)) == [.resumed])
        #expect(s.state == counting(500, 1700))
    }

    @Test func resumeATimedPauseEarly() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 3600, now: at(10))
        #expect(s.resume(now: at(40)) == [.resumed])
        #expect(s.state == counting(40, 1240))
    }

    @Test func resumeWhenNotPausedDoesNothing() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.resume(now: at(10)).isEmpty)
        #expect(s.state == counting(0, 1200))

        var r = schedulerReminding()
        #expect(r.resume(now: at(1205)).isEmpty)
        #expect(r.state == reminding(1200, 1220))
    }

    @Test func resumeTwiceIsIdempotent() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        #expect(s.resume(now: at(20)) == [.resumed])
        #expect(s.resume(now: at(20)).isEmpty)
        #expect(s.state == counting(20, 1220))
    }

    // MARK: - Reset

    @Test func resetWhileCountingRestartsTheInterval() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 500)
        #expect(s.reset(now: at(500)) == [.restarted])
        #expect(s.state == counting(500, 1700))
    }

    @Test func resetTwiceAtTheSameInstantIsIdempotent() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 500)
        #expect(s.reset(now: at(500)) == [.restarted])
        #expect(s.reset(now: at(500)).isEmpty)
        #expect(s.state == counting(500, 1700))

        var fresh = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(fresh.reset(now: t0).isEmpty)  // already a fresh interval
    }

    @Test func resetWhileRemindingClosesTheCard() {
        var s = schedulerReminding()
        #expect(s.reset(now: at(1205)) == [.hidden, .restarted])
        #expect(s.state == counting(1205, 2405))
    }

    @Test func resetWhilePausedEndsThePause() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        #expect(s.reset(now: at(20)) == [.resumed, .restarted])
        #expect(s.state == counting(20, 1220))
    }

    @Test func resetWhileSuspendedRestartsOnce() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.sessionInactive, now: at(10))
        #expect(s.reset(now: at(20)) == [.restarted])
        #expect(s.state == counting(20, 1220))
        #expect(s.suspendReasons.isEmpty)
    }

    // MARK: - Suspend / unsuspend

    @Test(arguments: SuspendReason.allCases)
    func everyReasonSuspendsACountdown(reason: SuspendReason) {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 600)
        #expect(s.suspend(reason, now: at(600)).isEmpty)
        #expect(s.state == .suspended)
        #expect(s.suspendReasons == [reason])
        #expect(s.unsuspend(reason, now: at(700)) == [.restarted])
        #expect(s.state == counting(700, 1900))  // a fresh interval, not the 600 s that were left
        #expect(s.suspendReasons.isEmpty)
    }

    @Test func suspendWhileRemindingHidesTheCard() {
        var s = schedulerReminding()
        #expect(s.suspend(.systemAsleep, now: at(1205)) == [.hidden])
        #expect(s.state == .suspended)
        #expect(s.unsuspend(.systemAsleep, now: at(3000)) == [.restarted])
        #expect(s.state == counting(3000, 4200))
    }

    @Test func suspendWhilePausedOnlyRecordsTheReason() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 1800, now: at(10))
        #expect(s.suspend(.screenLocked, now: at(20)).isEmpty)
        #expect(s.state == .paused(until: at(1810)))
        #expect(s.suspendReasons == [.screenLocked])
        #expect(s.unsuspend(.screenLocked, now: at(30)).isEmpty)
        #expect(s.state == .paused(until: at(1810)))
        #expect(s.suspendReasons.isEmpty)
    }

    @Test func pauseExpiryWhileSuspendedStaysSuspended() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 60, now: at(10))
        _ = s.suspend(.systemAsleep, now: at(20))
        #expect(s.tick(now: at(70)) == [.resumed])
        #expect(s.state == .suspended)
        #expect(s.suspendReasons == [.systemAsleep])
        #expect(s.unsuspend(.systemAsleep, now: at(80)) == [.restarted])
        #expect(s.state == counting(80, 1280))
    }

    @Test func suspendingWithTheSameReasonTwiceIsIdempotent() {
        var s = schedulerReminding()
        #expect(s.suspend(.screenLocked, now: at(1205)) == [.hidden])
        #expect(s.suspend(.screenLocked, now: at(1205)).isEmpty)
        #expect(s.suspend(.screenLocked, now: at(1206)).isEmpty)
        #expect(s.state == .suspended)
        #expect(s.suspendReasons == [.screenLocked])
    }

    @Test func unsuspendingTwiceIsIdempotent() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.screenLocked, now: at(10))
        #expect(s.unsuspend(.screenLocked, now: at(20)) == [.restarted])
        #expect(s.unsuspend(.screenLocked, now: at(20)).isEmpty)
        #expect(s.unsuspend(.screenLocked, now: at(21)).isEmpty)
        #expect(s.state == counting(20, 1220))
    }

    @Test func multipleReasonsMustAllClear() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.suspend(.screenLocked, now: at(10)).isEmpty)
        #expect(s.suspend(.systemAsleep, now: at(20)).isEmpty)
        #expect(s.suspend(.displayAsleep, now: at(30)).isEmpty)
        #expect(s.suspendReasons == [.screenLocked, .systemAsleep, .displayAsleep])
        #expect(s.unsuspend(.screenLocked, now: at(40)).isEmpty)
        #expect(s.unsuspend(.displayAsleep, now: at(50)).isEmpty)
        #expect(s.state == .suspended)
        #expect(s.suspendReasons == [.systemAsleep])
        #expect(s.unsuspend(.systemAsleep, now: at(60)) == [.restarted])
        #expect(s.state == counting(60, 1260))
    }

    @Test func unsuspendingAnInactiveReasonDoesNothing() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.unsuspend(.systemAsleep, now: at(10)).isEmpty)
        #expect(s.state == counting(0, 1200))

        _ = s.suspend(.screenLocked, now: at(20))
        #expect(s.unsuspend(.systemAsleep, now: at(30)).isEmpty)
        #expect(s.state == .suspended)
        #expect(s.suspendReasons == [.screenLocked])
    }

    @Test func suspensionIgnoresTimeAndGaps() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.systemAsleep, now: at(10))
        #expect(s.tick(now: at(5000)).isEmpty)
        #expect(s.tick(now: at(5001)).isEmpty)
        #expect(s.state == .suspended)
        #expect(s.unsuspend(.systemAsleep, now: at(5002)) == [.restarted])
        #expect(s.state == counting(5002, 6202))
    }

    @Test func suspendAtTheDeadlineReconcilesFirst() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        #expect(s.suspend(.screenLocked, now: at(1200)) == [.shown(endsAt: at(1220)), .hidden])
        #expect(s.state == .suspended)
    }

    // MARK: - Presence proof

    enum UserAction: String, CaseIterable, Sendable {
        case remindNow, dismiss, pause, resume, reset

        func perform(on s: inout ReminderScheduler, now: Date) -> [ReminderEvent] {
            switch self {
            case .remindNow: s.remindNow(now: now)
            case .dismiss: s.dismiss(now: now)
            case .pause: s.pause(for: nil, now: now)
            case .resume: s.resume(now: now)
            case .reset: s.reset(now: now)
            }
        }
    }

    @Test(arguments: UserAction.allCases)
    func userActionsClearStaleReasons(action: UserAction) {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.screenLocked, now: at(10))
        _ = s.suspend(.displayAsleep, now: at(11))
        let events = action.perform(on: &s, now: at(20))
        let expected: [ReminderEvent] = switch action {
        case .remindNow: [.restarted, .shown(endsAt: at(40))]
        case .pause: [.restarted, .paused(until: nil)]
        case .dismiss, .resume, .reset: [.restarted]
        }
        #expect(events == expected)
        #expect(s.suspendReasons.isEmpty)
        #expect(s.state != .suspended)
        // The stale notification finally arriving changes nothing.
        #expect(s.unsuspend(.screenLocked, now: at(30)).isEmpty)
        #expect(s.unsuspend(.displayAsleep, now: at(31)).isEmpty)
    }

    @Test(arguments: UserAction.allCases)
    func userActionsWhileCountingKeepReasonsEmpty(action: UserAction) {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = action.perform(on: &s, now: at(20))
        #expect(s.suspendReasons.isEmpty)
        #expect(s.state != .suspended)
    }

    @Test func presenceWhilePausedKeepsThePause() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        _ = s.suspend(.screenLocked, now: at(20))
        #expect(s.pause(for: 1800, now: at(30)) == [.paused(until: at(1830))])
        #expect(s.suspendReasons.isEmpty)
        #expect(s.tick(now: at(1830)) == [.resumed])
        #expect(s.state == counting(1830, 3030))  // counting, not suspended: the reason was cleared
    }

    @Test func resumeClearsStaleReasons() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        _ = s.suspend(.screenLocked, now: at(20))
        #expect(s.resume(now: at(30)) == [.resumed])
        #expect(s.state == counting(30, 1230))
        #expect(s.suspendReasons.isEmpty)
    }

    @Test func ticksAndSettingsChangesAreNotPresenceProof() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.screenLocked, now: at(10))
        #expect(s.tick(now: at(20)).isEmpty)
        #expect(s.updateSettings(settings(interval: 30), now: at(21)).isEmpty)
        #expect(s.state == .suspended)
        #expect(s.suspendReasons == [.screenLocked])
    }

    // MARK: - Backward clock jumps

    @Test func backwardJumpWhileCountingKeepsTheRemainingTime() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 101)  // last tick at 100, 1100 s left
        #expect(s.tick(now: at(-3500)).isEmpty)
        #expect(s.state == counting(-3600, -2400))
        #expect(s.timeUntilNextReminder(now: at(-3500)) == 1100)
        #expect(advance(&s, to: -2400).isEmpty)
        #expect(s.tick(now: at(-2400)) == [.shown(endsAt: at(-2380))])
    }

    @Test func backwardJumpWhileRemindingKeepsTheRemainingTime() {
        var s = schedulerReminding()
        _ = advance(&s, to: 1206)  // last tick at 1205, 15 s left
        #expect(s.tick(now: at(605)).isEmpty)
        #expect(s.state == reminding(600, 620))
        #expect(s.reminderTimeRemaining(now: at(605)) == 15)
        #expect(s.reminderProgress(now: at(605)) == 0.25)
        _ = advance(&s, to: 620)
        #expect(s.tick(now: at(620)) == [.hidden])
    }

    @Test func backwardJumpWhilePausedKeepsTheRemainingPause() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 1800, now: at(10))  // until 1810
        _ = s.tick(now: at(50))
        #expect(s.tick(now: at(-950)).isEmpty)
        #expect(s.state == .paused(until: at(810)))
        #expect(s.tick(now: at(809)).isEmpty)
        #expect(s.tick(now: at(810)) == [.resumed])
    }

    @Test func backwardJumpLeavesUndatedStatesAlone() {
        var paused = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = paused.pause(for: nil, now: at(10))
        #expect(paused.tick(now: at(-5000)).isEmpty)
        #expect(paused.state == .paused(until: nil))

        var suspended = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = suspended.suspend(.screenLocked, now: at(10))
        #expect(suspended.tick(now: at(-5000)).isEmpty)
        #expect(suspended.state == .suspended)
        #expect(suspended.suspendReasons == [.screenLocked])
    }

    @Test func gapsAreMeasuredFromTheJumpedClock() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 101)
        _ = s.tick(now: at(-3500))
        #expect(s.tick(now: at(-3440)).isEmpty)  // 60 s later: not a gap
        #expect(s.tick(now: at(-3379)) == [.restarted])  // 61 s later: a gap
        #expect(s.state == counting(-3379, -2179))
    }

    // MARK: - Missed ticks (forward gaps)

    @Test func gapWhileCountingRestarts() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 500)  // last tick at 499
        #expect(s.tick(now: at(561)) == [.restarted])
        #expect(s.state == counting(561, 1761))
    }

    @Test func gapPastTheDeadlineRestartsInsteadOfShowing() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)  // last tick at 1199
        #expect(s.tick(now: at(5000)) == [.restarted])
        #expect(s.state == counting(5000, 6200))
    }

    @Test func gapWhileRemindingClosesTheCardAndRestarts() {
        var s = schedulerReminding()
        #expect(s.tick(now: at(1300)) == [.hidden, .restarted])
        #expect(s.state == counting(1300, 2500))
    }

    @Test func gapWhileRemindingBeforeTheCardWouldClose() {
        var s = schedulerReminding(settings: settings(reminder: 120))  // 1200...1320
        #expect(s.tick(now: at(1270)) == [.hidden, .restarted])
        #expect(s.state == counting(1270, 2470))
    }

    @Test func userActionAfterAGapReconcilesFirst() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 500)
        #expect(s.remindNow(now: at(1000)) == [.restarted, .shown(endsAt: at(1020))])

        var r = schedulerReminding()
        #expect(r.dismiss(now: at(1300)) == [.hidden, .restarted])
        #expect(r.state == counting(1300, 2500))
    }

    // MARK: - Settings changes

    @Test func intervalChangeWhileCountingRestarts() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 500)
        #expect(s.updateSettings(settings(interval: 30), now: at(500)) == [.restarted])
        #expect(s.settings.intervalMinutes == 30)
        #expect(s.state == counting(500, 2300))
    }

    @Test func intervalChangeRightAfterARestartIsReTimedSilently() {
        // A gap restarts the interval while reconciling; the interval change then only re-times it.
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 500)  // last tick at 499
        #expect(s.updateSettings(settings(interval: 30), now: at(1000)) == [.restarted])
        #expect(s.state == counting(1000, 2800))

        // Likewise for an interval that began at this very instant.
        var fresh = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(fresh.updateSettings(settings(interval: 30), now: t0).isEmpty)
        #expect(fresh.state == counting(0, 1800))

        var dismissed = schedulerReminding()
        #expect(dismissed.dismiss(now: at(1205)) == [.hidden])
        #expect(dismissed.updateSettings(settings(interval: 5), now: at(1205)).isEmpty)
        #expect(dismissed.state == counting(1205, 1505))
    }

    @Test func otherChangesWhileCountingKeepTheCountdown() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        var new = defaultSettings
        new.playSound = false
        #expect(s.updateSettings(new, now: at(10)).isEmpty)
        new.showCountdownInMenuBar = false
        #expect(s.updateSettings(new, now: at(11)).isEmpty)
        #expect(s.settings == new)
        #expect(s.state == counting(0, 1200))
    }

    @Test func reminderLengthChangeMidCountAppliesToTheNextCard() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 500)
        #expect(s.updateSettings(settings(reminder: 45), now: at(500)).isEmpty)
        #expect(s.state == counting(0, 1200))
        _ = advance(&s, to: 1200)
        #expect(s.tick(now: at(1200)) == [.shown(endsAt: at(1245))])
    }

    @Test func intervalChangeMidReminderKeepsTheCard() {
        var s = schedulerReminding()
        #expect(s.updateSettings(settings(interval: 5), now: at(1205)).isEmpty)
        #expect(s.state == reminding(1200, 1220))
        _ = advance(&s, to: 1220)
        #expect(s.tick(now: at(1220)) == [.hidden])
        #expect(s.state == counting(1220, 1520))  // the next interval uses the new length
    }

    @Test func reminderLengthChangeMidReminderKeepsTheCardsEnd() {
        var s = schedulerReminding()
        #expect(s.updateSettings(settings(reminder: 60), now: at(1205)).isEmpty)
        #expect(s.state == reminding(1200, 1220))
        _ = advance(&s, to: 1220)
        _ = s.tick(now: at(1220))
        _ = advance(&s, to: 2420)
        #expect(s.tick(now: at(2420)) == [.shown(endsAt: at(2480))])
    }

    @Test func intervalChangeWhilePausedAppliesOnResume() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        #expect(s.updateSettings(settings(interval: 10), now: at(20)).isEmpty)
        #expect(s.state == .paused(until: nil))
        _ = s.resume(now: at(30))
        #expect(s.state == counting(30, 630))
    }

    @Test func intervalChangeWhileSuspendedAppliesWhenCountingStarts() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.screenLocked, now: at(10))
        #expect(s.updateSettings(settings(interval: 10), now: at(20)).isEmpty)
        #expect(s.state == .suspended)
        #expect(s.unsuspend(.screenLocked, now: at(30)) == [.restarted])
        #expect(s.state == counting(30, 630))
    }

    @Test func settingsAreClamped() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.updateSettings(settings(interval: 500, reminder: 1), now: at(10)) == [.restarted])
        #expect(s.settings.intervalMinutes == 120)
        #expect(s.settings.reminderSeconds == 5)
        #expect(s.state == counting(10, 7210))
        // Out-of-range values equal to the current ones once clamped change nothing.
        #expect(s.updateSettings(settings(interval: 999, reminder: -3), now: at(20)).isEmpty)
        #expect(s.state == counting(10, 7210))
    }

    @Test func sameSettingsAreIgnored() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(s.updateSettings(defaultSettings, now: at(10)).isEmpty)
        #expect(s.state == counting(0, 1200))
        #expect(s.updateSettings(settings(interval: 30), now: at(20)) == [.restarted])
        #expect(s.updateSettings(settings(interval: 30), now: at(20)).isEmpty)
        #expect(s.updateSettings(settings(interval: 30), now: at(30)).isEmpty)
        #expect(s.state == counting(20, 1820))
    }

    @Test func settingsChangeAtTheDeadlineReconcilesFirst() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        #expect(s.updateSettings(settings(interval: 30), now: at(1200)) == [.shown(endsAt: at(1220))])
        #expect(s.state == reminding(1200, 1220))
        #expect(s.settings.intervalMinutes == 30)
    }

    // MARK: - Clock bookkeeping

    @Test func everyMutatingCallRecordsNow() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.tick(now: at(1)); #expect(s.lastSeen == at(1))
        _ = s.remindNow(now: at(2)); #expect(s.lastSeen == at(2))
        _ = s.dismiss(now: at(3)); #expect(s.lastSeen == at(3))
        _ = s.pause(for: 60, now: at(4)); #expect(s.lastSeen == at(4))
        _ = s.resume(now: at(5)); #expect(s.lastSeen == at(5))
        _ = s.reset(now: at(6)); #expect(s.lastSeen == at(6))
        _ = s.suspend(.screenLocked, now: at(7)); #expect(s.lastSeen == at(7))
        _ = s.unsuspend(.screenLocked, now: at(8)); #expect(s.lastSeen == at(8))
        _ = s.updateSettings(settings(interval: 5), now: at(9)); #expect(s.lastSeen == at(9))
        _ = s.tick(now: at(-9)); #expect(s.lastSeen == at(-9))
    }
}

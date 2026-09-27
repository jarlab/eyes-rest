import Foundation
import Testing
@testable import EyeRestCore

@Suite("StatusText")
struct StatusTextTests {
    private func statusLine(_ s: BreakScheduler, _ seconds: TimeInterval) -> String {
        StatusText.statusLine(s, now: at(seconds), formatTime: { _ in "unused" })
    }

    // MARK: - Status line

    @Test func workingShowsCountdown() {
        let s = BreakScheduler(settings: defaultSettings, now: t0)
        #expect(statusLine(s, 0) == "Next break in 20:00")
        #expect(statusLine(s, 0.5) == "Next break in 20:00")
        #expect(statusLine(s, 1) == "Next break in 19:59")
    }

    @Test func holdingForACall() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        _ = s.tick(now: at(1200), holdBreak: true)
        #expect(statusLine(s, 1200) == "Break on hold while you're on a call")
    }

    @Test func onBreakShowsTimeLeft() {
        let s = schedulerOnFirstBreak()
        #expect(statusLine(s, 1205) == "On break — 0:15 left")
    }

    @Test func pausedUntilUsesTheInjectedTimeFormatter() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 3600, now: at(10))
        var formatted: Date?
        let line = StatusText.statusLine(s, now: at(20)) { date in
            formatted = date
            return "3:30 PM"
        }
        #expect(line == "Paused until 3:30 PM")
        #expect(formatted == at(3610))
    }

    @Test func pausedIndefinitely() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        #expect(statusLine(s, 20) == "Paused")
    }

    @Test func away() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = s.beginAway(.screenLocked, since: at(10), now: at(10))
        #expect(statusLine(s, 20) == "Paused while you're away")
    }

    // MARK: - Menu-bar title

    @Test func menuBarTitleWhileWorking() {
        let s = BreakScheduler(settings: defaultSettings, now: t0)
        #expect(StatusText.menuBarTitle(s, now: at(0)) == "20m")
        #expect(StatusText.menuBarTitle(s, now: at(119)) == "19m")
        #expect(StatusText.menuBarTitle(s, now: at(1141)) == "59s")
    }

    @Test func menuBarTitleHiddenWhenTurnedOff() {
        var settings = defaultSettings
        settings.showCountdownInMenuBar = false
        let s = BreakScheduler(settings: settings, now: t0)
        #expect(StatusText.menuBarTitle(s, now: at(0)) == nil)
    }

    @Test func menuBarTitleHiddenWhileHolding() {
        var s = BreakScheduler(settings: defaultSettings, now: t0)
        _ = advance(&s, to: 1200)
        _ = s.tick(now: at(1200), holdBreak: true)
        #expect(StatusText.menuBarTitle(s, now: at(1200)) == nil)
    }

    @Test func menuBarTitleHiddenUnlessWorking() {
        #expect(StatusText.menuBarTitle(schedulerOnFirstBreak(), now: at(1205)) == nil)

        var paused = BreakScheduler(settings: defaultSettings, now: t0)
        _ = paused.pause(for: nil, now: at(1))
        #expect(StatusText.menuBarTitle(paused, now: at(2)) == nil)

        var away = BreakScheduler(settings: defaultSettings, now: t0)
        _ = away.beginAway(.systemAsleep, since: at(1), now: at(1))
        #expect(StatusText.menuBarTitle(away, now: at(2)) == nil)
    }

    // MARK: - Other strings

    @Test func statsLine() {
        func line(completed: Int, skipped: Int, postponed: Int = 0) -> String {
            var stats = DailyStats(day: t0)
            stats.completed = completed
            stats.skipped = skipped
            stats.postponed = postponed
            return StatusText.statsLine(stats)
        }
        #expect(line(completed: 0, skipped: 0) == "Today: no breaks yet")
        #expect(line(completed: 0, skipped: 0, postponed: 3) == "Today: no breaks yet")
        #expect(line(completed: 1, skipped: 0) == "Today: 1 break taken")
        #expect(line(completed: 7, skipped: 0, postponed: 2) == "Today: 7 breaks taken")
        #expect(line(completed: 0, skipped: 2) == "Today: 0 breaks taken · 2 skipped")
        #expect(line(completed: 1, skipped: 1) == "Today: 1 break taken · 1 skipped")
    }

    @Test func headsUpText() {
        #expect(StatusText.headsUpText(secondsLeft: 10) == "Eye break in 10 seconds")
        #expect(StatusText.headsUpText(secondsLeft: 2) == "Eye break in 2 seconds")
        #expect(StatusText.headsUpText(secondsLeft: 1) == "Eye break in 1 second")
    }

    @Test func snoozeButtonTitle() {
        #expect(StatusText.snoozeButtonTitle(minutes: 5) == "Snooze 5 min")
        #expect(StatusText.snoozeButtonTitle(minutes: 1) == "Snooze 1 min")
        #expect(StatusText.snoozeButtonTitle(minutes: 30) == "Snooze 30 min")
    }
}

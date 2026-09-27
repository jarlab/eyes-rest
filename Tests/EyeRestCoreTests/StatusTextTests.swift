import Foundation
import Testing
@testable import EyeRestCore

@Suite("StatusText")
struct StatusTextTests {
    private func statusLine(_ s: ReminderScheduler, _ seconds: TimeInterval) -> String {
        StatusText.statusLine(s, now: at(seconds), formatTime: { _ in "unused" })
    }

    // MARK: - Status line

    @Test func countingShowsCountdown() {
        let s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(statusLine(s, 0) == "Next reminder in 20:00")
        #expect(statusLine(s, 0.5) == "Next reminder in 20:00")
        #expect(statusLine(s, 1) == "Next reminder in 19:59")
        #expect(statusLine(s, 78) == "Next reminder in 18:42")
    }

    @Test func countingWithAnHourLongInterval() {
        var settings = defaultSettings
        settings.intervalMinutes = 90
        let s = ReminderScheduler(settings: settings, now: t0)
        #expect(statusLine(s, 0) == "Next reminder in 1:30:00")
    }

    @Test func remindingShowsTimeLeft() {
        let s = schedulerReminding()
        #expect(statusLine(s, 1200) == "Resting — 0:20 left")
        #expect(statusLine(s, 1208) == "Resting — 0:12 left")
        #expect(statusLine(s, 1219.5) == "Resting — 0:01 left")
    }

    @Test func pausedUntilUsesTheInjectedTimeFormatter() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: 3600, now: at(10))
        var formatted: Date?
        let line = StatusText.statusLine(s, now: at(20)) { date in
            formatted = date
            return "3:45 PM"
        }
        #expect(line == "Paused until 3:45 PM")
        #expect(formatted == at(3610))
    }

    @Test func pausedIndefinitely() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.pause(for: nil, now: at(10))
        #expect(statusLine(s, 20) == "Paused")
    }

    @Test func suspendedReadsAsPaused() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = s.suspend(.screenLocked, now: at(10))
        #expect(s.state == .suspended)
        #expect(statusLine(s, 20) == "Paused")
    }

    // MARK: - Menu-bar title

    @Test func menuBarTitleWhileCounting() {
        let s = ReminderScheduler(settings: defaultSettings, now: t0)
        #expect(StatusText.menuBarTitle(s, now: at(0)) == "20m")
        #expect(StatusText.menuBarTitle(s, now: at(119)) == "19m")
        #expect(StatusText.menuBarTitle(s, now: at(1141)) == "59s")
        #expect(StatusText.menuBarTitle(s, now: at(1158)) == "42s")
    }

    @Test func menuBarTitleHiddenWhenTurnedOff() {
        var settings = defaultSettings
        settings.showCountdownInMenuBar = false
        let s = ReminderScheduler(settings: settings, now: t0)
        #expect(StatusText.menuBarTitle(s, now: at(0)) == nil)
    }

    @Test func menuBarTitleFollowsASettingsChange() {
        var s = ReminderScheduler(settings: defaultSettings, now: t0)
        var settings = defaultSettings
        settings.showCountdownInMenuBar = false
        _ = s.updateSettings(settings, now: at(5))
        #expect(StatusText.menuBarTitle(s, now: at(5)) == nil)
        settings.showCountdownInMenuBar = true
        _ = s.updateSettings(settings, now: at(6))
        #expect(StatusText.menuBarTitle(s, now: at(6)) == "20m")
    }

    @Test func menuBarTitleHiddenUnlessCounting() {
        #expect(StatusText.menuBarTitle(schedulerReminding(), now: at(1205)) == nil)

        var paused = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = paused.pause(for: nil, now: at(1))
        #expect(StatusText.menuBarTitle(paused, now: at(2)) == nil)

        var timedPause = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = timedPause.pause(for: 1800, now: at(1))
        #expect(StatusText.menuBarTitle(timedPause, now: at(2)) == nil)

        var suspended = ReminderScheduler(settings: defaultSettings, now: t0)
        _ = suspended.suspend(.systemAsleep, now: at(1))
        #expect(StatusText.menuBarTitle(suspended, now: at(2)) == nil)
    }
}

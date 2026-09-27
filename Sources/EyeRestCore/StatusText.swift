import Foundation

/// User-facing status strings, derived purely from scheduler state so they can be unit-tested.
public enum StatusText {
    /// The first line of the menu, e.g. "Next break in 12:34".
    public static func statusLine(_ scheduler: BreakScheduler, now: Date, formatTime: (Date) -> String) -> String {
        switch scheduler.state {
        case .working where scheduler.isHoldingBreak:
            return "Break on hold while you're on a call"
        case let .working(_, nextBreakAt):
            return "Next break in \(TimeFormatting.countdown(nextBreakAt.timeIntervalSince(now)))"
        case let .onBreak(_, endsAt):
            return "On break — \(TimeFormatting.countdown(endsAt.timeIntervalSince(now))) left"
        case let .paused(until?):
            return "Paused until \(formatTime(until))"
        case .paused(nil):
            return "Paused"
        case .away:
            return "Paused while you're away"
        }
    }

    /// The countdown next to the menu-bar icon, or nil when it should be hidden.
    public static func menuBarTitle(_ scheduler: BreakScheduler, now: Date) -> String? {
        guard scheduler.settings.showCountdownInMenuBar, !scheduler.isHoldingBreak,
              let remaining = scheduler.timeUntilNextBreak(now: now)
        else { return nil }
        return TimeFormatting.menuBarCompact(remaining)
    }

    /// Today's summary, e.g. "Today: 3 breaks taken · 1 skipped". Snoozes are not shown.
    public static func statsLine(_ stats: DailyStats) -> String {
        if stats.completed == 0 && stats.skipped == 0 { return "Today: no breaks yet" }
        var line = "Today: \(stats.completed) \(stats.completed == 1 ? "break" : "breaks") taken"
        if stats.skipped > 0 { line += " · \(stats.skipped) skipped" }
        return line
    }

    public static func headsUpText(secondsLeft: Int) -> String {
        "Eye break in \(secondsLeft) \(secondsLeft == 1 ? "second" : "seconds")"
    }

    public static func snoozeButtonTitle(minutes: Int) -> String {
        "Snooze \(minutes) min"
    }
}

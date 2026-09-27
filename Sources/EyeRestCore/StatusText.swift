import Foundation

/// User-facing status strings, derived purely from scheduler state so they can be unit-tested.
public enum StatusText {
    /// The first line of the menu, e.g. "Next reminder in 18:42". `formatTime` renders the end of a timed pause
    /// (e.g. "3:45 PM") so callers control the locale.
    public static func statusLine(_ scheduler: ReminderScheduler, now: Date, formatTime: (Date) -> String) -> String {
        switch scheduler.state {
        case let .counting(_, nextAt):
            return "Next reminder in \(TimeFormatting.countdown(nextAt.timeIntervalSince(now)))"
        case let .reminding(_, endsAt):
            return "Resting — \(TimeFormatting.countdown(endsAt.timeIntervalSince(now))) left"
        case let .paused(until?):
            return "Paused until \(formatTime(until))"
        case .paused(nil), .suspended:
            return "Paused"
        }
    }

    /// The countdown next to the menu-bar icon ("18m", "42s"), or nil when it should be hidden:
    /// shown only while counting and when the setting is on.
    public static func menuBarTitle(_ scheduler: ReminderScheduler, now: Date) -> String? {
        guard scheduler.settings.showCountdownInMenuBar,
              let remaining = scheduler.timeUntilNextReminder(now: now)
        else { return nil }
        return TimeFormatting.menuBarCompact(remaining)
    }
}

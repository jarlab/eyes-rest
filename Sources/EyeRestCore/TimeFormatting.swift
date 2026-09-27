import Foundation

/// Locale-independent formatting of time spans for the UI.
public enum TimeFormatting {
    /// A clock-style countdown, rounded up to whole seconds: "20:00", "1:05", "0:05", "1:02:05".
    /// Negative and NaN values show "0:00".
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        if hours > 0 { return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))" }
        return "\(minutes):\(twoDigits(secs))"
    }

    /// A short menu-bar label: whole minutes rounded up ("19m") from one minute up, else seconds ("43s").
    /// The value is rounded up to whole seconds first, so 59.5 shows "1m" just like the countdown's "1:00".
    public static func menuBarCompact(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        return total >= 60 ? "\((total + 59) / 60)m" : "\(total)s"
    }

    /// Values beyond this (about 68 years) are capped so the conversion to `Int` can never trap.
    private static let maximumSeconds = TimeInterval(Int32.max)

    /// Whole, non-negative seconds, rounded up; NaN and negative values become 0.
    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds > 0 else { return 0 }
        return Int(min(seconds.rounded(.up), maximumSeconds))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

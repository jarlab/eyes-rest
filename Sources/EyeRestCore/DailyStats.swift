import Foundation

/// Break outcomes counted for a single calendar day.
public struct DailyStats: Codable, Equatable, Sendable {
    /// Start of the day these counts belong to, in the time zone they were recorded in.
    public var day: Date
    /// The local calendar date these counts belong to, as "yyyy-MM-dd". Days are compared by this key rather than
    /// by `day`, whose instant falls on the previous date in any time zone further west. Nil in stats saved before
    /// the key existed.
    public var dayKey: String?
    public var completed: Int = 0
    public var skipped: Int = 0
    public var postponed: Int = 0

    /// Empty stats for `day`, which should be the start of a day in `calendar`.
    public init(day: Date, calendar: Calendar = .current) {
        self.day = day
        dayKey = Self.dayKey(for: day, calendar: calendar)
    }

    /// Counts `outcome`, first starting a fresh day if `date` falls on a different day.
    public mutating func record(_ outcome: BreakOutcome, at date: Date, calendar: Calendar = .current) {
        self = normalized(for: date, calendar: calendar)
        switch outcome {
        case .completed: completed += 1
        case .skipped: skipped += 1
        case .postponed: postponed += 1
        }
    }

    /// These stats if they belong to the local date containing `now`; otherwise empty stats for that date.
    public func normalized(for now: Date, calendar: Calendar = .current) -> DailyStats {
        let today = Self.dayKey(for: now, calendar: calendar)
        if let dayKey {
            return dayKey == today ? self : DailyStats(day: calendar.startOfDay(for: now), calendar: calendar)
        }
        // Saved before `dayKey` existed: fall back to comparing instants, and adopt the key if it is still today.
        guard calendar.isDate(day, inSameDayAs: now) else {
            return DailyStats(day: calendar.startOfDay(for: now), calendar: calendar)
        }
        var stats = self
        stats.dayKey = today
        return stats
    }

    /// The local date of `date` in `calendar`'s time zone, as "yyyy-MM-dd" in the Gregorian calendar.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Persists today's `DailyStats` as JSON in `UserDefaults`.
public final class StatsStore {
    static let key = "stats.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored stats normalized to the day containing `now`; empty stats when missing or unreadable.
    public func load(now: Date, calendar: Calendar = .current) -> DailyStats {
        guard let data = defaults.data(forKey: Self.key),
              let stats = try? JSONDecoder().decode(DailyStats.self, from: data)
        else { return DailyStats(day: calendar.startOfDay(for: now), calendar: calendar) }
        return stats.normalized(for: now, calendar: calendar)
    }

    public func save(_ stats: DailyStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

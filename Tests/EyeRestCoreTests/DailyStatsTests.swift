import Foundation
import Testing
@testable import EyeRestCore

/// A Gregorian calendar in a fixed, non-UTC time zone so day boundaries never depend on the machine.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 5 * 3600 + 1800)!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute, second: second))!
}

/// Empty stats for the start of `day` (March 2026) in the test calendar.
private func emptyStats(_ day: Int) -> DailyStats {
    DailyStats(day: date(day, 0, 0), calendar: calendar)
}

/// A Gregorian calendar in the named region time zone (with its daylight saving rules).
private func regionCalendar(_ identifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
}

private let newYork = regionCalendar("America/New_York")
private let losAngeles = regionCalendar("America/Los_Angeles")

/// The instant of a wall-clock time on 14 or 15 September 2026 in `calendar`.
private func september(_ day: Int, _ hour: Int, in calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
}

/// Three completed breaks recorded in New York on 14 September 2026.
private func threeBreaksInNewYork() -> DailyStats {
    var stats = DailyStats(day: newYork.startOfDay(for: september(14, 9, in: newYork)), calendar: newYork)
    for hour in [9, 10, 11] {
        stats.record(.completed, at: september(14, hour, in: newYork), calendar: newYork)
    }
    return stats
}

@Suite("DailyStats")
struct DailyStatsTests {
    @Test func recordCountsEachOutcome() {
        var stats = DailyStats(day: calendar.startOfDay(for: date(14, 9, 0)), calendar: calendar)
        stats.record(.completed, at: date(14, 9, 0), calendar: calendar)
        stats.record(.completed, at: date(14, 10, 0), calendar: calendar)
        stats.record(.skipped, at: date(14, 11, 0), calendar: calendar)
        stats.record(.postponed, at: date(14, 12, 0), calendar: calendar)
        #expect(stats.day == date(14, 0, 0))
        #expect(stats.dayKey == "2026-03-14")
        #expect(stats.completed == 2)
        #expect(stats.skipped == 1)
        #expect(stats.postponed == 1)
    }

    @Test func recordRollsOverAtMidnight() {
        var stats = emptyStats(14)
        stats.record(.completed, at: date(14, 23, 59, 59), calendar: calendar)
        stats.record(.skipped, at: date(14, 23, 59, 59), calendar: calendar)
        #expect(stats.completed == 1)
        #expect(stats.skipped == 1)

        stats.record(.completed, at: date(15, 0, 0, 1), calendar: calendar)
        var expected = emptyStats(15)
        expected.completed = 1
        #expect(stats == expected)
    }

    @Test func normalizedKeepsTodayAndZeroesAStaleDay() {
        var stats = emptyStats(14)
        stats.completed = 3
        stats.skipped = 2
        stats.postponed = 1
        #expect(stats.normalized(for: date(14, 23, 30), calendar: calendar) == stats)
        #expect(stats.normalized(for: date(17, 8, 0), calendar: calendar) == emptyStats(17))
        #expect(stats.completed == 3)  // normalized(for:) does not mutate
    }

    @Test func midnightDependsOnTheCalendarTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        // 23:00 on the 14th in UTC is already 04:30 on the 15th in UTC+5:30.
        let instant = utc.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 23))!
        let stats = DailyStats(day: utc.startOfDay(for: instant), calendar: utc)
        #expect(stats.normalized(for: instant, calendar: utc) == stats)
        #expect(stats.normalized(for: instant, calendar: calendar) == emptyStats(15))
    }

    /// Midnight in New York is still the previous evening in Los Angeles, but the local date is the same.
    @Test func movingWestOnTheSameDateKeepsTheCounts() {
        var stats = threeBreaksInNewYork()
        let afternoonInLA = september(14, 15, in: losAngeles)
        #expect(stats.normalized(for: afternoonInLA, calendar: losAngeles) == stats)

        stats.record(.completed, at: afternoonInLA, calendar: losAngeles)
        #expect(stats.completed == 4)
    }

    @Test func movingWestStillRollsOverOnTheNextDate() {
        let stats = threeBreaksInNewYork()
        // 01:00 PDT on the 15th: the local date has changed.
        let nextDay = september(15, 1, in: losAngeles)
        let expected = DailyStats(day: losAngeles.startOfDay(for: nextDay), calendar: losAngeles)
        #expect(stats.normalized(for: nextDay, calendar: losAngeles) == expected)
        #expect(expected.dayKey == "2026-09-15")
    }

    @Test func movingEastKeepsTheCountsUntilTheLocalDateChanges() {
        var stats = DailyStats(day: losAngeles.startOfDay(for: september(14, 18, in: losAngeles)), calendar: losAngeles)
        stats.record(.completed, at: september(14, 18, in: losAngeles), calendar: losAngeles)
        // 18:00 PDT is 21:00 EDT on the same date; 01:00 EDT on the 15th is a new date.
        #expect(stats.normalized(for: september(14, 21, in: newYork), calendar: newYork) == stats)
        #expect(stats.normalized(for: september(15, 1, in: newYork), calendar: newYork).completed == 0)
    }

    @Test func statsWithoutADayKeyFallBackToTheDayInstant() {
        var stats = emptyStats(14)
        stats.dayKey = nil
        stats.completed = 2
        let sameDay = stats.normalized(for: date(14, 20, 0), calendar: calendar)
        #expect(sameDay.completed == 2)
        #expect(sameDay.dayKey == "2026-03-14")  // adopted, so later comparisons use the date
        #expect(stats.normalized(for: date(15, 8, 0), calendar: calendar) == emptyStats(15))
    }
}

@Suite("StatsStore")
struct StatsStoreTests {
    @Test func missingValueLoadsEmptyStatsForToday() {
        withTemporaryDefaults { defaults in
            let stats = StatsStore(defaults: defaults).load(now: date(14, 15, 0), calendar: calendar)
            #expect(stats == emptyStats(14))
        }
    }

    @Test func saveThenLoadRoundTripsAndRollsOver() {
        withTemporaryDefaults { defaults in
            var stats = emptyStats(14)
            stats.completed = 4
            stats.skipped = 1
            stats.postponed = 2
            StatsStore(defaults: defaults).save(stats)

            let store = StatsStore(defaults: defaults)
            #expect(store.load(now: date(14, 18, 0), calendar: calendar) == stats)
            #expect(store.load(now: date(15, 7, 0), calendar: calendar) == emptyStats(15))
        }
    }

    @Test func relaunchingFurtherWestOnTheSameDateKeepsTheCounts() {
        withTemporaryDefaults { defaults in
            let stats = threeBreaksInNewYork()
            StatsStore(defaults: defaults).save(stats)
            let loaded = StatsStore(defaults: defaults).load(now: september(14, 15, in: losAngeles), calendar: losAngeles)
            #expect(loaded == stats)
        }
    }

    /// Stats saved before `dayKey` existed still load, so upgrading keeps today's counts.
    @Test func payloadWithoutADayKeyStillLoads() {
        withTemporaryDefaults { defaults in
            let day = date(14, 0, 0).timeIntervalSinceReferenceDate
            let json = "{\"day\":\(day),\"completed\":3,\"skipped\":1,\"postponed\":0}"
            defaults.set(Data(json.utf8), forKey: StatsStore.key)
            let stats = StatsStore(defaults: defaults).load(now: date(14, 15, 0), calendar: calendar)
            var expected = emptyStats(14)
            expected.completed = 3
            expected.skipped = 1
            #expect(stats == expected)
        }
    }

    @Test func corruptDataLoadsEmptyStats() {
        withTemporaryDefaults { defaults in
            defaults.set(Data("{\"day\":".utf8), forKey: StatsStore.key)
            let stats = StatsStore(defaults: defaults).load(now: date(14, 15, 0), calendar: calendar)
            #expect(stats == emptyStats(14))
        }
    }
}

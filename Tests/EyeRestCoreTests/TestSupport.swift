import Foundation
@testable import EyeRestCore

/// Fixed reference instant so every test is deterministic.
let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// The instant `seconds` after `t0`.
func at(_ seconds: TimeInterval) -> Date { t0 + seconds }

/// 20 min interval, 20 s reminder.
let defaultSettings = EyeRestSettings.default

/// Ticks at 1 Hz from `from` through `to` (inclusive), returning every event.
func run(_ scheduler: inout ReminderScheduler, from: TimeInterval, through to: TimeInterval) -> [ReminderEvent] {
    var events: [ReminderEvent] = []
    var t = from
    while t <= to {
        events += scheduler.tick(now: at(t))
        t += 1
    }
    return events
}

/// Ticks at 1 Hz from `lastSeen + 1` up to, but excluding, `to`, so the scheduler never sees a gap.
func advance(_ scheduler: inout ReminderScheduler, to: TimeInterval) -> [ReminderEvent] {
    let next = scheduler.lastSeen.timeIntervalSince(t0) + 1
    guard next < to else { return [] }
    return run(&scheduler, from: next, through: to - 1)
}

/// A scheduler whose first reminder has just appeared at the end of the first interval
/// (at 1200 with default settings, closing itself at 1220).
func schedulerReminding(settings: EyeRestSettings = defaultSettings) -> ReminderScheduler {
    var scheduler = ReminderScheduler(settings: settings, now: t0)
    let due = scheduler.settings.interval
    _ = advance(&scheduler, to: due)
    _ = scheduler.tick(now: at(due))
    return scheduler
}

/// Runs `body` with an isolated, empty `UserDefaults` suite that is deleted afterwards.
///
/// The suite is named by an absolute path in a fresh temporary directory, so its plist lives there instead of
/// in ~/Library/Preferences, where cfprefsd would leave an empty file behind for every run.
func withTemporaryDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("EyeRestCoreTests.\(UUID().uuidString)", isDirectory: true)
    let suiteName = directory.appendingPathComponent("defaults").path
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
    try body(defaults)
}

import Foundation

/// User preferences. Every numeric field is kept inside its documented range: `clamped()` enforces it,
/// and decoding clamps automatically.
public struct EyeRestSettings: Codable, Equatable, Sendable {
    /// Minutes between reminders (1...120).
    public var intervalMinutes: Int = 20
    /// How long the reminder card stays up, in seconds (5...120).
    public var reminderSeconds: Int = 20
    /// Play a gentle sound when the reminder card appears.
    public var playSound: Bool = true
    /// Show the time until the next reminder next to the menu-bar icon.
    public var showCountdownInMenuBar: Bool = true

    public init() {}

    public static let `default` = EyeRestSettings()

    public static let intervalRange: ClosedRange<Int> = 1...120
    public static let reminderRange: ClosedRange<Int> = 5...120

    /// Reminder lengths offered in Settings, in seconds.
    public static let reminderPresets: [Int] = [10, 20, 30, 45, 60]

    /// The time between reminders.
    public var interval: TimeInterval { TimeInterval(intervalMinutes) * 60 }
    /// How long a reminder card stays up.
    public var reminderDuration: TimeInterval { TimeInterval(reminderSeconds) }

    /// A copy with every numeric field forced into its range.
    public func clamped() -> EyeRestSettings {
        var settings = self
        settings.intervalMinutes = intervalMinutes.clamped(to: Self.intervalRange)
        settings.reminderSeconds = reminderSeconds.clamped(to: Self.reminderRange)
        return settings
    }

    /// Lenient decoding so settings survive app upgrades and downgrades: a missing or mistyped key falls back
    /// to its default, unknown keys are ignored, and the result is clamped.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func decode<T: Decodable>(_ key: CodingKeys, default fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let defaults = Self.default
        intervalMinutes = decode(.intervalMinutes, default: defaults.intervalMinutes)
        reminderSeconds = decode(.reminderSeconds, default: defaults.reminderSeconds)
        playSound = decode(.playSound, default: defaults.playSound)
        showCountdownInMenuBar = decode(.showCountdownInMenuBar, default: defaults.showCountdownInMenuBar)
        self = clamped()
    }
}

/// Persists `EyeRestSettings` as JSON in `UserDefaults`.
public final class SettingsStore {
    static let key = "settings.v2"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored settings, or `.default` when nothing is stored or the stored value cannot be decoded.
    public func load() -> EyeRestSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(EyeRestSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: EyeRestSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

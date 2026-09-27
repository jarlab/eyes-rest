import Foundation

/// User preferences. Every numeric field is kept inside its documented range: `clamped()` enforces it,
/// and decoding clamps automatically.
public struct EyeRestSettings: Codable, Equatable, Sendable {
    /// Minutes of work between breaks (1...120).
    public var workIntervalMinutes: Int = 20
    /// Length of a break in seconds (10...300).
    public var breakDurationSeconds: Int = 20
    /// Snooze length in minutes (1...30). "Snooze" is the user-facing name for postponing.
    public var postponeMinutes: Int = 5
    /// Minutes without input after which the user counts as away (1...30).
    public var idleThresholdMinutes: Int = 5
    public var allowSkip: Bool = true
    public var allowPostpone: Bool = true
    /// Show the heads-up pill 10 seconds before a break.
    public var showHeadsUp: Bool = true
    /// Hold a due break while the camera or microphone is in use.
    public var holdDuringCalls: Bool = true
    public var pauseWhenIdle: Bool = true
    /// Play a chime when a break completes.
    public var playSounds: Bool = true
    public var showCountdownInMenuBar: Bool = true

    public init() {}

    public static let `default` = EyeRestSettings()

    public static let workIntervalRange: ClosedRange<Int> = 1...120
    public static let breakDurationRange: ClosedRange<Int> = 10...300
    public static let postponeRange: ClosedRange<Int> = 1...30
    public static let idleThresholdRange: ClosedRange<Int> = 1...30

    /// Break lengths offered in Settings, in seconds.
    public static let breakDurationPresets: [Int] = [10, 20, 30, 45, 60, 120, 180, 300]
    /// Snooze lengths offered in Settings, in minutes.
    public static let postponePresets: [Int] = [1, 2, 5, 10, 15, 30]
    /// "Away after" values offered in Settings, in minutes.
    public static let idleThresholdPresets: [Int] = [2, 3, 5, 10, 15, 30]

    public var workInterval: TimeInterval { TimeInterval(workIntervalMinutes) * 60 }
    public var breakDuration: TimeInterval { TimeInterval(breakDurationSeconds) }
    public var postponeDuration: TimeInterval { TimeInterval(postponeMinutes) * 60 }
    public var idleThreshold: TimeInterval { TimeInterval(idleThresholdMinutes) * 60 }

    /// A copy with every numeric field forced into its range.
    public func clamped() -> EyeRestSettings {
        var settings = self
        settings.workIntervalMinutes = workIntervalMinutes.clamped(to: Self.workIntervalRange)
        settings.breakDurationSeconds = breakDurationSeconds.clamped(to: Self.breakDurationRange)
        settings.postponeMinutes = postponeMinutes.clamped(to: Self.postponeRange)
        settings.idleThresholdMinutes = idleThresholdMinutes.clamped(to: Self.idleThresholdRange)
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
        workIntervalMinutes = decode(.workIntervalMinutes, default: defaults.workIntervalMinutes)
        breakDurationSeconds = decode(.breakDurationSeconds, default: defaults.breakDurationSeconds)
        postponeMinutes = decode(.postponeMinutes, default: defaults.postponeMinutes)
        idleThresholdMinutes = decode(.idleThresholdMinutes, default: defaults.idleThresholdMinutes)
        allowSkip = decode(.allowSkip, default: defaults.allowSkip)
        allowPostpone = decode(.allowPostpone, default: defaults.allowPostpone)
        showHeadsUp = decode(.showHeadsUp, default: defaults.showHeadsUp)
        holdDuringCalls = decode(.holdDuringCalls, default: defaults.holdDuringCalls)
        pauseWhenIdle = decode(.pauseWhenIdle, default: defaults.pauseWhenIdle)
        playSounds = decode(.playSounds, default: defaults.playSounds)
        showCountdownInMenuBar = decode(.showCountdownInMenuBar, default: defaults.showCountdownInMenuBar)
        self = clamped()
    }
}

/// Persists `EyeRestSettings` as JSON in `UserDefaults`.
public final class SettingsStore {
    static let key = "settings.v1"

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

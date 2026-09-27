import Foundation

/// Turns raw input idle time into idle time as the break scheduler should see it.
///
/// While an app keeps the display awake (video players and call apps hold a display-sleep assertion), the user
/// counts as present even without any input: someone watching a video or listening to a call is not away. Once
/// the app lets go, idle time counts from that moment instead of from the last input, so the stretch spent watching
/// is never mistaken for time away (which would count it as a break and restart the cycle).
public struct EffectiveIdle: Sendable {
    /// The assertion is only checked once the user has gone this long without input; while they are typing or
    /// pointing, raw idle is already tiny.
    public static let assertionCheckThreshold: TimeInterval = 2

    /// When an app was last seen keeping the display awake, on the monotonic clock passed to `update`.
    private var lastPreventedAt: TimeInterval?

    public init() {}

    /// The effective idle seconds, given `rawIdle` (seconds since the last input) at `now`, a reading of a monotonic
    /// clock in seconds. `displaySleepPrevented` is only evaluated when the user has not just given input.
    public mutating func update(
        rawIdle: TimeInterval, displaySleepPrevented: @autoclosure () -> Bool, now: TimeInterval
    ) -> TimeInterval {
        let raw = rawIdle.isFinite ? max(0, rawIdle) : 0
        guard raw >= Self.assertionCheckThreshold else { return raw }
        if displaySleepPrevented() {
            lastPreventedAt = now
            return 0
        }
        guard let lastPreventedAt else { return raw }
        return min(raw, max(0, now - lastPreventedAt))
    }
}

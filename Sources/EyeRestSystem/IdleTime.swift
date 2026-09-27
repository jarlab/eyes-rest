import CoreGraphics
import EyeRestCore
import Foundation
import IOKit.pwr_mgt

/// How long the user has been away from the keyboard and mouse. Needs no permission.
public enum IdleTime {
    /// `kCGAnyInputEventType`, which Swift cannot see: every HID event type.
    private static let anyInputEventType = CGEventType(rawValue: ~0)!

    /// Seconds since the last keyboard, mouse or trackpad event in this login session (never negative or NaN).
    public static func seconds() -> TimeInterval {
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    /// True while some app holds a `PreventUserIdleDisplaySleep` power assertion, as video players and call apps do.
    ///
    /// `InternalPreventDisplaySleep` is deliberately ignored: it reads 1 whenever the user is active.
    public static func isDisplaySleepPreventedByApp() -> Bool {
        var status: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsStatus(&status)
        guard let assertions = status?.takeRetainedValue() as? [String: Any], result == kIOReturnSuccess else {
            return false
        }
        return (assertions[kIOPMAssertPreventUserIdleDisplaySleep] as? Int ?? 0) > 0
    }

    /// Seconds on a clock that keeps counting while the Mac sleeps and ignores changes to the wall clock.
    public static func monotonicSeconds() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

/// Idle time as the break scheduler should see it: `IdleTime.seconds()`, adjusted by `EffectiveIdle` so that an app
/// keeping the display awake (someone watching a video or in a call) counts as the user being present, and idle time
/// starts counting only when that app lets go.
@MainActor
public final class EffectiveIdleTime {
    private var state = EffectiveIdle()

    public init() {}

    /// The current effective idle seconds. Call it at least once a second so the end of a video or call is noticed.
    public func seconds() -> TimeInterval {
        state.update(
            rawIdle: IdleTime.seconds(),
            displaySleepPrevented: IdleTime.isDisplaySleepPreventedByApp(),
            now: IdleTime.monotonicSeconds()
        )
    }
}

import Foundation
import Testing
@testable import EyeRestCore

@Suite("TimeFormatting")
struct TimeFormattingTests {
    @Test(arguments: [
        (1199.2, "20:00"), (65, "1:05"), (5, "0:05"), (3725, "1:02:05"),
        (0, "0:00"), (0.01, "0:01"), (59.001, "1:00"), (600, "10:00"), (3600, "1:00:00"), (36_000, "10:00:00"),
        (360_000, "100:00:00"), (-5, "0:00"), (-.infinity, "0:00"), (.nan, "0:00"),
    ] as [(TimeInterval, String)])
    func countdown(seconds: TimeInterval, expected: String) {
        #expect(TimeFormatting.countdown(seconds) == expected)
    }

    @Test(arguments: [
        (20, "20 sec"), (60, "1 min"), (90, "1 min 30 sec"), (300, "5 min"), (3600, "1 hr"), (5400, "1 hr 30 min"),
        (0, "0 sec"), (45, "45 sec"), (120, "2 min"), (1800, "30 min"), (7200, "2 hr"), (3661, "1 hr 1 min 1 sec"),
        (19.6, "20 sec"), (0.4, "0 sec"), (-10, "0 sec"), (.nan, "0 sec"), (360_000, "100 hr"),
    ] as [(TimeInterval, String)])
    func duration(seconds: TimeInterval, expected: String) {
        #expect(TimeFormatting.duration(seconds) == expected)
    }

    @Test(arguments: [
        (1081, "19m"), (60, "1m"), (61, "2m"), (42.3, "43s"), (0, "0s"),
        (1200, "20m"), (59, "59s"), (59.5, "1m"), (0.2, "1s"), (7200, "120m"), (-3, "0s"), (.nan, "0s"),
    ] as [(TimeInterval, String)])
    func menuBarCompact(seconds: TimeInterval, expected: String) {
        #expect(TimeFormatting.menuBarCompact(seconds) == expected)
    }

    @Test func hugeValuesAreCappedInsteadOfTrapping() {
        let cap = "596523:14:07"  // Int32.max seconds
        #expect(TimeFormatting.countdown(.infinity) == cap)
        #expect(TimeFormatting.countdown(.greatestFiniteMagnitude) == cap)
        #expect(TimeFormatting.countdown(1e300) == cap)
        #expect(TimeFormatting.duration(.infinity) == "596523 hr 14 min 7 sec")
        #expect(TimeFormatting.menuBarCompact(.infinity) == "35791395m")
    }
}

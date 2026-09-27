import Foundation
import Testing
@testable import EyeRestCore

@Suite("EyeRestSettings")
struct SettingsTests {
    private func decode(_ json: String) throws -> EyeRestSettings {
        try JSONDecoder().decode(EyeRestSettings.self, from: Data(json.utf8))
    }

    @Test func defaults() {
        let s = EyeRestSettings.default
        #expect(s == EyeRestSettings())
        #expect(s.workIntervalMinutes == 20)
        #expect(s.breakDurationSeconds == 20)
        #expect(s.postponeMinutes == 5)
        #expect(s.idleThresholdMinutes == 5)
        #expect(s.allowSkip && s.allowPostpone && s.showHeadsUp && s.holdDuringCalls)
        #expect(s.pauseWhenIdle && s.playSounds && s.showCountdownInMenuBar)
        #expect(s.workInterval == 1200)
        #expect(s.breakDuration == 20)
        #expect(s.postponeDuration == 300)
        #expect(s.idleThreshold == 300)
    }

    @Test func rangesAndPresets() {
        #expect(EyeRestSettings.workIntervalRange == 1...120)
        #expect(EyeRestSettings.breakDurationRange == 10...300)
        #expect(EyeRestSettings.postponeRange == 1...30)
        #expect(EyeRestSettings.idleThresholdRange == 1...30)
        #expect(EyeRestSettings.breakDurationPresets == [10, 20, 30, 45, 60, 120, 180, 300])
        #expect(EyeRestSettings.postponePresets == [1, 2, 5, 10, 15, 30])
        #expect(EyeRestSettings.idleThresholdPresets == [2, 3, 5, 10, 15, 30])
        #expect(EyeRestSettings.breakDurationPresets.allSatisfy(EyeRestSettings.breakDurationRange.contains))
        #expect(EyeRestSettings.postponePresets.allSatisfy(EyeRestSettings.postponeRange.contains))
        #expect(EyeRestSettings.idleThresholdPresets.allSatisfy(EyeRestSettings.idleThresholdRange.contains))
    }

    @Test func clampedForcesValuesIntoRange() {
        var low = EyeRestSettings()
        low.workIntervalMinutes = 0
        low.breakDurationSeconds = 5
        low.postponeMinutes = -1
        low.idleThresholdMinutes = 0
        let clampedLow = low.clamped()
        #expect(clampedLow.workIntervalMinutes == 1)
        #expect(clampedLow.breakDurationSeconds == 10)
        #expect(clampedLow.postponeMinutes == 1)
        #expect(clampedLow.idleThresholdMinutes == 1)

        var high = EyeRestSettings()
        high.workIntervalMinutes = 121
        high.breakDurationSeconds = 301
        high.postponeMinutes = 31
        high.idleThresholdMinutes = Int.max
        high.playSounds = false
        let clampedHigh = high.clamped()
        #expect(clampedHigh.workIntervalMinutes == 120)
        #expect(clampedHigh.breakDurationSeconds == 300)
        #expect(clampedHigh.postponeMinutes == 30)
        #expect(clampedHigh.idleThresholdMinutes == 30)
        #expect(clampedHigh.playSounds == false)  // non-numeric fields untouched

        #expect(EyeRestSettings.default.clamped() == .default)
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        #expect(try decode("{}") == .default)
    }

    @Test func unknownKeysAreIgnored() throws {
        let s = try decode(#"{"reminderStyle":"overlay","workIntervalMinutes":25,"playSounds":false}"#)
        var expected = EyeRestSettings.default
        expected.workIntervalMinutes = 25
        expected.playSounds = false
        #expect(s == expected)
    }

    @Test func outOfRangeValuesAreClampedOnDecode() throws {
        let low = try decode(
            #"{"workIntervalMinutes":0,"breakDurationSeconds":5,"postponeMinutes":0,"idleThresholdMinutes":-3}"#)
        #expect(low.workIntervalMinutes == 1)
        #expect(low.breakDurationSeconds == 10)
        #expect(low.postponeMinutes == 1)
        #expect(low.idleThresholdMinutes == 1)

        let high = try decode(
            #"{"workIntervalMinutes":500,"breakDurationSeconds":1000,"postponeMinutes":99,"idleThresholdMinutes":45}"#)
        #expect(high.workIntervalMinutes == 120)
        #expect(high.breakDurationSeconds == 300)
        #expect(high.postponeMinutes == 30)
        #expect(high.idleThresholdMinutes == 30)
    }

    @Test func mistypedValueFallsBackToItsDefaultOnly() throws {
        let s = try decode(#"{"workIntervalMinutes":"soon","breakDurationSeconds":45,"allowSkip":"no"}"#)
        #expect(s.workIntervalMinutes == 20)
        #expect(s.breakDurationSeconds == 45)
        #expect(s.allowSkip == true)
    }

    @Test func nonObjectJSONFailsToDecode() {
        #expect(throws: DecodingError.self) { try decode("[1, 2, 3]") }
    }

    @Test func encodeDecodeRoundTrip() throws {
        var s = EyeRestSettings()
        s.workIntervalMinutes = 45
        s.breakDurationSeconds = 120
        s.postponeMinutes = 15
        s.idleThresholdMinutes = 10
        s.allowSkip = false
        s.allowPostpone = false
        s.showHeadsUp = false
        s.holdDuringCalls = false
        s.pauseWhenIdle = false
        s.playSounds = false
        s.showCountdownInMenuBar = false
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(EyeRestSettings.self, from: data) == s)
    }
}

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test func missingValueLoadsDefaults() {
        withTemporaryDefaults { defaults in
            #expect(SettingsStore(defaults: defaults).load() == .default)
        }
    }

    @Test func saveThenLoadRoundTrips() {
        withTemporaryDefaults { defaults in
            var s = EyeRestSettings()
            s.workIntervalMinutes = 30
            s.breakDurationSeconds = 60
            s.holdDuringCalls = false
            SettingsStore(defaults: defaults).save(s)
            #expect(SettingsStore(defaults: defaults).load() == s)
            #expect(defaults.data(forKey: SettingsStore.key) != nil)
        }
    }

    @Test func corruptDataLoadsDefaults() {
        withTemporaryDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: SettingsStore.key)
            #expect(SettingsStore(defaults: defaults).load() == .default)
            defaults.set("a string, not data", forKey: SettingsStore.key)
            #expect(SettingsStore(defaults: defaults).load() == .default)
        }
    }
}

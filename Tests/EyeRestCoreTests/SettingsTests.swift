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
        #expect(s.intervalMinutes == 20)
        #expect(s.reminderSeconds == 20)
        #expect(s.playSound)
        #expect(s.showCountdownInMenuBar)
        #expect(s.interval == 1200)
        #expect(s.reminderDuration == 20)
    }

    @Test func rangesAndPresets() {
        #expect(EyeRestSettings.intervalRange == 1...120)
        #expect(EyeRestSettings.reminderRange == 5...120)
        #expect(EyeRestSettings.reminderPresets == [10, 20, 30, 45, 60])
        #expect(EyeRestSettings.reminderPresets.allSatisfy(EyeRestSettings.reminderRange.contains))
        #expect(EyeRestSettings.intervalRange.contains(EyeRestSettings.default.intervalMinutes))
        #expect(EyeRestSettings.reminderPresets.contains(EyeRestSettings.default.reminderSeconds))
    }

    @Test func derivedDurations() {
        var s = EyeRestSettings()
        s.intervalMinutes = 1
        s.reminderSeconds = 5
        #expect(s.interval == 60)
        #expect(s.reminderDuration == 5)
        s.intervalMinutes = 120
        s.reminderSeconds = 120
        #expect(s.interval == 7200)
        #expect(s.reminderDuration == 120)
    }

    @Test func clampedForcesValuesIntoRange() {
        var low = EyeRestSettings()
        low.intervalMinutes = 0
        low.reminderSeconds = 4
        let clampedLow = low.clamped()
        #expect(clampedLow.intervalMinutes == 1)
        #expect(clampedLow.reminderSeconds == 5)

        var negative = EyeRestSettings()
        negative.intervalMinutes = Int.min
        negative.reminderSeconds = -20
        #expect(negative.clamped().intervalMinutes == 1)
        #expect(negative.clamped().reminderSeconds == 5)

        var high = EyeRestSettings()
        high.intervalMinutes = 121
        high.reminderSeconds = Int.max
        high.playSound = false
        high.showCountdownInMenuBar = false
        let clampedHigh = high.clamped()
        #expect(clampedHigh.intervalMinutes == 120)
        #expect(clampedHigh.reminderSeconds == 120)
        #expect(clampedHigh.playSound == false)  // non-numeric fields untouched
        #expect(clampedHigh.showCountdownInMenuBar == false)

        #expect(EyeRestSettings.default.clamped() == .default)
    }

    @Test func boundaryValuesAreKept() {
        var s = EyeRestSettings()
        s.intervalMinutes = 1
        s.reminderSeconds = 120
        #expect(s.clamped() == s)
        s.intervalMinutes = 120
        s.reminderSeconds = 5
        #expect(s.clamped() == s)
        s.reminderSeconds = 37  // a non-preset value inside the range survives
        #expect(s.clamped().reminderSeconds == 37)
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        #expect(try decode("{}") == .default)
    }

    @Test func unknownKeysAreIgnored() throws {
        // Includes keys from the previous, fuller app, which must not break decoding.
        let s = try decode(
            #"{"allowSkip":false,"holdDuringCalls":true,"workIntervalMinutes":45,"intervalMinutes":25,"playSound":false}"#)
        var expected = EyeRestSettings.default
        expected.intervalMinutes = 25
        expected.playSound = false
        #expect(s == expected)
    }

    @Test func outOfRangeValuesAreClampedOnDecode() throws {
        let low = try decode(#"{"intervalMinutes":0,"reminderSeconds":1}"#)
        #expect(low.intervalMinutes == 1)
        #expect(low.reminderSeconds == 5)

        let high = try decode(#"{"intervalMinutes":500,"reminderSeconds":1000}"#)
        #expect(high.intervalMinutes == 120)
        #expect(high.reminderSeconds == 120)
    }

    @Test func mistypedValueFallsBackToItsDefaultOnly() throws {
        let s = try decode(
            #"{"intervalMinutes":"soon","reminderSeconds":45,"playSound":"no","showCountdownInMenuBar":false}"#)
        #expect(s.intervalMinutes == 20)
        #expect(s.reminderSeconds == 45)
        #expect(s.playSound == true)
        #expect(s.showCountdownInMenuBar == false)
    }

    @Test func nullValueFallsBackToItsDefault() throws {
        let s = try decode(#"{"intervalMinutes":null,"reminderSeconds":30}"#)
        #expect(s.intervalMinutes == 20)
        #expect(s.reminderSeconds == 30)
    }

    @Test func nonObjectJSONFailsToDecode() {
        #expect(throws: DecodingError.self) { try decode("[1, 2, 3]") }
    }

    @Test func encodeDecodeRoundTrip() throws {
        var s = EyeRestSettings()
        s.intervalMinutes = 45
        s.reminderSeconds = 60
        s.playSound = false
        s.showCountdownInMenuBar = false
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(EyeRestSettings.self, from: data) == s)
    }

    @Test func encodesExactlyTheFourKeys() throws {
        let data = try JSONEncoder().encode(EyeRestSettings.default)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["intervalMinutes", "reminderSeconds", "playSound", "showCountdownInMenuBar"])
    }
}

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test func usesTheV2Key() {
        #expect(SettingsStore.key == "settings.v2")
    }

    @Test func missingValueLoadsDefaults() {
        withTemporaryDefaults { defaults in
            #expect(SettingsStore(defaults: defaults).load() == .default)
        }
    }

    @Test func saveThenLoadRoundTrips() {
        withTemporaryDefaults { defaults in
            var s = EyeRestSettings()
            s.intervalMinutes = 30
            s.reminderSeconds = 45
            s.playSound = false
            SettingsStore(defaults: defaults).save(s)
            #expect(SettingsStore(defaults: defaults).load() == s)
            #expect(defaults.data(forKey: SettingsStore.key) != nil)
        }
    }

    @Test func storedOutOfRangeValuesLoadClamped() {
        withTemporaryDefaults { defaults in
            defaults.set(Data(#"{"intervalMinutes":999,"reminderSeconds":0}"#.utf8), forKey: SettingsStore.key)
            let s = SettingsStore(defaults: defaults).load()
            #expect(s.intervalMinutes == 120)
            #expect(s.reminderSeconds == 5)
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

    @Test func oldV1ValueIsNotRead() {
        withTemporaryDefaults { defaults in
            defaults.set(Data(#"{"intervalMinutes":45}"#.utf8), forKey: "settings.v1")
            #expect(SettingsStore(defaults: defaults).load() == .default)
        }
    }
}

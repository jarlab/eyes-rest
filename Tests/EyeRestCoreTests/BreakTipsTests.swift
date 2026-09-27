import Testing
@testable import EyeRestCore

@Suite("BreakTips")
struct BreakTipsTests {
    @Test func containsTheTenTipsInOrder() {
        #expect(BreakTips.all.count == 10)
        #expect(BreakTips.all.first == "Blink slowly a few times — we blink less when looking at screens.")
        #expect(BreakTips.all.last == "Check your posture: feet flat, back supported.")
        #expect(Set(BreakTips.all).count == BreakTips.all.count)
    }

    @Test func tipIndexWrapsAround() {
        #expect(BreakTips.tip(for: 0) == BreakTips.all[0])
        #expect(BreakTips.tip(for: 9) == BreakTips.all[9])
        #expect(BreakTips.tip(for: 10) == BreakTips.all[0])
        #expect(BreakTips.tip(for: 23) == BreakTips.all[3])
    }

    @Test func negativeAndExtremeIndicesAreSafe() {
        #expect(BreakTips.tip(for: -1) == BreakTips.all[9])
        #expect(BreakTips.tip(for: -10) == BreakTips.all[0])
        #expect(BreakTips.tip(for: -11) == BreakTips.all[9])
        #expect(BreakTips.tip(for: Int.min) == BreakTips.all[2])
        #expect(BreakTips.tip(for: Int.max) == BreakTips.all[7])
    }
}

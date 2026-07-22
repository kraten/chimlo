import Testing
@testable import ChimloCore

@Suite("System feedback")
struct SystemFeedbackTests {
    @Test("System feedback remains visible long enough to read")
    func holdsForTwoSeconds() {
        #expect(SystemFeedbackPolicy.holdMilliseconds >= 2_000)
    }

    @Test("Values are normalized for display and accessibility")
    func presentationNormalizesValues() {
        let loud = SystemFeedbackPresentation(kind: .outputVolume, value: 1.4)
        let dark = SystemFeedbackPresentation(kind: .displayBrightness, value: -0.2)
        let muted = SystemFeedbackPresentation(kind: .outputVolume, value: 0.7, isMuted: true)

        #expect(loud.value == 1)
        #expect(loud.percentage == 100)
        #expect(loud.accessibilityDescription == "Output volume 100 percent")
        #expect(dark.value == 0)
        #expect(dark.accessibilityDescription == "Display brightness 0 percent")
        #expect(muted.accessibilityDescription == "Output volume muted")
    }

    @Test("Coarse and fine adjustments match native keyboard increments")
    func adjustmentSteps() {
        #expect(SystemFeedbackPolicy.adjustedValue(from: 0.5, direction: 1, fine: false) == 0.5625)
        #expect(SystemFeedbackPolicy.adjustedValue(from: 0.5, direction: -1, fine: true) == 0.484375)
        #expect(SystemFeedbackPolicy.adjustedValue(from: 0.99, direction: 1, fine: false) == 1)
        #expect(SystemFeedbackPolicy.adjustedValue(from: 0.01, direction: -1, fine: false) == 0)
    }

    @Test("The pixel meter reaches the exact endpoints")
    func meterEndpoints() {
        #expect(SystemFeedbackPolicy.meterFillWidth(for: 0, trackWidth: 23) == 0)
        #expect(SystemFeedbackPolicy.meterFillWidth(for: 0.5, trackWidth: 23) == 11.5)
        #expect(SystemFeedbackPolicy.meterFillWidth(for: 1, trackWidth: 23) == 23)
    }
}

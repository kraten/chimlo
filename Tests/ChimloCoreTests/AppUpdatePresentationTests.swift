import ChimloCore
import Testing

@Suite("App update presentation")
struct AppUpdatePresentationTests {
    @Test("Available updates use the requested notification copy")
    func availableCopy() {
        let presentation = AppUpdatePresentation(phase: .available)

        #expect(presentation.title == "Update to latest version")
        #expect(presentation.isActionable)
    }

    @Test("Download progress is clamped for the pixel meter")
    func progressClamping() {
        #expect(AppUpdatePresentation(phase: .downloading(progress: -0.2)).normalizedProgress == 0)
        #expect(AppUpdatePresentation(phase: .downloading(progress: 0.42)).normalizedProgress == 0.42)
        #expect(AppUpdatePresentation(phase: .downloading(progress: 1.4)).normalizedProgress == 1)
        #expect(AppUpdatePresentation(phase: .downloading(progress: nil)).normalizedProgress == nil)
    }

    @Test("Owner interactions and onboarding outrank update reminders")
    func priority() {
        let presentation = AppUpdatePresentation(phase: .available)

        #expect(AppUpdatePresentationPolicy.shouldTakeIdlePanel(
            presentation: presentation,
            hasOwnerInteraction: false,
            isOnboarding: false
        ))
        #expect(!AppUpdatePresentationPolicy.shouldTakeIdlePanel(
            presentation: presentation,
            hasOwnerInteraction: true,
            isOnboarding: false
        ))
        #expect(!AppUpdatePresentationPolicy.shouldTakeIdlePanel(
            presentation: presentation,
            hasOwnerInteraction: false,
            isOnboarding: true
        ))
    }
}

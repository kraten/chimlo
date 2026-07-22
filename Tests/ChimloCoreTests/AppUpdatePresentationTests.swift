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

    @Test("Completed checks retain a visible up-to-date result")
    func completedCheckFeedback() {
        let presentation = AppUpdatePresentation(phase: .upToDate)

        #expect(presentation.title == "Chimlo is up to date")
        #expect(presentation.actionTitle == "Check Again")
        #expect(presentation.isActionable)
        #expect(!AppUpdatePresentationPolicy.shouldTakeIdlePanel(
            presentation: presentation,
            hasOwnerInteraction: false,
            isOnboarding: false
        ))
    }

    @Test("Settings feedback covers active, available, and failed checks")
    func settingsFeedback() {
        let checking = AppUpdatePresentation(phase: .checking)
        let available = AppUpdatePresentation(phase: .available)
        let downloading = AppUpdatePresentation(phase: .downloading(progress: 0.42))
        let failed = AppUpdatePresentation(phase: .failed)

        #expect(checking.statusText == "Checking for updates…")
        #expect(checking.actionTitle == "Checking…")
        #expect(checking.isBusy)
        #expect(!checking.isActionable)

        #expect(available.statusText == "Update available")
        #expect(available.actionTitle == "Update to latest version")
        #expect(available.isActionable)

        #expect(downloading.statusText == "Downloading update: 42%")
        #expect(downloading.isBusy)
        #expect(!downloading.isActionable)

        #expect(failed.statusText == "Couldn’t check for updates")
        #expect(failed.actionTitle == "Try Again")
        #expect(failed.isActionable)
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

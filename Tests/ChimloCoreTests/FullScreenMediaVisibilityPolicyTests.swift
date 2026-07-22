import ChimloCore
import Foundation
import Testing

@Suite("Full-screen media visibility")
struct FullScreenMediaVisibilityPolicyTests {
    @Test("System feedback temporarily replaces full-screen suppression")
    func showsOnlySystemFeedbackDuringFullScreenMedia() {
        #expect(FullScreenMediaPresentationPolicy.mode(
            fullScreenMediaIsActive: true,
            hasSystemFeedback: true
        ) == .systemFeedbackOnly)
    }

    @Test("Full-screen media stays hidden when feedback expires")
    func hidesAgainAfterSystemFeedbackExpires() {
        #expect(FullScreenMediaPresentationPolicy.mode(
            fullScreenMediaIsActive: true,
            hasSystemFeedback: false
        ) == .hidden)
    }

    @Test("System feedback does not alter ordinary Chimlo presentation")
    func keepsNormalPresentationOutsideFullScreenMedia() {
        #expect(FullScreenMediaPresentationPolicy.mode(
            fullScreenMediaIsActive: false,
            hasSystemFeedback: true
        ) == .normal)
    }

    @Test("Playing media hides Chimlo when its app owns the full-screen window")
    func hidesForMatchingFullScreenMediaApp() {
        #expect(FullScreenMediaVisibilityPolicy.shouldHideIsland(
            mediaIsPlaying: true,
            mediaBundleIdentifier: "com.apple.Safari",
            mediaApplicationName: "Safari",
            windowOwnerBundleIdentifier: "com.apple.Safari",
            windowOwnerApplicationName: "Safari",
            windowOwnerHasFullScreenWindow: true
        ))
    }

    @Test("Paused media restores Chimlo even when the media app remains full screen")
    func restoresWhenPlaybackPauses() {
        #expect(!FullScreenMediaVisibilityPolicy.shouldHideIsland(
            mediaIsPlaying: false,
            mediaBundleIdentifier: "com.apple.Safari",
            mediaApplicationName: "Safari",
            windowOwnerBundleIdentifier: "com.apple.Safari",
            windowOwnerApplicationName: "Safari",
            windowOwnerHasFullScreenWindow: true
        ))
    }

    @Test("Leaving full screen restores Chimlo while playback continues")
    func restoresWhenFullScreenEnds() {
        #expect(!FullScreenMediaVisibilityPolicy.shouldHideIsland(
            mediaIsPlaying: true,
            mediaBundleIdentifier: "com.apple.Safari",
            mediaApplicationName: "Safari",
            windowOwnerBundleIdentifier: "com.apple.Safari",
            windowOwnerApplicationName: "Safari",
            windowOwnerHasFullScreenWindow: false
        ))
    }

    @Test("Background media does not hide Chimlo for an unrelated full-screen app")
    func staysVisibleForUnrelatedFullScreenApp() {
        #expect(!FullScreenMediaVisibilityPolicy.shouldHideIsland(
            mediaIsPlaying: true,
            mediaBundleIdentifier: "com.spotify.client",
            mediaApplicationName: "Spotify",
            windowOwnerBundleIdentifier: "com.apple.dt.Xcode",
            windowOwnerApplicationName: "Xcode",
            windowOwnerHasFullScreenWindow: true
        ))
    }

    @Test("Application names provide a fail-safe identity fallback")
    func fallsBackToApplicationNames() {
        #expect(FullScreenMediaVisibilityPolicy.shouldHideIsland(
            mediaIsPlaying: true,
            mediaBundleIdentifier: nil,
            mediaApplicationName: " QuickTime Player ",
            windowOwnerBundleIdentifier: nil,
            windowOwnerApplicationName: "quicktime player",
            windowOwnerHasFullScreenWindow: true
        ))
    }

    @Test("Missing media identity fails open")
    func staysVisibleWithoutMediaIdentity() {
        #expect(!FullScreenMediaVisibilityPolicy.shouldHideIsland(
            mediaIsPlaying: true,
            mediaBundleIdentifier: nil,
            mediaApplicationName: nil,
            windowOwnerBundleIdentifier: "com.apple.Safari",
            windowOwnerApplicationName: "Safari",
            windowOwnerHasFullScreenWindow: true
        ))
    }

    @Test("An active audio owner can recover from a stale Now Playing app")
    func activeAudioOwnerRecoversFromStaleNowPlayingApp() {
        #expect(FullScreenMediaVisibilityPolicy.shouldHideIsland(
            mediaIsPlaying: false,
            mediaBundleIdentifier: "company.thebrowser.Browser",
            mediaApplicationName: "Arc",
            windowOwnerBundleIdentifier: "com.google.Chrome",
            windowOwnerApplicationName: "Google Chrome",
            windowOwnerHasFullScreenWindow: false,
            windowOwnerHasAccessibleFullScreenPresentation: true,
            windowOwnerIsProducingAudio: true,
            windowOwnerAccessibilityIndicatesPlayback: true
        ))
    }

    @Test("A maximized audio app without full-screen semantics stays visible")
    func maximizedAudioAppStaysVisible() {
        #expect(!FullScreenMediaVisibilityPolicy.shouldHideIsland(
            mediaIsPlaying: false,
            mediaBundleIdentifier: "company.thebrowser.Browser",
            mediaApplicationName: "Arc",
            windowOwnerBundleIdentifier: "com.google.Chrome",
            windowOwnerApplicationName: "Google Chrome",
            windowOwnerHasFullScreenWindow: false,
            windowOwnerHasAccessibleFullScreenPresentation: false,
            windowOwnerIsProducingAudio: true,
            windowOwnerAccessibilityIndicatesPlayback: true
        ))
    }

    @Test("A single native full-screen window covers its display")
    func recognizesSingleWindowFullScreen() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        #expect(FullScreenWindowCoveragePolicy.coversDisplay(
            display,
            windows: [FullScreenWindowFrameObservation(frame: display, layer: 0)],
            maximumTopBandHeight: 44
        ))
    }

    @Test("A notched full-screen app may split its top band and content")
    func recognizesSplitNotchFullScreen() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let windows = [
            FullScreenWindowFrameObservation(
                frame: CGRect(x: 0, y: 33, width: 1728, height: 1084),
                layer: 0
            ),
            FullScreenWindowFrameObservation(
                frame: CGRect(x: 0, y: 0, width: 1728, height: 33),
                layer: 26
            ),
        ]
        #expect(FullScreenWindowCoveragePolicy.coversDisplay(
            display,
            windows: windows,
            maximumTopBandHeight: 44
        ))
    }

    @Test("A maximized window without an owned top band is not full screen")
    func rejectsOrdinaryMaximizedWindow() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let maximized = FullScreenWindowFrameObservation(
            frame: CGRect(x: 0, y: 33, width: 1728, height: 1084),
            layer: 0
        )
        #expect(!FullScreenWindowCoveragePolicy.coversDisplay(
            display,
            windows: [maximized],
            maximumTopBandHeight: 44
        ))
    }

    @Test("Camera-safe content coverage is available for semantic full screen")
    func recognizesCameraSafeContentCoverage() {
        let display = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let content = FullScreenWindowFrameObservation(
            frame: CGRect(x: 0, y: 33, width: 1728, height: 1084),
            layer: 0
        )
        #expect(FullScreenWindowCoveragePolicy.coversDisplayContent(
            display,
            windows: [content],
            maximumTopBandHeight: 44
        ))
    }

    @Test("Exit full-screen semantics are active while enter semantics are not")
    func recognizesActiveFullScreenSemantics() {
        #expect(FullScreenAccessibilitySemanticPolicy.indicatesActiveFullScreen(
            role: "AXButton",
            labels: ["Exit full screen (f)"]
        ))
        #expect(FullScreenAccessibilitySemanticPolicy.indicatesActiveFullScreen(
            role: "AXGroup",
            labels: ["YouTube Video Player in Fullscreen"]
        ))
        #expect(!FullScreenAccessibilitySemanticPolicy.indicatesActiveFullScreen(
            role: "AXButton",
            labels: ["Full screen (f)"]
        ))
    }

    @Test("Pause control semantics indicate active playback")
    func recognizesActivePlaybackSemantics() {
        #expect(FullScreenAccessibilitySemanticPolicy.indicatesActivePlayback(
            role: "AXButton",
            labels: ["Pause (k)"]
        ))
        #expect(!FullScreenAccessibilitySemanticPolicy.indicatesActivePlayback(
            role: "AXButton",
            labels: ["Play (k)"]
        ))
    }
}

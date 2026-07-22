import CoreGraphics
import Foundation

public struct FullScreenWindowFrameObservation: Equatable, Sendable {
    public let frame: CGRect
    public let layer: Int

    public init(frame: CGRect, layer: Int) {
        self.frame = frame
        self.layer = layer
    }
}

public enum FullScreenMediaPresentationMode: Equatable, Sendable {
    case normal
    case systemFeedbackOnly
    case hidden
}

public enum FullScreenMediaPresentationPolicy {
    public static func mode(
        fullScreenMediaIsActive: Bool,
        hasSystemFeedback: Bool
    ) -> FullScreenMediaPresentationMode {
        guard fullScreenMediaIsActive else { return .normal }
        return hasSystemFeedback ? .systemFeedbackOnly : .hidden
    }
}

public enum FullScreenWindowCoveragePolicy {
    public static func coversDisplay(
        _ displayBounds: CGRect,
        windows: [FullScreenWindowFrameObservation],
        maximumTopBandHeight: CGFloat,
        tolerance: CGFloat = 1.5
    ) -> Bool {
        let normalWindows = windows.filter { $0.layer == 0 }
        if normalWindows.contains(where: {
            framesMatch($0.frame, displayBounds, tolerance: tolerance)
        }) {
            return true
        }

        return normalWindows.contains { contentWindow in
            let content = contentWindow.frame
            let topGap = content.minY - displayBounds.minY
            guard topGap > tolerance,
                  topGap <= maximumTopBandHeight + tolerance,
                  horizontalEdgesMatch(content, displayBounds, tolerance: tolerance),
                  abs(content.maxY - displayBounds.maxY) < tolerance else {
                return false
            }

            return windows.contains { topBand in
                let frame = topBand.frame
                return horizontalEdgesMatch(frame, displayBounds, tolerance: tolerance)
                    && abs(frame.minY - displayBounds.minY) < tolerance
                    && frame.maxY >= content.minY - tolerance
                    && frame.maxY <= content.minY + maximumTopBandHeight + tolerance
            }
        }
    }

    public static func coversDisplayContent(
        _ displayBounds: CGRect,
        windows: [FullScreenWindowFrameObservation],
        maximumTopBandHeight: CGFloat,
        tolerance: CGFloat = 1.5
    ) -> Bool {
        windows.contains { observation in
            guard observation.layer == 0 else { return false }
            let frame = observation.frame
            let topGap = frame.minY - displayBounds.minY
            return topGap >= -tolerance
                && topGap <= maximumTopBandHeight + tolerance
                && horizontalEdgesMatch(frame, displayBounds, tolerance: tolerance)
                && abs(frame.maxY - displayBounds.maxY) < tolerance
        }
    }

    private static func horizontalEdgesMatch(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.minX - rhs.minX) < tolerance
            && abs(lhs.maxX - rhs.maxX) < tolerance
    }

    private static func framesMatch(
        _ lhs: CGRect,
        _ rhs: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        horizontalEdgesMatch(lhs, rhs, tolerance: tolerance)
            && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.maxY - rhs.maxY) < tolerance
    }
}

public enum FullScreenAccessibilitySemanticPolicy {
    public static func indicatesActiveFullScreen(
        role: String?,
        labels: [String]
    ) -> Bool {
        let normalizedRole = normalized(role)
        let normalizedLabels = labels.compactMap(normalized)

        if normalizedRole == "axbutton" {
            return normalizedLabels.contains { label in
                label.contains("exit full screen")
                    || label.contains("exit fullscreen")
                    || label.contains("leave full screen")
                    || label.contains("leave fullscreen")
            }
        }

        return normalizedLabels.contains { label in
            label.contains("in full screen") || label.contains("in fullscreen")
        }
    }

    public static func indicatesActivePlayback(
        role: String?,
        labels: [String]
    ) -> Bool {
        guard normalized(role) == "axbutton" else { return false }
        return labels.compactMap(normalized).contains { label in
            label == "pause"
                || label.hasPrefix("pause ")
                || label.hasPrefix("pause(")
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !value.isEmpty else {
            return nil
        }
        return value
    }
}

public enum FullScreenMediaVisibilityPolicy {
    public static func shouldHideIsland(
        mediaIsPlaying: Bool,
        mediaBundleIdentifier: String?,
        mediaApplicationName: String?,
        windowOwnerBundleIdentifier: String?,
        windowOwnerApplicationName: String?,
        windowOwnerHasFullScreenWindow: Bool,
        windowOwnerHasAccessibleFullScreenPresentation: Bool = false,
        windowOwnerIsProducingAudio: Bool = false,
        windowOwnerAccessibilityIndicatesPlayback: Bool = false
    ) -> Bool {
        let presentsFullScreen = windowOwnerHasFullScreenWindow
            || windowOwnerHasAccessibleFullScreenPresentation
        guard presentsFullScreen else { return false }

        let mediaIdentityMatches = mediaIsPlaying && identitiesMatch(
            mediaBundleIdentifier: mediaBundleIdentifier,
            mediaApplicationName: mediaApplicationName,
            windowOwnerBundleIdentifier: windowOwnerBundleIdentifier,
            windowOwnerApplicationName: windowOwnerApplicationName
        )
        return mediaIdentityMatches
            || windowOwnerIsProducingAudio
            || windowOwnerAccessibilityIndicatesPlayback
    }

    private static func identitiesMatch(
        mediaBundleIdentifier: String?,
        mediaApplicationName: String?,
        windowOwnerBundleIdentifier: String?,
        windowOwnerApplicationName: String?
    ) -> Bool {
        let mediaBundle = normalized(mediaBundleIdentifier)
        let ownerBundle = normalized(windowOwnerBundleIdentifier)
        if let mediaBundle, let ownerBundle {
            return mediaBundle.caseInsensitiveCompare(ownerBundle) == .orderedSame
        }

        guard let mediaName = normalized(mediaApplicationName),
              let ownerName = normalized(windowOwnerApplicationName) else {
            return false
        }
        return mediaName.localizedCaseInsensitiveCompare(ownerName) == .orderedSame
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

import Foundation

public struct IslandDisplayMetrics: Equatable, Sendable {
    public let screenWidth: CGFloat
    public let screenHeight: CGFloat
    public let visibleTop: CGFloat
    public let safeTopInset: CGFloat
    public let cameraHousingLeftEdge: CGFloat?
    public let cameraHousingRightEdge: CGFloat?

    public init(
        screenWidth: CGFloat,
        screenHeight: CGFloat,
        visibleTop: CGFloat,
        safeTopInset: CGFloat,
        cameraHousingLeftEdge: CGFloat?,
        cameraHousingRightEdge: CGFloat?
    ) {
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.visibleTop = visibleTop
        self.safeTopInset = safeTopInset
        self.cameraHousingLeftEdge = cameraHousingLeftEdge
        self.cameraHousingRightEdge = cameraHousingRightEdge
    }

    public var cameraHousingWidth: CGFloat {
        guard let left = cameraHousingLeftEdge, let right = cameraHousingRightEdge else { return 0 }
        return Swift.max(0, right - left)
    }

    public var hasCameraHousing: Bool {
        safeTopInset > 0 && cameraHousingWidth > 0
    }
}

public struct IslandLayout: Equatable, Sendable {
    public let compactWidth: CGFloat
    public let compactHeight: CGFloat
    public let expandedWidth: CGFloat
    public let expandedContentTopInset: CGFloat
    public let expandedNeckWidth: CGFloat
    public let cameraHousingWidth: CGFloat
    public let activityWingWidth: CGFloat
    public let hasCameraHousing: Bool

    public static func make(
        for display: IslandDisplayMetrics,
        expandedWidthFraction: CGFloat = 0.3
    ) -> IslandLayout {
        let expandedWidth = display.screenWidth > 0
            ? display.screenWidth * expandedWidthFraction
            : 404

        guard display.hasCameraHousing else {
            return IslandLayout(
                compactWidth: 198,
                compactHeight: 42,
                expandedWidth: max(198, expandedWidth),
                expandedContentTopInset: 0,
                expandedNeckWidth: 198,
                cameraHousingWidth: 0,
                activityWingWidth: 0,
                hasCameraHousing: false
            )
        }

        // The physical camera housing occupies the middle of this window. Chimlo
        // paints one interactive activity wing on either side, then grows from
        // that exact silhouette below the hardware when expanded.
        let activityWingWidth: CGFloat = 32
        let neckWidth = min(expandedWidth, display.cameraHousingWidth + activityWingWidth * 2)
        return IslandLayout(
            compactWidth: neckWidth,
            compactHeight: display.safeTopInset,
            expandedWidth: max(neckWidth, expandedWidth),
            expandedContentTopInset: display.safeTopInset,
            expandedNeckWidth: neckWidth,
            cameraHousingWidth: display.cameraHousingWidth,
            activityWingWidth: activityWingWidth,
            hasCameraHousing: true
        )
    }
}

public struct ExpandedIslandSilhouette: Equatable, Sendable {
    public let topLeftX: CGFloat
    public let topRightX: CGFloat
    public let topY: CGFloat

    public init(width: CGFloat) {
        topLeftX = 0
        topRightX = max(0, width)
        topY = 0
    }
}

public enum IslandCollapsePolicy {
    public static let hoverDelayMilliseconds = 500
    public static let completionHoldMilliseconds = 5_000
    public static let completionDetailLifetimeSeconds: TimeInterval = 120

    public static func shouldCollapse(
        pointerInside: Bool,
        isSessionPanel: Bool,
        hasBlockingDecision: Bool
    ) -> Bool {
        !pointerInside && isSessionPanel && !hasBlockingDecision
    }

    public static func isNewCompletion(
        wasArmedForCompletion: Bool,
        eventKind: AgentEventKind
    ) -> Bool {
        eventKind == .completed && wasArmedForCompletion
    }
}

import Foundation

public enum SessionInteractionLayout {
    public static func permissionRowHeight(
        promptLineCount: Int,
        detailLineCount: Int?,
        previewLineCount: Int?
    ) -> CGFloat {
        let summaryHeight: CGFloat = 70
        let summaryToPermissionSpacing: CGFloat = 8
        let cardVerticalPadding: CGFloat = 19
        let cardContentSpacing: CGFloat = 9

        var contentHeights: [CGFloat] = [
            13, // Tool header.
            CGFloat(max(1, promptLineCount)) * 15,
            31, // Permission actions.
        ]

        if let detailLineCount {
            contentHeights.insert(CGFloat(max(1, detailLineCount)) * 12, at: 2)
        }

        if let previewLineCount {
            let lines = max(1, previewLineCount)
            let previewHeight = CGFloat(lines) * 13
                + CGFloat(max(0, lines - 1)) * 2
                + 16
            contentHeights.insert(previewHeight, at: contentHeights.count - 1)
        }

        let sectionSpacing = CGFloat(max(0, contentHeights.count - 1)) * cardContentSpacing
        return summaryHeight
            + summaryToPermissionSpacing
            + cardVerticalPadding
            + contentHeights.reduce(0, +)
            + sectionSpacing
    }
}

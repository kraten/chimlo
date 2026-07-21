import Foundation

public enum SessionListLayout {
    public static func contentHeight(
        displayedRowHeights: [CGFloat],
        hasSessions: Bool,
        hasDecision: Bool,
        showsDisclosureControl: Bool,
        isDisclosureContextActive: Bool
    ) -> CGFloat {
        let maximumRowsHeight: CGFloat = 320
        let rowsHeight = displayedRowHeights.reduce(0, +)
        let rowSpacing = CGFloat(max(0, displayedRowHeights.count - 1)) * 6
        let naturalRowsHeight = rowsHeight + rowSpacing
        let rowHeight: CGFloat
        if !hasSessions, !hasDecision {
            rowHeight = 62
        } else {
            rowHeight = min(maximumRowsHeight, naturalRowsHeight)
        }
        let decisionHeight: CGFloat = hasDecision ? 132 : 0
        // Keep the disclosure slot after reveal only when the rows already
        // fill the viewport. That prevents a simultaneous window shrink and
        // scroll relayout without leaving blank space below a short list.
        let retainsDisclosureSlot = isDisclosureContextActive
            && naturalRowsHeight >= maximumRowsHeight
        let disclosureHeight: CGFloat = showsDisclosureControl || retainsDisclosureSlot ? 34 : 0
        return min(366, 12 + rowHeight + decisionHeight + disclosureHeight)
    }
}

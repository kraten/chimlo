import Testing
@testable import ChimloCore

@Suite("Session list layout")
struct SessionListLayoutTests {
    @Test("Revealing hidden sessions does not shrink a scrollable viewport")
    func revealingSessionsKeepsViewportStable() {
        let focusedHeight = SessionListLayout.contentHeight(
            displayedRowHeights: [420],
            hasSessions: true,
            hasDecision: false,
            showsDisclosureControl: true,
            isDisclosureContextActive: true
        )
        let revealedHeight = SessionListLayout.contentHeight(
            displayedRowHeights: [420, 70, 70, 70, 70],
            hasSessions: true,
            hasDecision: false,
            showsDisclosureControl: false,
            isDisclosureContextActive: true
        )

        #expect(revealedHeight == focusedHeight)
    }

    @Test("A short revealed list does not reserve empty disclosure space")
    func shortListHugsItsRows() {
        let height = SessionListLayout.contentHeight(
            displayedRowHeights: [70, 70],
            hasSessions: true,
            hasDecision: false,
            showsDisclosureControl: false,
            isDisclosureContextActive: true
        )

        #expect(height == 158)
    }
}

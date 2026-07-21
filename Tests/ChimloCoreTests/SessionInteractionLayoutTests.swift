import Testing
@testable import ChimloCore

@Suite("Session interaction layout")
struct SessionInteractionLayoutTests {
    @Test("A focused one-line permission reserves no unused preview space")
    func focusedPermissionHugsItsContents() {
        let height = SessionInteractionLayout.permissionRowHeight(
            promptLineCount: 1,
            detailLineCount: 1,
            previewLineCount: 1
        )

        // 70 summary + 8 gap + a 155-point permission card.
        #expect(height == 233)
    }

    @Test("Permission height grows only with visible content")
    func permissionHeightTracksVisibleLines() {
        let compact = SessionInteractionLayout.permissionRowHeight(
            promptLineCount: 1,
            detailLineCount: nil,
            previewLineCount: nil
        )
        let multiline = SessionInteractionLayout.permissionRowHeight(
            promptLineCount: 1,
            detailLineCount: 1,
            previewLineCount: 3
        )

        #expect(compact == 174)
        #expect(multiline == 263)
    }
}

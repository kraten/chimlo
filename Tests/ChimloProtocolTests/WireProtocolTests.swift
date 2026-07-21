import Foundation
import Testing
import ChimloCore
@testable import ChimloProtocol

@Suite("Wire protocol")
struct WireProtocolTests {
    @Test("Frames round-trip")
    func frameRoundTrip() throws {
        let envelope = ChimloEnvelope(
            messageID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sentAt: Date(timeIntervalSince1970: 1_700_000_000),
            authenticationToken: String(repeating: "a", count: 64),
            message: .ping
        )

        let frame = try ChimloFrameCodec.encode(envelope)

        #expect(try ChimloFrameCodec.expectedFrameLength(from: frame) == frame.count)
        #expect(try ChimloFrameCodec.decode(frame) == envelope)
    }

    @Test("Oversized declared lengths are rejected before payload allocation")
    func frameRejectsOversizedDeclaredLength() {
        let impossibleLength = UInt32(ChimloFrameCodec.maximumPayloadBytes + 1)
        let frame = Data([
            UInt8((impossibleLength >> 24) & 0xff),
            UInt8((impossibleLength >> 16) & 0xff),
            UInt8((impossibleLength >> 8) & 0xff),
            UInt8(impossibleLength & 0xff),
        ])

        #expect(throws: (any Error).self) { try ChimloFrameCodec.expectedFrameLength(from: frame) }
        #expect(throws: (any Error).self) { try ChimloFrameCodec.decode(frame) }
    }

    @Test("Trailing bytes are rejected")
    func frameRejectsTrailingBytes() throws {
        let envelope = ChimloEnvelope(
            authenticationToken: String(repeating: "e", count: 64),
            message: .ping
        )
        var frame = try ChimloFrameCodec.encode(envelope)
        frame.append(0)

        #expect(throws: (any Error).self) { try ChimloFrameCodec.decode(frame) }
    }

    @Test("Decision payloads are bounded")
    func largeDecisionPayloadIsBounded() {
        let request = ChimloDecisionRequest(
            title: "Do something",
            message: String(repeating: "x", count: ChimloFrameCodec.maximumPayloadBytes * 2)
        )
        let envelope = ChimloEnvelope(
            authenticationToken: String(repeating: "f", count: 64),
            message: .decisionRequest(request)
        )

        #expect(throws: ChimloProtocolError.self) { try ChimloFrameCodec.encode(envelope) }
    }

    @Test("Only explicit approval counts as approved")
    func onlyExplicitApprovalCountsAsApproved() {
        #expect(ChimloDecisionOutcome.approved.isApproved)
        #expect(!ChimloDecisionOutcome.denied.isApproved)
        #expect(!ChimloDecisionOutcome.cancelled.isApproved)
        #expect(!ChimloDecisionOutcome.unavailable.isApproved)
        #expect(ProviderPermissionOutcome.allowedOnce.grantsPermission)
        #expect(ProviderPermissionOutcome.allowedForSession.grantsPermission)
        #expect(!ProviderPermissionOutcome.denied.grantsPermission)
        #expect(!ProviderPermissionOutcome.cancelled.grantsPermission)
        #expect(!ProviderPermissionOutcome.unavailable.grantsPermission)
    }

    @Test("Provider permission requests round-trip with transient context")
    func providerPermissionRoundTrip() throws {
        let request = ProviderPermissionRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            sessionID: "claude-1",
            agent: .claude,
            title: "chimlo",
            toolName: "Write",
            prompt: "Do you want Claude to write hello.txt?",
            detail: "/tmp/hello.txt",
            preview: "hello",
            allowsSessionApproval: true
        )
        let envelope = ChimloEnvelope(
            sentAt: Date(timeIntervalSince1970: 1_700_000_050),
            authenticationToken: String(repeating: "c", count: 64),
            message: .permissionRequest(request)
        )

        #expect(try ChimloFrameCodec.decode(ChimloFrameCodec.encode(envelope)) == envelope)
    }

    @Test("Question requests round-trip with their options")
    func questionRequestRoundTrip() throws {
        let request = ProviderQuestionRequest(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
            sessionID: "claude-1",
            agent: .claude,
            title: "chimlo",
            questions: [ProviderQuestion(
                prompt: "Which target?",
                header: "Target",
                options: [
                    ProviderQuestionOption(label: "Local", detail: "This Mac"),
                    ProviderQuestionOption(label: "Staging", detail: "Shared environment"),
                ]
            )]
        )
        let envelope = ChimloEnvelope(
            sentAt: Date(timeIntervalSince1970: 1_700_000_100),
            authenticationToken: String(repeating: "b", count: 64),
            message: .questionRequest(request)
        )

        let decoded = try ChimloFrameCodec.decode(ChimloFrameCodec.encode(envelope))

        #expect(decoded == envelope)
    }
}

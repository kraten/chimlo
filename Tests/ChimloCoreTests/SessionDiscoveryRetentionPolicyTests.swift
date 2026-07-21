import Foundation
import Testing
@testable import ChimloCore

@Suite("Session discovery retention")
struct SessionDiscoveryRetentionPolicyTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("A response-backed session remains visible inside two hours")
    func completedResponseSurvivesMetadataReconstruction() {
        #expect(SessionDiscoveryRetentionPolicy.shouldRetain(
            phase: .completed,
            updatedAt: now.addingTimeInterval(-119 * 60),
            hasActiveProcess: false,
            hasLastResponse: true,
            now: now
        ))
    }

    @Test("A session expires at the two-hour activity boundary")
    func completedResponseExpiresAfterActivityWindow() {
        #expect(!SessionVisibilityPolicy.wasActiveRecently(
            updatedAt: now.addingTimeInterval(-2 * 60 * 60),
            now: now
        ))
        #expect(!SessionDiscoveryRetentionPolicy.shouldRetain(
            phase: .completed,
            updatedAt: now.addingTimeInterval(-2 * 60 * 60),
            hasActiveProcess: false,
            hasLastResponse: true,
            now: now
        ))
    }

    @Test("Metadata-only completions retain the short cleanup window")
    func metadataOnlyCompletionExpires() {
        #expect(!SessionDiscoveryRetentionPolicy.shouldRetain(
            phase: .completed,
            updatedAt: now.addingTimeInterval(-24 * 60),
            hasActiveProcess: false,
            hasLastResponse: false,
            now: now
        ))
    }

    @Test("An active process keeps its session regardless of transcript age")
    func activeProcessWins() {
        #expect(SessionDiscoveryRetentionPolicy.shouldRetain(
            phase: .working,
            updatedAt: now.addingTimeInterval(-86_400),
            hasActiveProcess: true,
            hasLastResponse: false,
            now: now
        ))
    }
}

import Foundation
import Testing
@testable import ChimloProtocol

@Suite("Network transport", .serialized)
struct NetworkTransportTests {
    @Test("The loopback server answers ping")
    func loopbackServerAnswersPing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-network-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
        let server = try ChimloServer(descriptorStore: store, eventHandler: { _ in })
        defer { server.stop() }
        _ = try await server.start()

        let client = try ChimloClient(descriptorStore: store, timeout: .seconds(1))
        try await client.ping()
    }

    @Test("Decision transport failure is unavailable, never approved")
    func decisionFailureIsUnavailableRatherThanApproved() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-network-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("missing.json"))
        let client = try ChimloClient(descriptorStore: store, timeout: .milliseconds(50))
        let request = ChimloDecisionRequest(title: "Delete files?", message: "This must fail closed")

        let response = await client.requestDecision(request)

        #expect(response.requestID == request.id)
        #expect(response.outcome == .unavailable)
        #expect(!response.outcome.isApproved)
    }

    @Test("A server without a decision handler returns unavailable")
    func serverDefaultsDecisionsToUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-network-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
        let server = try ChimloServer(descriptorStore: store, eventHandler: { _ in })
        defer { server.stop() }
        _ = try await server.start()
        let client = try ChimloClient(descriptorStore: store, timeout: .seconds(1))
        let request = ChimloDecisionRequest(title: "Run command?", message: "No handler is installed")

        let response = await client.requestDecision(request)

        #expect(response.outcome == .unavailable)
        #expect(!response.outcome.isApproved)
    }
}

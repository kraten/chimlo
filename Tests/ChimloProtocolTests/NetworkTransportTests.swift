import Foundation
import Testing
import ChimloCore
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

    @Test("Claude permission choices round-trip through the loopback server")
    func providerPermissionRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-network-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
        let server = try ChimloServer(
            descriptorStore: store,
            eventHandler: { _ in },
            permissionHandler: { request in
                ProviderPermissionResponse(
                    requestID: request.id,
                    outcome: .allowedForSession
                )
            }
        )
        defer { server.stop() }
        _ = try await server.start()
        let client = try ChimloClient(descriptorStore: store, timeout: .seconds(1))
        let request = ProviderPermissionRequest(
            sessionID: "claude-1",
            agent: .claude,
            title: "chimlo",
            toolName: "Write",
            prompt: "Write hello.txt?",
            allowsSessionApproval: true
        )

        let response = await client.requestPermission(request)

        #expect(response.outcome == .allowedForSession)
        #expect(response.outcome.grantsPermission)
    }

    @Test("A server without a permission handler never grants access")
    func serverDefaultsPermissionsToUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-network-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
        let server = try ChimloServer(descriptorStore: store, eventHandler: { _ in })
        defer { server.stop() }
        _ = try await server.start()
        let client = try ChimloClient(descriptorStore: store, timeout: .seconds(1))
        let request = ProviderPermissionRequest(
            sessionID: "claude-1",
            agent: .claude,
            title: "chimlo",
            toolName: "Bash",
            prompt: "Run this command?"
        )

        let response = await client.requestPermission(request)

        #expect(response.outcome == .unavailable)
        #expect(!response.outcome.grantsPermission)
    }

    @Test("Question selections round-trip through the loopback server")
    func questionSelectionsRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-network-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
        let server = try ChimloServer(
            descriptorStore: store,
            eventHandler: { _ in },
            questionHandler: { request in
                ProviderQuestionResponse(
                    requestID: request.id,
                    outcome: .answered,
                    answers: ["Which target?": "Local"]
                )
            }
        )
        defer { server.stop() }
        _ = try await server.start()
        let client = try ChimloClient(descriptorStore: store, timeout: .seconds(1))
        let request = ProviderQuestionRequest(
            sessionID: "claude-1",
            agent: .claude,
            title: "chimlo",
            questions: [ProviderQuestion(
                prompt: "Which target?",
                options: [
                    ProviderQuestionOption(label: "Local"),
                    ProviderQuestionOption(label: "Staging"),
                ]
            )]
        )

        let response = await client.requestQuestion(request)

        #expect(response.outcome == .answered)
        #expect(response.answers["Which target?"] == "Local")
    }

    @Test("A server without a question handler returns unavailable")
    func serverDefaultsQuestionsToUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-network-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
        let server = try ChimloServer(descriptorStore: store, eventHandler: { _ in })
        defer { server.stop() }
        _ = try await server.start()
        let client = try ChimloClient(descriptorStore: store, timeout: .seconds(1))
        let request = ProviderQuestionRequest(
            sessionID: "claude-1",
            agent: .claude,
            title: "chimlo",
            questions: [ProviderQuestion(
                prompt: "Continue?",
                options: [
                    ProviderQuestionOption(label: "Yes"),
                    ProviderQuestionOption(label: "No"),
                ]
            )]
        )

        let response = await client.requestQuestion(request)

        #expect(response.outcome == .unavailable)
        #expect(response.answers.isEmpty)
    }
}

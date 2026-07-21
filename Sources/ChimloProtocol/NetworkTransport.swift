import ChimloCore
import Foundation
import Network

public final class ChimloServer: @unchecked Sendable {
    public typealias EventHandler = @Sendable (AgentEvent) async -> Void
    public typealias DecisionHandler = @Sendable (ChimloDecisionRequest) async -> ChimloDecisionResponse
    public typealias QuestionHandler = @Sendable (ProviderQuestionRequest) async -> ProviderQuestionResponse

    private let descriptorStore: RuntimeDescriptorStore
    private let eventHandler: EventHandler
    private let decisionHandler: DecisionHandler
    private let questionHandler: QuestionHandler
    private let authenticationToken: String
    private let queue = DispatchQueue(label: "dev.chimlo.protocol.server", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var publishedDescriptor: RuntimeDescriptor?

    public init(
        descriptorStore: RuntimeDescriptorStore? = nil,
        eventHandler: @escaping EventHandler,
        decisionHandler: @escaping DecisionHandler = { request in
            .unavailable(for: request.id, reason: "No decision handler is configured")
        },
        questionHandler: @escaping QuestionHandler = { request in
            .unavailable(for: request.id, reason: "No question handler is configured")
        }
    ) throws {
        self.descriptorStore = try descriptorStore ?? .live()
        self.eventHandler = eventHandler
        self.decisionHandler = decisionHandler
        self.questionHandler = questionHandler
        self.authenticationToken = try SecureAuthenticationToken.generate()
    }

    deinit {
        listener?.cancel()
    }

    @discardableResult
    public func start() async throws -> RuntimeDescriptor {
        let alreadyRunning = lock.withLock { listener != nil }
        guard !alreadyRunning else { throw ChimloProtocolError.serverAlreadyRunning }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let newListener = try NWListener(using: parameters)
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        lock.withLock { listener = newListener }

        do {
            let port = try await waitUntilReady(newListener)
            let descriptor = RuntimeDescriptor(
                port: port,
                authenticationToken: authenticationToken
            )
            try descriptorStore.write(descriptor)
            lock.withLock { publishedDescriptor = descriptor }
            return descriptor
        } catch {
            newListener.cancel()
            lock.withLock {
                listener = nil
                publishedDescriptor = nil
            }
            throw error
        }
    }

    public func stop() {
        lock.lock()
        let activeListener = listener
        let descriptor = publishedDescriptor
        listener = nil
        publishedDescriptor = nil
        lock.unlock()

        activeListener?.cancel()
        if let descriptor {
            try? descriptorStore.remove(ifAuthenticationTokenMatches: descriptor.authenticationToken)
        }
    }

    private func waitUntilReady(_ listener: NWListener) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ContinuationGate()
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    guard let rawPort = listener?.port?.rawValue else {
                        gate.run {
                            continuation.resume(
                                throwing: ChimloProtocolError.connectionFailed("Listener did not publish a port")
                            )
                        }
                        return
                    }
                    gate.run { continuation.resume(returning: rawPort) }
                case let .failed(error):
                    gate.run {
                        continuation.resume(
                            throwing: ChimloProtocolError.connectionFailed(String(describing: error))
                        )
                    }
                case .cancelled:
                    gate.run {
                        continuation.resume(
                            throwing: ChimloProtocolError.connectionFailed("Listener was cancelled")
                        )
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        Task { [weak self, connection] in
            guard let self else {
                connection.cancel()
                return
            }
            do {
                let frame = try await NetworkFrameIO.receiveFrame(from: connection)
                let envelope = try ChimloFrameCodec.decode(frame)
                guard constantTimeEqual(envelope.authenticationToken, authenticationToken) else {
                    connection.cancel()
                    return
                }
                let responseMessage = await response(to: envelope)
                let response = ChimloEnvelope(
                    authenticationToken: authenticationToken,
                    message: responseMessage
                )
                let responseFrame = try ChimloFrameCodec.encode(response)
                try await NetworkFrameIO.send(responseFrame, over: connection)
            } catch {
                // Malformed and unauthenticated requests are intentionally silent.
            }
            connection.cancel()
        }
    }

    private func response(to envelope: ChimloEnvelope) async -> ChimloWireMessage {
        switch envelope.message {
        case let .event(event):
            await eventHandler(event)
            return .acknowledgement(.init(acknowledgedMessageID: envelope.messageID))
        case let .decisionRequest(request):
            if let expiresAt = request.expiresAt, expiresAt <= Date() {
                return .decisionResponse(.unavailable(for: request.id, reason: "Decision request expired"))
            }
            let response = await decisionHandler(request)
            guard response.requestID == request.id else {
                return .decisionResponse(
                    .unavailable(for: request.id, reason: "Decision handler returned a mismatched request identifier")
                )
            }
            return .decisionResponse(response)
        case let .questionRequest(request):
            if let expiresAt = request.expiresAt, expiresAt <= Date() {
                return .questionResponse(.unavailable(for: request.id, reason: "Question request expired"))
            }
            let response = await questionHandler(request)
            guard response.requestID == request.id else {
                return .questionResponse(
                    .unavailable(for: request.id, reason: "Question handler returned a mismatched request identifier")
                )
            }
            return .questionResponse(response)
        case .ping:
            return .acknowledgement(.init(acknowledgedMessageID: envelope.messageID))
        case .decisionResponse, .questionResponse, .acknowledgement, .error:
            return .error(.init(code: .invalidRequest, message: "Message type is not accepted by the server"))
        }
    }
}

public struct ChimloClient: Sendable {
    public let descriptorStore: RuntimeDescriptorStore
    public let timeout: Duration

    public init(
        descriptorStore: RuntimeDescriptorStore? = nil,
        timeout: Duration = .seconds(3)
    ) throws {
        self.descriptorStore = try descriptorStore ?? .live()
        self.timeout = timeout
    }

    @discardableResult
    public func sendEvent(_ event: AgentEvent) async throws -> ChimloAcknowledgement {
        let requestID = UUID()
        let response = try await exchange(.event(event), messageID: requestID)
        guard case let .acknowledgement(acknowledgement) = response,
              acknowledgement.acknowledgedMessageID == requestID else {
            throw ChimloProtocolError.unexpectedMessage("Expected an acknowledgement")
        }
        return acknowledgement
    }

    @discardableResult
    public func ping() async throws -> ChimloAcknowledgement {
        let requestID = UUID()
        let response = try await exchange(.ping, messageID: requestID)
        guard case let .acknowledgement(acknowledgement) = response,
              acknowledgement.acknowledgedMessageID == requestID else {
            throw ChimloProtocolError.unexpectedMessage("Expected a ping acknowledgement")
        }
        return acknowledgement
    }

    /// Decision transport is fail-closed by design: callers always receive a
    /// response, and every communication failure maps to `.unavailable`.
    public func requestDecision(_ request: ChimloDecisionRequest) async -> ChimloDecisionResponse {
        do {
            let message = try await exchange(.decisionRequest(request), messageID: UUID())
            guard case let .decisionResponse(response) = message,
                  response.requestID == request.id else {
                return .unavailable(for: request.id, reason: "Chimlo returned an invalid decision response")
            }
            return response
        } catch {
            return .unavailable(for: request.id, reason: error.localizedDescription)
        }
    }

    /// Question transport also fails back to the provider. A missing or stale
    /// Chimlo process never fabricates an answer.
    public func requestQuestion(_ request: ProviderQuestionRequest) async -> ProviderQuestionResponse {
        do {
            let message = try await exchange(.questionRequest(request), messageID: UUID())
            guard case let .questionResponse(response) = message,
                  response.requestID == request.id else {
                return .unavailable(for: request.id, reason: "Chimlo returned an invalid question response")
            }
            return response
        } catch {
            return .unavailable(for: request.id, reason: error.localizedDescription)
        }
    }

    private func exchange(_ message: ChimloWireMessage, messageID: UUID) async throws -> ChimloWireMessage {
        let descriptor = try descriptorStore.read()
        let envelope = ChimloEnvelope(
            messageID: messageID,
            authenticationToken: descriptor.authenticationToken,
            message: message
        )
        let frame = try ChimloFrameCodec.encode(envelope)
        let responseFrame = try await withTimeout(timeout) {
            try await NetworkFrameIO.roundTrip(frame, descriptor: descriptor)
        }
        let response = try ChimloFrameCodec.decode(responseFrame)
        guard constantTimeEqual(response.authenticationToken, descriptor.authenticationToken) else {
            throw ChimloProtocolError.authenticationFailed
        }
        if case let .error(error) = response.message {
            throw ChimloProtocolError.unexpectedMessage("\(error.code.rawValue): \(error.message)")
        }
        return response.message
    }
}

private enum NetworkFrameIO {
    static func roundTrip(_ frame: Data, descriptor: RuntimeDescriptor) async throws -> Data {
        guard let port = NWEndpoint.Port(rawValue: descriptor.port) else {
            throw ChimloProtocolError.invalidDescriptor("Port could not be represented")
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(descriptor.host),
            port: port,
            using: .tcp
        )
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        return try await withTaskCancellationHandler {
            try await send(frame, over: connection)
            let response = try await receiveFrame(from: connection)
            connection.cancel()
            return response
        } onCancel: {
            connection.cancel()
        }
    }

    static func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(
                        throwing: ChimloProtocolError.connectionFailed(String(describing: error))
                    )
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    static func receiveFrame(from connection: NWConnection) async throws -> Data {
        var buffer = Data()
        while true {
            if let expectedLength = try ChimloFrameCodec.expectedFrameLength(from: buffer) {
                guard buffer.count <= expectedLength else {
                    throw ChimloProtocolError.invalidFrame("Connection sent more than one frame")
                }
                if buffer.count == expectedLength { return buffer }
            }

            let chunk = try await receiveChunk(from: connection)
            guard !chunk.isEmpty else {
                throw ChimloProtocolError.connectionFailed("Connection closed before a full response arrived")
            }
            buffer.append(chunk)
            guard buffer.count <= ChimloFrameCodec.maximumPayloadBytes + ChimloFrameCodec.headerBytes else {
                throw ChimloProtocolError.payloadTooLarge(buffer.count)
            }
        }
    }

    private static func receiveChunk(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: ChimloFrameCodec.maximumPayloadBytes + ChimloFrameCodec.headerBytes
            ) { data, _, isComplete, error in
                if let error {
                    continuation.resume(
                        throwing: ChimloProtocolError.connectionFailed(String(describing: error))
                    )
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: Data())
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRun = false

    func run(_ operation: () -> Void) {
        lock.lock()
        guard !hasRun else {
            lock.unlock()
            return
        }
        hasRun = true
        lock.unlock()
        operation()
    }
}

private func withTimeout<Value: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw ChimloProtocolError.timedOut
        }
        guard let result = try await group.next() else {
            throw ChimloProtocolError.timedOut
        }
        group.cancelAll()
        return result
    }
}

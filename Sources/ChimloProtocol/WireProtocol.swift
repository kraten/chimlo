import ChimloCore
import Foundation

public struct ChimloDecisionRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String
    public let approveLabel: String
    public let denyLabel: String
    public let expiresAt: Date?
    public let context: [String: String]

    public init(
        id: UUID = UUID(),
        title: String,
        message: String,
        approveLabel: String = "Approve",
        denyLabel: String = "Deny",
        expiresAt: Date? = nil,
        context: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.approveLabel = approveLabel
        self.denyLabel = denyLabel
        self.expiresAt = expiresAt
        self.context = context
    }
}

public enum ChimloDecisionOutcome: String, Codable, Equatable, Sendable {
    case approved
    case denied
    case cancelled
    case unavailable

    /// Approval is deliberately opt-in. Timeouts, cancellation, malformed
    /// replies and transport errors all resolve to a non-approved outcome.
    public var isApproved: Bool { self == .approved }
}

public struct ChimloDecisionResponse: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let outcome: ChimloDecisionOutcome
    public let note: String?
    public let resolvedAt: Date

    public init(
        requestID: UUID,
        outcome: ChimloDecisionOutcome,
        note: String? = nil,
        resolvedAt: Date = Date()
    ) {
        self.requestID = requestID
        self.outcome = outcome
        self.note = note
        self.resolvedAt = resolvedAt
    }

    public static func unavailable(for requestID: UUID, reason: String? = nil) -> Self {
        Self(requestID: requestID, outcome: .unavailable, note: reason)
    }
}

public struct ChimloAcknowledgement: Codable, Equatable, Sendable {
    public let acknowledgedMessageID: UUID

    public init(acknowledgedMessageID: UUID) {
        self.acknowledgedMessageID = acknowledgedMessageID
    }
}

public struct ChimloRemoteError: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Equatable, Sendable {
        case invalidRequest = "invalid_request"
        case unsupportedVersion = "unsupported_version"
        case internalError = "internal_error"
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

public enum ChimloWireMessage: Codable, Equatable, Sendable {
    case event(AgentEvent)
    case decisionRequest(ChimloDecisionRequest)
    case decisionResponse(ChimloDecisionResponse)
    case permissionRequest(ProviderPermissionRequest)
    case permissionResponse(ProviderPermissionResponse)
    case questionRequest(ProviderQuestionRequest)
    case questionResponse(ProviderQuestionResponse)
    case acknowledgement(ChimloAcknowledgement)
    case ping
    case error(ChimloRemoteError)

    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum MessageType: String, Codable {
        case event
        case decisionRequest = "decision_request"
        case decisionResponse = "decision_response"
        case permissionRequest = "permission_request"
        case permissionResponse = "permission_response"
        case questionRequest = "question_request"
        case questionResponse = "question_response"
        case acknowledgement
        case ping
        case error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(MessageType.self, forKey: .type)
        switch type {
        case .event:
            self = .event(try container.decode(AgentEvent.self, forKey: .payload))
        case .decisionRequest:
            self = .decisionRequest(try container.decode(ChimloDecisionRequest.self, forKey: .payload))
        case .decisionResponse:
            self = .decisionResponse(try container.decode(ChimloDecisionResponse.self, forKey: .payload))
        case .permissionRequest:
            self = .permissionRequest(try container.decode(ProviderPermissionRequest.self, forKey: .payload))
        case .permissionResponse:
            self = .permissionResponse(try container.decode(ProviderPermissionResponse.self, forKey: .payload))
        case .questionRequest:
            self = .questionRequest(try container.decode(ProviderQuestionRequest.self, forKey: .payload))
        case .questionResponse:
            self = .questionResponse(try container.decode(ProviderQuestionResponse.self, forKey: .payload))
        case .acknowledgement:
            self = .acknowledgement(try container.decode(ChimloAcknowledgement.self, forKey: .payload))
        case .ping:
            self = .ping
        case .error:
            self = .error(try container.decode(ChimloRemoteError.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .event(event):
            try container.encode(MessageType.event, forKey: .type)
            try container.encode(event, forKey: .payload)
        case let .decisionRequest(request):
            try container.encode(MessageType.decisionRequest, forKey: .type)
            try container.encode(request, forKey: .payload)
        case let .decisionResponse(response):
            try container.encode(MessageType.decisionResponse, forKey: .type)
            try container.encode(response, forKey: .payload)
        case let .permissionRequest(request):
            try container.encode(MessageType.permissionRequest, forKey: .type)
            try container.encode(request, forKey: .payload)
        case let .permissionResponse(response):
            try container.encode(MessageType.permissionResponse, forKey: .type)
            try container.encode(response, forKey: .payload)
        case let .questionRequest(request):
            try container.encode(MessageType.questionRequest, forKey: .type)
            try container.encode(request, forKey: .payload)
        case let .questionResponse(response):
            try container.encode(MessageType.questionResponse, forKey: .type)
            try container.encode(response, forKey: .payload)
        case let .acknowledgement(acknowledgement):
            try container.encode(MessageType.acknowledgement, forKey: .type)
            try container.encode(acknowledgement, forKey: .payload)
        case .ping:
            try container.encode(MessageType.ping, forKey: .type)
        case let .error(error):
            try container.encode(MessageType.error, forKey: .type)
            try container.encode(error, forKey: .payload)
        }
    }
}

public struct ChimloEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let messageID: UUID
    public let sentAt: Date
    public let authenticationToken: String
    public let message: ChimloWireMessage

    public init(
        protocolVersion: Int = RuntimeDescriptor.currentProtocolVersion,
        messageID: UUID = UUID(),
        sentAt: Date = Date(),
        authenticationToken: String,
        message: ChimloWireMessage
    ) {
        self.protocolVersion = protocolVersion
        self.messageID = messageID
        self.sentAt = sentAt
        self.authenticationToken = authenticationToken
        self.message = message
    }
}

public enum ChimloFrameCodec {
    /// A deliberately small limit for local status events. The prefix itself is
    /// not included in this number.
    public static let maximumPayloadBytes = 64 * 1024
    public static let headerBytes = 4

    public static func encode(_ envelope: ChimloEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(envelope)
        guard !payload.isEmpty, payload.count <= maximumPayloadBytes else {
            throw ChimloProtocolError.payloadTooLarge(payload.count)
        }

        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: headerBytes)
        framed.append(payload)
        return framed
    }

    public static func decode(_ frame: Data) throws -> ChimloEnvelope {
        guard frame.count >= headerBytes else {
            throw ChimloProtocolError.invalidFrame("Missing length prefix")
        }

        let length = frame.prefix(headerBytes).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        guard length > 0, length <= maximumPayloadBytes else {
            throw ChimloProtocolError.invalidFrame("Declared payload length is out of bounds")
        }
        guard frame.count == headerBytes + Int(length) else {
            throw ChimloProtocolError.invalidFrame("Declared and actual payload lengths differ")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: ChimloEnvelope
        do {
            envelope = try decoder.decode(ChimloEnvelope.self, from: frame.dropFirst(headerBytes))
        } catch {
            throw ChimloProtocolError.invalidFrame("Payload is not a valid Chimlo envelope")
        }

        guard envelope.protocolVersion == RuntimeDescriptor.currentProtocolVersion else {
            throw ChimloProtocolError.unsupportedProtocolVersion(envelope.protocolVersion)
        }
        return envelope
    }

    public static func expectedFrameLength(from bufferedData: Data) throws -> Int? {
        guard bufferedData.count >= headerBytes else { return nil }
        let length = bufferedData.prefix(headerBytes).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        guard length > 0, length <= maximumPayloadBytes else {
            throw ChimloProtocolError.invalidFrame("Declared payload length is out of bounds")
        }
        return headerBytes + Int(length)
    }
}

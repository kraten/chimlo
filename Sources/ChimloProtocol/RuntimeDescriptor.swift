import Foundation
import Security

public struct RuntimeDescriptor: Codable, Equatable, Sendable {
    public static let currentProtocolVersion = 1

    public let protocolVersion: Int
    public let host: String
    public let port: UInt16
    public let authenticationToken: String
    public let processID: Int32
    public let startedAt: Date

    public init(
        protocolVersion: Int = RuntimeDescriptor.currentProtocolVersion,
        host: String = "127.0.0.1",
        port: UInt16,
        authenticationToken: String,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        startedAt: Date = Date()
    ) {
        self.protocolVersion = protocolVersion
        self.host = host
        self.port = port
        self.authenticationToken = authenticationToken
        self.processID = processID
        self.startedAt = startedAt
    }

    public func validate() throws {
        guard protocolVersion == Self.currentProtocolVersion else {
            throw ChimloProtocolError.unsupportedProtocolVersion(protocolVersion)
        }
        guard Self.loopbackHosts.contains(host) else {
            throw ChimloProtocolError.nonLoopbackHost(host)
        }
        guard port > 0 else {
            throw ChimloProtocolError.invalidDescriptor("Port must be non-zero")
        }
        guard authenticationToken.utf8.count >= 32 else {
            throw ChimloProtocolError.invalidDescriptor("Authentication token is too short")
        }
        guard processID > 0 else {
            throw ChimloProtocolError.invalidDescriptor("Process identifier must be positive")
        }
    }

    private static let loopbackHosts: Set<String> = ["127.0.0.1", "::1", "localhost"]
}

public struct RuntimeDescriptorStore: Sendable {
    public static let environmentKey = "CHIMLO_RUNTIME_DESCRIPTOR"
    public static let maximumDescriptorBytes = 16 * 1024

    public let descriptorURL: URL

    public init(descriptorURL: URL) {
        self.descriptorURL = descriptorURL
    }

    public static func live(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        if let override = environment[environmentKey], !override.isEmpty {
            return Self(descriptorURL: URL(fileURLWithPath: override).standardizedFileURL)
        }

        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ChimloProtocolError.runtimeDescriptorUnavailable
        }

        return Self(
            descriptorURL: applicationSupport
                .appendingPathComponent("Chimlo", isDirectory: true)
                .appendingPathComponent("runtime.json", isDirectory: false)
        )
    }

    public func read() throws -> RuntimeDescriptor {
        let values = try descriptorURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw ChimloProtocolError.runtimeDescriptorUnavailable
        }
        guard let fileSize = values.fileSize, fileSize > 0, fileSize <= Self.maximumDescriptorBytes else {
            throw ChimloProtocolError.invalidDescriptor("Descriptor file has an invalid size")
        }

        let data = try Data(contentsOf: descriptorURL, options: [.mappedIfSafe])
        let descriptor: RuntimeDescriptor
        do {
            descriptor = try Self.decoder.decode(RuntimeDescriptor.self, from: data)
        } catch {
            throw ChimloProtocolError.invalidDescriptor("Descriptor JSON could not be decoded")
        }
        try descriptor.validate()
        return descriptor
    }

    public func write(_ descriptor: RuntimeDescriptor) throws {
        try descriptor.validate()
        let directory = descriptorURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let data = try Self.encoder.encode(descriptor)
        guard data.count <= Self.maximumDescriptorBytes else {
            throw ChimloProtocolError.payloadTooLarge(data.count)
        }
        try data.write(to: descriptorURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: descriptorURL.path)
    }

    /// Removes only the descriptor owned by the caller. This prevents an older
    /// Chimlo process from deleting a newer process's runtime descriptor.
    public func remove(ifAuthenticationTokenMatches token: String) throws {
        guard FileManager.default.fileExists(atPath: descriptorURL.path) else { return }
        let descriptor = try read()
        guard constantTimeEqual(descriptor.authenticationToken, token) else { return }
        try FileManager.default.removeItem(at: descriptorURL)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum SecureAuthenticationToken {
    public static func generate(byteCount: Int = 32) throws -> String {
        guard byteCount >= 16 else {
            throw ChimloProtocolError.invalidDescriptor("Authentication token entropy is too low")
        }
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw ChimloProtocolError.secureRandomFailed(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
    let lhsBytes = Array(lhs.utf8)
    let rhsBytes = Array(rhs.utf8)
    var difference = UInt(lhsBytes.count ^ rhsBytes.count)
    let count = max(lhsBytes.count, rhsBytes.count)
    for index in 0..<count {
        let left = index < lhsBytes.count ? lhsBytes[index] : 0
        let right = index < rhsBytes.count ? rhsBytes[index] : 0
        difference |= UInt(left ^ right)
    }
    return difference == 0
}

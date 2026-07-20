import Foundation

public enum ChimloProtocolError: Error, Equatable, LocalizedError, Sendable {
    case runtimeDescriptorUnavailable
    case invalidDescriptor(String)
    case unsupportedProtocolVersion(Int)
    case nonLoopbackHost(String)
    case secureRandomFailed(OSStatus)
    case payloadTooLarge(Int)
    case invalidFrame(String)
    case authenticationFailed
    case unexpectedMessage(String)
    case connectionFailed(String)
    case timedOut
    case serverAlreadyRunning

    public var errorDescription: String? {
        switch self {
        case .runtimeDescriptorUnavailable:
            "Chimlo is not running, or its runtime descriptor is unavailable."
        case let .invalidDescriptor(reason):
            "The Chimlo runtime descriptor is invalid: \(reason)."
        case let .unsupportedProtocolVersion(version):
            "Chimlo protocol version \(version) is not supported."
        case let .nonLoopbackHost(host):
            "Refusing to connect to non-loopback host \(host)."
        case let .secureRandomFailed(status):
            "Could not create a secure authentication token (status \(status))."
        case let .payloadTooLarge(size):
            "The Chimlo payload is too large (\(size) bytes)."
        case let .invalidFrame(reason):
            "The Chimlo frame is invalid: \(reason)."
        case .authenticationFailed:
            "Chimlo authentication failed."
        case let .unexpectedMessage(message):
            "Chimlo returned an unexpected message: \(message)."
        case let .connectionFailed(message):
            "Could not communicate with Chimlo: \(message)."
        case .timedOut:
            "Communication with Chimlo timed out."
        case .serverAlreadyRunning:
            "The Chimlo protocol server is already running."
        }
    }
}

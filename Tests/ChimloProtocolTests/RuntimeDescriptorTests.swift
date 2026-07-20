import Foundation
import Testing
@testable import ChimloProtocol

@Suite("Runtime descriptor")
struct RuntimeDescriptorTests {
    @Test("The protected descriptor store round-trips")
    func descriptorRoundTripsThroughProtectedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-descriptor-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
        let descriptor = RuntimeDescriptor(
            port: 43_210,
            authenticationToken: String(repeating: "a", count: 64),
            processID: 123,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try store.write(descriptor)

        #expect(try store.read() == descriptor)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.descriptorURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Non-loopback hosts are rejected")
    func descriptorRejectsNonLoopbackHost() {
        let descriptor = RuntimeDescriptor(
            host: "example.com",
            port: 80,
            authenticationToken: String(repeating: "b", count: 64)
        )

        #expect(throws: ChimloProtocolError.self) { try descriptor.validate() }
    }

    @Test("Short tokens are rejected")
    func descriptorRejectsShortToken() {
        let descriptor = RuntimeDescriptor(port: 1, authenticationToken: "guessable")
        #expect(throws: ChimloProtocolError.self) { try descriptor.validate() }
    }

    @Test("An older owner cannot delete a newer descriptor")
    func olderOwnerCannotDeleteNewDescriptor() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-descriptor-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
        let token = String(repeating: "c", count: 64)
        try store.write(RuntimeDescriptor(port: 9_999, authenticationToken: token))

        try store.remove(ifAuthenticationTokenMatches: String(repeating: "d", count: 64))
        #expect(FileManager.default.fileExists(atPath: store.descriptorURL.path))

        try store.remove(ifAuthenticationTokenMatches: token)
        #expect(!FileManager.default.fileExists(atPath: store.descriptorURL.path))
    }

    @Test("Generated tokens have enough descriptor entropy")
    func generatedTokensHaveEnoughEntropyForDescriptor() throws {
        let first = try SecureAuthenticationToken.generate()
        let second = try SecureAuthenticationToken.generate()

        #expect(first.count == 64)
        #expect(second.count == 64)
        #expect(first != second)
    }
}

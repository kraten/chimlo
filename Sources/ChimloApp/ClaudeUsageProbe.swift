import ChimloCore
import Darwin
import Foundation

// The PTY session and probe-artifact cleanup approach adapts CodexBar's
// MIT-licensed Claude provider implementation. See Vendor/CodexBar/LICENSE.

enum ClaudeUsageProbeError: Error, LocalizedError {
    case executableUnavailable
    case terminalUnavailable
    case launchFailed(String)
    case timedOut
    case usageUnavailable

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            "Claude Code is not installed in a known location"
        case .terminalUnavailable:
            "Chimlo could not create a terminal for Claude Code"
        case let .launchFailed(reason):
            "Claude Code usage probe could not start: \(reason)"
        case .timedOut:
            "Claude Code did not return usage limits before the probe timed out"
        case .usageUnavailable:
            "Claude Code did not return session and weekly usage limits"
        }
    }
}

/// A provider-owned, read-only fallback for stale Claude capacity. It opens a
/// short-lived Claude Code terminal, runs `/usage`, and cleans its dedicated
/// transcript artifacts after exit. It never enables tools. No tokens, Keychain
/// items, cookies, or private HTTP endpoints are read by this probe.
actor ClaudeUsageProbe {
    static let workingDirectoryName = "Claude Usage Probe"
    private static let sessionIDFilename = ".chimlo-session-id"

    private let fileManager: FileManager
    private let environment: [String: String]
    private let timeout: TimeInterval
    private let idleTimeout: TimeInterval
    private let maximumOutputBytes: Int

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 20,
        idleTimeout: TimeInterval = 3,
        maximumOutputBytes: Int = 512 * 1_024
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.timeout = timeout
        self.idleTimeout = idleTimeout
        self.maximumOutputBytes = maximumOutputBytes
    }

    func fetch(observedAt: Date = .now) async throws -> ProviderCapacitySnapshot {
        guard let executableURL = resolveExecutable() else {
            throw ClaudeUsageProbeError.executableUnavailable
        }

        let workingDirectory = Self.workingDirectoryURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let sessionID = loadOrCreateSessionID(in: workingDirectory)
        cleanupProbeSessionArtifacts(for: workingDirectory)

        var primary: Int32 = -1
        var replica: Int32 = -1
        var size = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &replica, nil, nil, &size) == 0 else {
            throw ClaudeUsageProbeError.terminalUnavailable
        }

        let process = Process()
        let replicaHandle = FileHandle(fileDescriptor: replica, closeOnDealloc: false)
        process.executableURL = executableURL
        process.arguments = [
            "--allowed-tools", "",
            "--session-id", sessionID.uuidString.lowercased(),
        ]
        process.currentDirectoryURL = workingDirectory
        process.standardInput = replicaHandle
        process.standardOutput = replicaHandle
        process.standardError = replicaHandle
        var launchEnvironment = probeEnvironment()
        launchEnvironment["PWD"] = workingDirectory.path
        process.environment = launchEnvironment

        let existingFlags = fcntl(primary, F_GETFL)
        if existingFlags >= 0 {
            _ = fcntl(primary, F_SETFL, existingFlags | O_NONBLOCK)
        }

        do {
            try process.run()
        } catch {
            close(primary)
            close(replica)
            throw ClaudeUsageProbeError.launchFailed(error.localizedDescription)
        }
        close(replica)

        defer {
            if process.isRunning {
                write("/exit\r", to: primary)
                process.terminate()
                let deadline = Date.now.addingTimeInterval(1)
                while process.isRunning, Date.now < deadline {
                    usleep(50_000)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            close(primary)
            cleanupProbeSessionArtifacts(for: workingDirectory)
        }

        let startedAt = Date.now
        var lastOutputAt = startedAt
        var output = Data()
        var sentUsageCommand = false
        var answeredTrustPrompt = false
        var answeredSafetyPrompt = false
        var acceptedUsageMenuItem = false
        var lastEnterAt = startedAt

        while !Task.isCancelled, process.isRunning {
            let chunk = readAvailable(from: primary)
            if !chunk.isEmpty {
                lastOutputAt = .now
                appendBounded(chunk, to: &output)
            }

            let text = String(decoding: output, as: UTF8.self)
            let folded = text.lowercased()

            if !answeredTrustPrompt,
               folded.contains("do you trust the files in this folder") {
                write("y\r", to: primary)
                answeredTrustPrompt = true
            }
            if !answeredSafetyPrompt,
               folded.contains("quick safety check")
                || folded.contains("yes, i trust")
                || folded.contains("ready to code here")
                || folded.contains("press enter") {
                write("\r", to: primary)
                answeredSafetyPrompt = true
            }
            if folded.contains("\u{001B}[6n") {
                write("\u{001B}[1;1R", to: primary)
            }

            if !sentUsageCommand, Date.now.timeIntervalSince(startedAt) >= 2 {
                write("/usage\r", to: primary)
                sentUsageCommand = true
                lastOutputAt = .now
            }

            if sentUsageCommand,
               !acceptedUsageMenuItem,
               (folded.contains("show plan usage limits")
                || folded.contains("plan usage")) {
                write("\r", to: primary)
                acceptedUsageMenuItem = true
                lastOutputAt = .now
            }

            // Claude 2.1 can draw the usage panel in stages. A periodic Enter
            // confirms the selected `/usage` palette item and lets the panel
            // settle, matching the provider's own interactive workflow.
            if sentUsageCommand,
               Date.now.timeIntervalSince(lastEnterAt) >= 0.8 {
                write("\r", to: primary)
                lastEnterAt = .now
            }

            if sentUsageCommand,
               let snapshot = ProviderCapacityParser.claudeUsagePanel(
                   text,
                   observedAt: observedAt
               ),
               snapshot.window(.session) != nil,
               snapshot.window(.weekly) != nil {
                return snapshot
            }

            let now = Date.now
            if now.timeIntervalSince(startedAt) >= timeout {
                throw ClaudeUsageProbeError.timedOut
            }
            if sentUsageCommand,
               now.timeIntervalSince(lastOutputAt) >= idleTimeout {
                if let snapshot = ProviderCapacityParser.claudeUsagePanel(
                    text,
                    observedAt: observedAt
                ) {
                    return snapshot
                }
                throw ClaudeUsageProbeError.usageUnavailable
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        if Task.isCancelled { throw CancellationError() }
        let text = String(decoding: output, as: UTF8.self)
        guard let snapshot = ProviderCapacityParser.claudeUsagePanel(
            text,
            observedAt: observedAt
        ) else {
            throw ClaudeUsageProbeError.usageUnavailable
        }
        return snapshot
    }

    static func workingDirectoryURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chimlo", isDirectory: true)
            .appendingPathComponent(workingDirectoryName, isDirectory: true)
    }

    private func resolveExecutable() -> URL? {
        var candidates: [String] = []
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("claude")
                    .path
            })
        }
        let home = fileManager.homeDirectoryForCurrentUser
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home.appendingPathComponent(".local/bin/claude").path,
            home.appendingPathComponent(".claude/local/claude").path,
        ])

        var seen = Set<String>()
        return candidates.first { path in
            seen.insert(path).inserted && fileManager.isExecutableFile(atPath: path)
        }.map { URL(fileURLWithPath: $0) }
    }

    private func probeEnvironment() -> [String: String] {
        var result = environment.filter { key, _ in
            !key.uppercased().hasPrefix("ANTHROPIC_")
        }
        result["DISABLE_AUTOUPDATER"] = "1"
        result["TERM"] = "xterm-256color"
        result["COLUMNS"] = "160"
        result["LINES"] = "50"
        result["CHIMLO_USAGE_PROBE"] = "1"
        return result
    }

    private func loadOrCreateSessionID(in directory: URL) -> UUID {
        let url = directory.appendingPathComponent(Self.sessionIDFilename)
        if let raw = try? String(contentsOf: url, encoding: .utf8),
           let existing = UUID(
            uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)
           ) {
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return existing
        }

        let sessionID = UUID()
        do {
            try sessionID.uuidString.lowercased().write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            return sessionID
        }
        return sessionID
    }

    private func cleanupProbeSessionArtifacts(for workingDirectory: URL) {
        let directoryName = claudeProjectDirectoryName(for: workingDirectory)
        for root in claudeConfigurationRoots() {
            let directory = root
                .appendingPathComponent("projects", isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "jsonl" {
                guard (try? entry.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                    continue
                }
                try? fileManager.removeItem(at: entry)
            }
            if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private func claudeConfigurationRoots() -> [URL] {
        var roots: [URL] = []
        if let configured = environment["CLAUDE_CONFIG_DIR"] {
            roots.append(contentsOf: configured.split(separator: ",").compactMap { part in
                let path = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
            })
        }
        let home = fileManager.homeDirectoryForCurrentUser
        roots.append(home.appendingPathComponent(".claude", isDirectory: true))
        roots.append(home.appendingPathComponent(".config/claude", isDirectory: true))

        var seen = Set<String>()
        return roots.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    }

    private func claudeProjectDirectoryName(for directory: URL) -> String {
        let path = directory.path.precomposedStringWithCanonicalMapping
        let sanitized = String(path.utf16.map { codeUnit in
            switch codeUnit {
            case 48...57, 65...90, 97...122:
                Character(UnicodeScalar(codeUnit)!)
            default:
                "-"
            }
        })
        guard sanitized.count > 200 else { return sanitized }
        return "\(sanitized.prefix(200))-\(javaScriptHashBase36(path))"
    }

    private func javaScriptHashBase36(_ value: String) -> String {
        var hash: Int32 = 0
        for codeUnit in value.utf16 {
            hash = hash &* 31 &+ Int32(truncatingIfNeeded: codeUnit)
        }
        let magnitude = hash < 0 ? -Int64(hash) : Int64(hash)
        return String(magnitude, radix: 36)
    }

    private func readAvailable(from descriptor: Int32) -> Data {
        var buffer = [UInt8](repeating: 0, count: 8_192)
        let count = buffer.withUnsafeMutableBytes { bytes in
            Darwin.read(descriptor, bytes.baseAddress, bytes.count)
        }
        guard count > 0 else { return Data() }
        return Data(buffer.prefix(count))
    }

    private func appendBounded(_ chunk: Data, to output: inout Data) {
        output.append(chunk)
        guard output.count > maximumOutputBytes else { return }
        output.removeFirst(output.count - maximumOutputBytes)
    }

    private func write(_ value: String, to descriptor: Int32) {
        let bytes = Array(value.utf8)
        bytes.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            var retries = 0
            while offset < buffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if written > 0 {
                    offset += written
                    retries = 0
                    continue
                }
                if written < 0,
                   errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                    retries += 1
                    guard retries <= 50 else { return }
                    usleep(5_000)
                    continue
                }
                return
            }
        }
    }
}

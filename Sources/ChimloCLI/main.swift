import ChimloCore
import ChimloProtocol
import Darwin
import Foundation

@main
enum ChimloCommand {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            writeError("chimlo: \(error.localizedDescription)\n")
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ arguments: [String]) async throws {
        guard let command = arguments.first else {
            print(usage)
            return
        }

        switch command {
        case "emit":
            let options = try Options(Array(arguments.dropFirst()))
            let event = try makeEvent(options: options)
            let client = try ChimloClient()
            _ = try await client.sendEvent(event)
            print("emitted \(event.kind.rawValue) for \(event.sessionID) #\(event.sequence)")
        case "demo":
            let options = try Options(Array(arguments.dropFirst()))
            try await runDemo(options: options)
        case "ping":
            let client = try ChimloClient()
            _ = try await client.ping()
            print("chimlo is listening")
        case "decision":
            let options = try Options(Array(arguments.dropFirst()))
            try await requestDecision(options: options)
        case "hook":
            await observeProviderHook(Array(arguments.dropFirst()))
        case "descriptor":
            let store = try RuntimeDescriptorStore.live()
            let descriptor = try store.read()
            print("\(descriptor.host):\(descriptor.port) pid=\(descriptor.processID) protocol=\(descriptor.protocolVersion)")
        case "help", "--help", "-h":
            print(usage)
        default:
            throw CLIError("Unknown command '\(command)'.\n\n\(usage)")
        }
    }

    /// Provider hooks must never block or break the invoking coding agent.
    /// `{}` is the documented no-op response; delivery failure is intentionally
    /// silent and leaves the native provider UI authoritative.
    private static func observeProviderHook(_ arguments: [String]) async {
        defer { print("{}") }
        guard arguments.count == 2,
              arguments[1] == "observe",
              let source = ProviderHookSource(rawValue: arguments[0]) else { return }

        do {
            guard let data = try FileHandle.standardInput.read(
                upToCount: PrivacySafeHookMapper.maximumPayloadBytes + 1
            ), data.count <= PrivacySafeHookMapper.maximumPayloadBytes,
                  let event = try PrivacySafeHookMapper.event(from: data, source: source) else { return }
            let client = try ChimloClient(timeout: .seconds(1))
            _ = try await client.sendEvent(event)
        } catch {
            // Observation is best-effort. Never turn a missing Chimlo process,
            // malformed hook, or local transport error into an agent failure.
        }
    }

    private static func makeEvent(options: Options) throws -> AgentEvent {
        if let json = options.value("json") {
            return try decodeEvent(Data(json.utf8))
        }
        if let path = options.value("file") {
            let data = path == "-"
                ? FileHandle.standardInput.readDataToEndOfFile()
                : try Data(contentsOf: URL(fileURLWithPath: path))
            return try decodeEvent(data)
        }

        let sessionID = try options.required("session")
        guard let sequence = Int(try options.required("sequence")), sequence >= 0 else {
            throw CLIError("--sequence must be a non-negative integer")
        }
        guard let kind = AgentEventKind(rawValue: try options.required("kind")) else {
            throw CLIError("--kind must be one of: \(eventKinds)")
        }
        guard let agent = AgentKind(rawValue: options.value("agent") ?? "other") else {
            throw CLIError("--agent must be one of: \(AgentKind.allCases.map(\.rawValue).joined(separator: ", "))")
        }

        let request = try makePendingRequest(kind: kind, options: options)
        let decision = try makeDecision(kind: kind, options: options)
        let jumpURL: URL?
        if let rawURL = options.value("jump-url") {
            guard let parsed = URL(string: rawURL), parsed.scheme != nil else {
                throw CLIError("--jump-url must be an absolute URL")
            }
            jumpURL = parsed
        } else {
            jumpURL = nil
        }

        return AgentEvent(
            sessionID: sessionID,
            sequence: sequence,
            kind: kind,
            agent: agent,
            title: options.value("title"),
            detail: options.value("detail"),
            model: options.value("model"),
            terminal: options.value("terminal"),
            projectPath: options.value("project"),
            jumpURL: jumpURL,
            request: request,
            decision: decision
        )
    }

    private static func makePendingRequest(kind: AgentEventKind, options: Options) throws -> PendingRequest? {
        switch kind {
        case .permissionRequested:
            let expiration = try parseDate(options.value("expires-at"))
            return .approval(
                ApprovalRequest(
                    id: try options.required("request-id"),
                    summary: try options.required("summary"),
                    detail: options.value("request-detail"),
                    expiresAt: expiration
                )
            )
        case .questionRequested:
            let choices = options.value("options")?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []
            return .question(
                AgentQuestion(
                    id: try options.required("request-id"),
                    prompt: try options.required("prompt"),
                    options: choices,
                    allowsFreeText: options.flag("allow-free-text"),
                    expiresAt: try parseDate(options.value("expires-at"))
                )
            )
        default:
            return nil
        }
    }

    private static func makeDecision(kind: AgentEventKind, options: Options) throws -> UserDecision? {
        guard kind == .permissionResolved || kind == .questionResolved else { return nil }
        if let answer = options.value("answer") { return .answer(answer) }
        guard let rawDecision = options.value("decision") else {
            throw CLIError("Resolved events require --decision allow|deny or --answer <text>")
        }
        switch rawDecision {
        case "allow": return .allow
        case "deny": return .deny
        default: throw CLIError("--decision must be 'allow' or 'deny'")
        }
    }

    private static func runDemo(options: Options) async throws {
        let client = try ChimloClient()
        let beats = DemoScript.make(start: Date())
        var previousOffset = 0

        for beat in beats {
            let delay = beat.offsetMilliseconds - previousOffset
            if delay > 0, !options.flag("instant") {
                try await Task.sleep(for: .milliseconds(delay))
            }
            _ = try await client.sendEvent(beat.event)
            print("demo \(beat.event.sequence)/\(beats.count): \(beat.event.kind.rawValue)")
            previousOffset = beat.offsetMilliseconds
        }
    }

    private static func requestDecision(options: Options) async throws {
        let timeoutSeconds = Int(options.value("timeout") ?? "60") ?? 0
        guard timeoutSeconds > 0, timeoutSeconds <= 600 else {
            throw CLIError("--timeout must be between 1 and 600 seconds")
        }

        let request = ChimloDecisionRequest(
            title: try options.required("title"),
            message: try options.required("message"),
            approveLabel: options.value("approve-label") ?? "Approve",
            denyLabel: options.value("deny-label") ?? "Deny",
            expiresAt: Date().addingTimeInterval(Double(timeoutSeconds))
        )
        let client = try ChimloClient(timeout: .seconds(timeoutSeconds + 2))
        let response = await client.requestDecision(request)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(response)
        print(String(decoding: data, as: UTF8.self))

        switch response.outcome {
        case .approved, .denied:
            return
        case .cancelled, .unavailable:
            throw CLIError(response.note ?? "No explicit decision returned")
        }
    }

    private static func decodeEvent(_ data: Data) throws -> AgentEvent {
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        if let event = try? isoDecoder.decode(AgentEvent.self, from: data) { return event }

        do {
            return try JSONDecoder().decode(AgentEvent.self, from: data)
        } catch {
            throw CLIError("Could not decode AgentEvent JSON: \(error.localizedDescription)")
        }
    }

    private static func parseDate(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw CLIError("Date must use ISO-8601, for example 2026-07-20T12:00:00Z")
        }
        return date
    }

    private static func writeError(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }

    private static let eventKinds = [
        "sessionStarted", "activity", "permissionRequested", "permissionResolved",
        "questionRequested", "questionResolved", "completed", "failed", "sessionEnded",
    ].joined(separator: ", ")

    private static let usage = """
    Usage:
      chimlo emit --session ID --sequence N --kind KIND [options]
      chimlo emit --json '{...}'
      chimlo emit --file event.json
      chimlo demo [--instant]
      chimlo ping
      chimlo decision --title TEXT --message TEXT [options]
      chimlo hook codex|claude observe < hook.json
      chimlo descriptor

    Common emit options:
      --agent NAME          claude, codex, gemini, cursor, opencode, hermes, other
      --title TEXT          Session title
      --detail TEXT         Current activity or result
      --model TEXT          Model name
      --terminal TEXT       Terminal or host label
      --project PATH        Project path
      --jump-url URL        Deep link back to the source

    Permission request options:
      --request-id ID --summary TEXT [--request-detail TEXT] [--expires-at ISO8601]

    Question request options:
      --request-id ID --prompt TEXT [--options 'one,two'] [--allow-free-text]

    Resolved event options:
      --decision allow|deny
      --answer TEXT

    Interactive decision options:
      --approve-label TEXT --deny-label TEXT --timeout SECONDS

    Set CHIMLO_RUNTIME_DESCRIPTOR to override the descriptor file used by the CLI.
    """
}

private struct Options {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                throw CLIError("Unexpected argument '\(argument)'")
            }
            let option = String(argument.dropFirst(2))
            if let equals = option.firstIndex(of: "=") {
                let key = String(option[..<equals])
                let value = String(option[option.index(after: equals)...])
                guard !key.isEmpty else { throw CLIError("Invalid empty option") }
                values[key] = value
                index += 1
            } else if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                values[option] = arguments[index + 1]
                index += 2
            } else {
                flags.insert(option)
                index += 1
            }
        }
    }

    func value(_ key: String) -> String? { values[key] }
    func flag(_ key: String) -> Bool { flags.contains(key) }

    func required(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else {
            throw CLIError("Missing required --\(key) option")
        }
        return value
    }
}

private struct CLIError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

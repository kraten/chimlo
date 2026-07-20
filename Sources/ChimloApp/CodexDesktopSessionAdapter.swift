import AppKit
import ChimloCore
import Foundation

private struct CodexDesktopThread: Sendable {
    let id: String
    let cwd: String
    let name: String?
    let ephemeral: Bool
    let updatedAt: Date
    let statusType: String
    let activeFlags: Set<String>

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty,
              let cwd = json["cwd"] as? String, !cwd.isEmpty else { return nil }
        self.id = id
        self.cwd = cwd
        name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        ephemeral = json["ephemeral"] as? Bool ?? false
        let timestamp = (json["updatedAt"] as? NSNumber)?.doubleValue
            ?? (json["createdAt"] as? NSNumber)?.doubleValue
        updatedAt = timestamp.map { Date(timeIntervalSince1970: $0) } ?? .now
        let status = json["status"] as? [String: Any]
        statusType = status?["type"] as? String ?? "idle"
        activeFlags = Set(status?["activeFlags"] as? [String] ?? [])
    }

    var candidate: SessionCandidate {
        let workspace = URL(fileURLWithPath: cwd).lastPathComponent
        let fallbackTitle = workspace.isEmpty ? "Codex session" : workspace
        let safeName = name.flatMap { $0.isEmpty ? nil : $0 }
        return SessionCandidate(
            id: id,
            agent: .codex,
            title: safeName ?? fallbackTitle,
            titleKind: safeName == nil ? .workspace : .task,
            detail: detail,
            projectPath: cwd,
            jumpURL: URL(string: "codex://threads/\(id)"),
            phase: phase,
            updatedAt: updatedAt,
            evidence: .codexAppServer
        )
    }

    private var phase: SessionPhase {
        switch statusType {
        case "active": .working
        case "systemError": .failed
        case "notLoaded" where updatedAt >= Date.now.addingTimeInterval(-90): .working
        default: .completed
        }
    }

    private var detail: String {
        if activeFlags.contains("waitingOnApproval") { return "Approval needed in Codex" }
        if activeFlags.contains("waitingOnUserInput") { return "Input needed in Codex" }
        switch statusType {
        case "active": return "Codex is working"
        case "systemError": return "Codex turn stopped"
        case "notLoaded" where updatedAt >= Date.now.addingTimeInterval(-90):
            return "Recent Codex activity"
        default: return "Codex is idle"
        }
    }
}

private enum CodexDesktopNotification: Sendable {
    case threadStarted(CodexDesktopThread)
    case statusChanged(id: String, type: String, flags: Set<String>)
    case threadClosed(String)
    case threadRenamed(id: String, name: String?)
    case turnStarted(String)
    case turnCompleted(id: String, status: String)
}

private enum CodexAppServerClientError: Error, LocalizedError {
    case unavailable
    case disconnected
    case malformedResponse
    case rpc(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "The Codex app-server executable is unavailable"
        case .disconnected: "The Codex app-server disconnected"
        case .malformedResponse: "The Codex app-server returned malformed data"
        case let .rpc(message): message
        }
    }
}

private final class CodexAppServerClient: @unchecked Sendable {
    typealias JSONObject = [String: Any]
    typealias Completion = @Sendable (Result<JSONObject, Error>) -> Void

    var onNotification: (@Sendable (CodexDesktopNotification) -> Void)?
    var onReady: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?

    private let executableURL: URL
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var readBuffer = Data()
    private var nextRequestID = 1
    private var pending: [Int: Completion] = [:]

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    func start() throws {
        guard process?.isRunning != true else { return }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CodexAppServerClientError.unavailable
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        input = stdin.fileHandleForWriting
        self.process = process

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.receive(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            self?.finishDisconnect()
        }

        try process.run()
        request(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "Chimlo",
                    "title": "Chimlo",
                    "version": "1.0.0",
                ],
                "capabilities": ["experimentalApi": false],
            ]
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                stop()
            case .success:
                sendNotification(method: "initialized", params: [:])
                synchronizeLoadedThreads()
            }
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        finishDisconnect()
    }

    private func synchronizeLoadedThreads() {
        request(method: "thread/loaded/list", params: [:]) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(object):
                let values = object["data"] as? [Any]
                    ?? object["threads"] as? [Any]
                    ?? []
                let objects = values.compactMap { $0 as? JSONObject }
                let identifiers = values.compactMap { $0 as? String }
                for object in objects {
                    if let thread = CodexDesktopThread(json: object), !thread.ephemeral {
                        onNotification?(.threadStarted(thread))
                    }
                }
                guard !identifiers.isEmpty else { return synchronizeRecentThreads() }
                readThreads(identifiers, index: 0)
            case .failure:
                // Older app-server builds may omit loaded/list. A bounded
                // thread/list request still recovers visible active/idle work.
                synchronizeRecentThreads()
            }
        }
    }

    private func readThreads(_ identifiers: [String], index: Int) {
        guard index < identifiers.count else {
            synchronizeRecentThreads()
            return
        }
        request(
            method: "thread/read",
            params: ["threadId": identifiers[index], "includeTurns": false]
        ) { [weak self] result in
            guard let self else { return }
            if case let .success(object) = result,
               let value = object["thread"] as? JSONObject,
               let thread = CodexDesktopThread(json: value),
               !thread.ephemeral {
                onNotification?(.threadStarted(thread))
            }
            readThreads(identifiers, index: index + 1)
        }
    }

    private func synchronizeRecentThreads() {
        request(
            method: "thread/list",
            params: [
                "limit": 40,
                "archived": false,
                "sortKey": "updated_at",
                "sortDirection": "desc",
            ]
        ) { [weak self] result in
            guard let self else { return }
            if case let .success(object) = result {
                let values = object["data"] as? [Any]
                    ?? object["threads"] as? [Any]
                    ?? []
                for value in values {
                    guard let object = value as? JSONObject,
                          let thread = CodexDesktopThread(json: object),
                          !thread.ephemeral,
                          thread.statusType != "notLoaded"
                            || thread.updatedAt >= Date.now.addingTimeInterval(-30 * 60) else { continue }
                    onNotification?(.threadStarted(thread))
                }
            }
            onReady?()
        }
    }

    private func request(method: String, params: JSONObject, completion: @escaping Completion) {
        let id: Int
        lock.lock()
        id = nextRequestID
        nextRequestID += 1
        pending[id] = completion
        lock.unlock()

        send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.timeout(requestID: id)
        }
    }

    private func sendNotification(method: String, params: JSONObject) {
        send(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func send(_ object: JSONObject) {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(UInt8(ascii: "\n"))
        lock.lock()
        let input = self.input
        lock.unlock()
        input?.write(data)
    }

    private func timeout(requestID: Int) {
        lock.lock()
        let completion = pending.removeValue(forKey: requestID)
        lock.unlock()
        completion?(.failure(CodexAppServerClientError.disconnected))
    }

    private func receive(_ data: Data) {
        lock.lock()
        readBuffer.append(data)
        var lines: [Data] = []
        while let index = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(Data(readBuffer.prefix(upTo: index)))
            readBuffer.removeSubrange(...index)
        }
        if readBuffer.count > 8 * 1_024 * 1_024 {
            readBuffer.removeAll(keepingCapacity: false)
        }
        lock.unlock()

        for line in lines where !line.isEmpty {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? JSONObject else { continue }
            if let id = (object["id"] as? NSNumber)?.intValue {
                handleResponse(id: id, object: object)
            } else if let method = object["method"] as? String,
                      let params = object["params"] as? JSONObject {
                handleNotification(method: method, params: params)
            }
        }
    }

    private func handleResponse(id: Int, object: JSONObject) {
        lock.lock()
        let completion = pending.removeValue(forKey: id)
        lock.unlock()
        guard let completion else { return }
        if let error = object["error"] as? JSONObject {
            completion(.failure(CodexAppServerClientError.rpc(
                error["message"] as? String ?? "Codex app-server request failed"
            )))
        } else if let result = object["result"] as? JSONObject {
            completion(.success(result))
        } else {
            completion(.failure(CodexAppServerClientError.malformedResponse))
        }
    }

    private func handleNotification(method: String, params: JSONObject) {
        switch method {
        case "thread/started":
            if let value = params["thread"] as? JSONObject,
               let thread = CodexDesktopThread(json: value), !thread.ephemeral {
                onNotification?(.threadStarted(thread))
            }
        case "thread/status/changed":
            guard let id = params["threadId"] as? String,
                  let status = params["status"] as? JSONObject else { return }
            onNotification?(.statusChanged(
                id: id,
                type: status["type"] as? String ?? "idle",
                flags: Set(status["activeFlags"] as? [String] ?? [])
            ))
        case "thread/closed":
            if let id = params["threadId"] as? String { onNotification?(.threadClosed(id)) }
        case "thread/name/updated":
            if let id = params["threadId"] as? String {
                onNotification?(.threadRenamed(id: id, name: params["name"] as? String))
            }
        case "turn/started":
            if let id = params["threadId"] as? String { onNotification?(.turnStarted(id)) }
        case "turn/completed":
            guard let id = params["threadId"] as? String else { return }
            let turn = params["turn"] as? JSONObject
            onNotification?(.turnCompleted(id: id, status: turn?["status"] as? String ?? "completed"))
        default:
            break
        }
    }

    private func finishDisconnect() {
        lock.lock()
        guard process != nil || input != nil else {
            lock.unlock()
            return
        }
        process = nil
        input = nil
        let completions = pending.values
        pending.removeAll()
        lock.unlock()
        for completion in completions {
            completion(.failure(CodexAppServerClientError.disconnected))
        }
        onDisconnected?()
    }
}

@MainActor
final class CodexDesktopSessionAdapter {
    var onCandidate: ((SessionCandidate) -> Void)?
    var onEvent: ((AgentEvent) -> Void)?
    var onSessionEnded: ((String) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?

    private var client: CodexAppServerClient?
    private var monitorTask: Task<Void, Never>?
    private var knownThreads: [String: SessionCandidate] = [:]

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.reconcileApplicationState()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        client?.stop()
        client = nil
        onConnectionChanged?(false)
    }

    private func reconcileApplicationState() {
        let running = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.openai.codex"
        }
        if running {
            connectIfNeeded()
        } else if client != nil {
            client?.stop()
            client = nil
            onConnectionChanged?(false)
        }
    }

    private func connectIfNeeded() {
        guard client == nil,
              let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex"
              ) else { return }
        let executableURL = appURL.appendingPathComponent("Contents/Resources/codex")
        let client = CodexAppServerClient(executableURL: executableURL)
        self.client = client
        client.onNotification = { [weak self] notification in
            Task { @MainActor [weak self] in self?.handle(notification) }
        }
        client.onReady = { [weak self] in
            Task { @MainActor [weak self] in self?.onConnectionChanged?(true) }
        }
        client.onDisconnected = { [weak self, weak client] in
            Task { @MainActor [weak self, weak client] in
                guard let self, self.client === client else { return }
                self.client = nil
                self.onConnectionChanged?(false)
            }
        }
        do {
            try client.start()
        } catch {
            self.client = nil
            onConnectionChanged?(false)
        }
    }

    private func handle(_ notification: CodexDesktopNotification) {
        switch notification {
        case let .threadStarted(thread):
            let candidate = thread.candidate
            knownThreads[candidate.id] = candidate
            onCandidate?(candidate)

        case let .statusChanged(id, type, flags):
            ensureThreadExists(id)
            if flags.contains("waitingOnApproval") {
                onEvent?(AgentEvent(
                    sessionID: id,
                    sequence: 0,
                    kind: .permissionRequested,
                    agent: .codex,
                    detail: "Approval needed in Codex",
                    request: .approval(.init(
                        id: "codex-app-approval-\(id)",
                        summary: "Continue in Codex"
                    ))
                ))
            } else if flags.contains("waitingOnUserInput") {
                onEvent?(AgentEvent(
                    sessionID: id,
                    sequence: 0,
                    kind: .questionRequested,
                    agent: .codex,
                    detail: "Input needed in Codex",
                    request: .question(.init(
                        id: "codex-app-input-\(id)",
                        prompt: "Continue in Codex"
                    ))
                ))
            } else {
                let kind: AgentEventKind = type == "systemError" ? .failed
                    : type == "active" ? .activity
                    : .completed
                onEvent?(AgentEvent(
                    sessionID: id,
                    sequence: 0,
                    kind: kind,
                    agent: .codex,
                    detail: type == "active" ? "Codex is working" : type == "systemError" ? "Codex turn stopped" : "Codex is idle"
                ))
            }

        case let .turnStarted(id):
            ensureThreadExists(id)
            onEvent?(AgentEvent(
                sessionID: id,
                sequence: 0,
                kind: .activity,
                agent: .codex,
                detail: "Codex is working"
            ))

        case let .turnCompleted(id, status):
            ensureThreadExists(id)
            onEvent?(AgentEvent(
                sessionID: id,
                sequence: 0,
                kind: status == "failed" ? .failed : .completed,
                agent: .codex,
                detail: status == "failed" ? "Codex turn stopped" : "Codex turn complete"
            ))

        case let .threadRenamed(id, name):
            guard var candidate = knownThreads[id],
                  let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return }
            candidate.title = name
            candidate.updatedAt = .now
            knownThreads[id] = candidate
            onCandidate?(candidate)

        case let .threadClosed(id):
            knownThreads.removeValue(forKey: id)
            onSessionEnded?(id)
        }
    }

    private func ensureThreadExists(_ id: String) {
        guard knownThreads[id] == nil else { return }
        let candidate = SessionCandidate(
            id: id,
            agent: .codex,
            title: "Codex session",
            detail: "Codex is active",
            jumpURL: URL(string: "codex://threads/\(id)"),
            phase: .working,
            updatedAt: .now,
            evidence: .codexAppServer
        )
        knownThreads[id] = candidate
        onCandidate?(candidate)
    }
}

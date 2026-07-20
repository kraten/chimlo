import AppKit
import ChimloCore
import ChimloProtocol
import Combine
import Foundation
import SwiftUI

struct SessionDisplayModel: Identifiable, Equatable, Sendable {
    let id: String
    var agentName: String
    var title: String
    var detail: String
    var mood: AvatarMood
    var startedAt: Date
    var isDemo: Bool
    var needsAttention: Bool
    var terminal: String?
    var projectPath: String?
    var jumpURL: URL?
    var model: String?

    var elapsedText: String {
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return "\(seconds / 3_600)h"
    }
}

enum PanelMode: Equatable, Sendable {
    case compact
    case sessions
    case onboarding
}

enum OnboardingStep: Equatable, Sendable {
    case welcome
    case working
    case permission
    case resolving(allowed: Bool)
    case complete(allowed: Bool)
}

@MainActor
final class ApplicationModel: ObservableObject {
    @Published private(set) var sessions: [SessionDisplayModel] = []
    @Published var panelMode: PanelMode = .compact
    @Published private(set) var onboardingStep: OnboardingStep = .welcome
    @Published private(set) var accessibility = AccessibilityEnvironment.current
    @Published private(set) var serverState: LocalServerState = .stopped
    @Published private(set) var pendingDecision: ChimloDecisionRequest?
    @Published private(set) var islandLayout: IslandLayout
    @Published private(set) var codexConnectionState: AgentConnectionState = .checking
    @Published private(set) var claudeConnectionState: AgentConnectionState = .checking
    @Published private(set) var isScanningSessions = true

    @Published var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.soundsEnabled) }
    }
    @Published var keepPreviewSession: Bool {
        didSet { defaults.set(keepPreviewSession, forKey: Keys.keepPreviewSession) }
    }

    private let defaults: UserDefaults
    private let chiptunePlayer = ChiptunePlayer()
    private var reducer = SessionReducer()
    private var demoSessionIDs: Set<String> = []
    private var previewSessionIDs: Set<String> = []
    private var deniedDemoSessionIDs: Set<String> = []
    private var hiddenSessionIDs: Set<String> = []
    private var onboardingSessionID: String?
    private var onboardingEvents: [AgentEvent] = []
    private var onboardingTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var pointerInsideIsland = false
    private var decisionExpiryTask: Task<Void, Never>?
    private var decisionContinuation: CheckedContinuation<ChimloDecisionResponse, Never>?
    private var protocolBridge: ProtocolBridge?
    private var hasStarted = false
    private lazy var integrationManager = AgentIntegrationManager.live()
    private let localSessionRuntime = LocalSessionRuntime()
    private let codexDesktopAdapter = CodexDesktopSessionAdapter()
    private var codexAppServerConnected = false
    private var sessionRemovalTasks: [String: Task<Void, Never>] = [:]

    var panelSize: CGSize {
        switch panelMode {
        case .compact:
            return CGSize(width: islandLayout.compactWidth, height: islandLayout.compactHeight)
        case .sessions:
            let rowHeight = sessions.isEmpty ? 62 : min(224, CGFloat(sessions.count) * 54)
            let decisionHeight: CGFloat = pendingDecision == nil ? 0 : 132
            let contentHeight = min(392, 38 + rowHeight + decisionHeight)
            return CGSize(width: 404, height: islandLayout.expandedContentTopInset + contentHeight)
        case .onboarding:
            return CGSize(width: 416, height: islandLayout.expandedContentTopInset + 364)
        }
    }

    var activeMood: AvatarMood {
        if pendingDecision != nil { return .waiting }
        if let attention = sessions.first(where: \.needsAttention) { return attention.mood }
        if let working = sessions.first(where: { $0.mood == .working }) { return working.mood }
        return sessions.first?.mood ?? .idle
    }

    var compactLabel: String {
        if pendingDecision != nil || sessions.contains(where: { $0.mood == .waiting }) { return "WAIT" }
        if sessions.contains(where: { $0.mood == .failed }) { return "STOP" }
        if sessions.contains(where: { $0.mood == .working }) { return "WORK" }
        if sessions.contains(where: { $0.mood == .success }) { return "DONE" }
        return "READY"
    }

    var serverStatusText: String {
        switch serverState {
        case .stopped:
            "Stopped"
        case .starting:
            "Starting local listener"
        case let .listening(port):
            "Listening locally on port \(port)"
        case .failed:
            "Local listener unavailable"
        }
    }

    var codexConnectionText: String {
        guard codexAppServerConnected else {
            return connectionText(for: .codex, state: codexConnectionState)
        }
        switch codexConnectionState {
        case .checking:
            return "Desktop live · checking observer"
        case .disconnected:
            return "Desktop live · observer optional"
        case .installedAwaitingEvent:
            return "Desktop live · observer awaiting event"
        case let .receiving(date):
            return "Desktop live · observer received \(date.formatted(.relative(presentation: .named)))"
        case .needsRepair:
            return "Desktop live · observer needs repair"
        case .unavailable:
            return "Desktop live · observer unavailable"
        }
    }

    var claudeConnectionText: String {
        connectionText(for: .claude, state: claudeConnectionState)
    }

    var hasInstalledAgent: Bool {
        codexConnectionState.isInstalled || claudeConnectionState.isInstalled || codexAppServerConnected
    }

    var isReceivingAgentEvents: Bool {
        codexConnectionState.isReceiving || claudeConnectionState.isReceiving || codexAppServerConnected
    }

    var connectionSummary: String {
        if isScanningSessions { return "scanning" }
        if isReceivingAgentEvents { return "live" }
        if hasInstalledAgent { return "awaiting event" }
        return "setup needed"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        islandLayout = IslandLayout.make(
            for: IslandDisplayMetrics(
                screenWidth: 0,
                screenHeight: 0,
                visibleTop: 0,
                safeTopInset: 0,
                cameraHousingLeftEdge: nil,
                cameraHousingRightEdge: nil
            )
        )
        soundsEnabled = defaults.object(forKey: Keys.soundsEnabled) as? Bool ?? true
        keepPreviewSession = defaults.object(forKey: Keys.keepPreviewSession) as? Bool ?? true
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        let bridge = ProtocolBridge()
        protocolBridge = bridge
        bridge.start(
            receive: { [weak self] event in
                self?.receiveLiveEvent(event)
            },
            decide: { [weak self] request in
                guard let self else {
                    return .unavailable(for: request.id, reason: "Chimlo is closing")
                }
                return await self.requestDecision(request)
            },
            stateChanged: { [weak self] state in
                self?.serverStateChanged(state)
            }
        )
        do {
            _ = try integrationManager.prepareStableHelper()
        } catch {
            codexConnectionState = .unavailable(error.localizedDescription)
            claudeConnectionState = .unavailable(error.localizedDescription)
        }
        configureSessionRuntime()
        localSessionRuntime.start()
        codexDesktopAdapter.start()
        refreshAgentConnections()

        if defaults.bool(forKey: Keys.completedOnboarding) {
            panelMode = .compact
        } else {
            replayOnboarding()
        }
    }

    func stop() {
        hasStarted = false
        onboardingTask?.cancel()
        collapseTask?.cancel()
        decisionExpiryTask?.cancel()
        finishPendingDecision(outcome: .unavailable, note: "Chimlo closed before a decision was made")
        protocolBridge?.stop()
        protocolBridge = nil
        localSessionRuntime.stop()
        codexDesktopAdapter.stop()
        for task in sessionRemovalTasks.values { task.cancel() }
        sessionRemovalTasks.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    func openPanel() {
        cancelCollapse()
        panelMode = .sessions
    }

    func pointerPresenceChanged(_ inside: Bool) {
        pointerInsideIsland = inside
        if inside {
            cancelCollapse()
            guard panelMode == .compact else { return }
            panelMode = .sessions
        } else {
            scheduleCollapseAfterHover()
        }
    }

    private func scheduleCollapseAfterHover() {
        guard hasStarted, IslandCollapsePolicy.shouldCollapse(
            pointerInside: pointerInsideIsland,
            isSessionPanel: panelMode == .sessions,
            hasBlockingDecision: pendingDecision != nil
        ) else { return }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, hasStarted,
                  IslandCollapsePolicy.shouldCollapse(
                    pointerInside: pointerInsideIsland,
                    isSessionPanel: panelMode == .sessions,
                    hasBlockingDecision: pendingDecision != nil
                  ) else { return }
            panelMode = .compact
            collapseTask = nil
        }
    }

    func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    func updateIslandLayout(_ layout: IslandLayout) {
        guard islandLayout != layout else { return }
        islandLayout = layout
    }

    func beginOnboardingDemo() {
        onboardingTask?.cancel()
        hideExistingDemoSessions()

        let sessionID = "chimlo-onboarding-\(UUID().uuidString.lowercased())"
        onboardingSessionID = sessionID
        demoSessionIDs.insert(sessionID)
        onboardingEvents = makeOnboardingEvents(sessionID: sessionID, start: .now)
        panelMode = .onboarding
        onboardingStep = .working

        guard onboardingEvents.count >= 3 else { return }
        consume(onboardingEvents[0], isDemo: true)

        onboardingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            consume(onboardingEvents[1], isDemo: true)

            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            consume(onboardingEvents[2], isDemo: true)
            onboardingStep = .permission
        }
    }

    func resolveDemoPermission(allowed: Bool) {
        guard onboardingStep == .permission,
              let sessionID = onboardingSessionID,
              let current = reducer.sessions[sessionID] else { return }

        onboardingTask?.cancel()
        onboardingStep = .resolving(allowed: allowed)
        if allowed {
            deniedDemoSessionIDs.remove(sessionID)
        } else {
            deniedDemoSessionIDs.insert(sessionID)
        }

        consume(
            AgentEvent(
                sessionID: sessionID,
                sequence: current.lastSequence + 1,
                kind: .permissionResolved,
                agent: current.agent,
                detail: allowed ? "Running three focused checks" : "Request denied safely",
                decision: allowed ? .allow : .deny,
                timestamp: .now
            ),
            isDemo: true
        )

        onboardingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self,
                  let latest = reducer.sessions[sessionID] else { return }

            consume(
                AgentEvent(
                    sessionID: sessionID,
                    sequence: latest.lastSequence + 1,
                    kind: .completed,
                    agent: latest.agent,
                    detail: allowed ? "Three focused checks passed" : "Nothing ran and nothing changed",
                    timestamp: .now
                ),
                isDemo: true
            )
            onboardingStep = .complete(allowed: allowed)
        }
    }

    func finishOnboarding() {
        defaults.set(true, forKey: Keys.completedOnboarding)
        panelMode = .sessions
        if sessions.isEmpty, keepPreviewSession, case .failed = serverState {
            installPreviewSession()
        }
    }

    func replayOnboarding() {
        onboardingTask?.cancel()
        hideExistingDemoSessions()
        onboardingSessionID = nil
        onboardingEvents = []
        panelMode = .onboarding
        onboardingStep = .welcome
    }

    func clearPreviewData() {
        hiddenSessionIDs.formUnion(demoSessionIDs)
        syncSessionProjections()
    }

    func previewSound() {
        chiptunePlayer.play(.success)
    }

    func refreshAgentConnections() {
        codexConnectionState = connectionState(for: .codex)
        claudeConnectionState = connectionState(for: .claude)
    }

    func refreshCodexConnection() {
        refreshAgentConnections()
    }

    func connectCodex() {
        connect(.codex)
    }

    func connectClaude() {
        connect(.claude)
    }

    func disconnectCodex() {
        disconnect(.codex)
    }

    func disconnectClaude() {
        disconnect(.claude)
    }

    private func connect(_ provider: AgentProvider) {
        do {
            let preview = try integrationManager.preview(for: provider)
            guard confirmConnection(provider: provider, preview: preview) else {
                refreshAgentConnections()
                return
            }
            try integrationManager.connect(provider)
            setConnectionState(.installedAwaitingEvent, for: provider)
        } catch {
            setConnectionState(.unavailable(error.localizedDescription), for: provider)
        }
    }

    private func disconnect(_ provider: AgentProvider) {
        do {
            try integrationManager.disconnect(provider)
            defaults.removeObject(forKey: receiptKey(for: provider))
            setConnectionState(.disconnected, for: provider)
        } catch {
            setConnectionState(.unavailable(error.localizedDescription), for: provider)
        }
    }

    private func confirmConnection(provider: AgentProvider, preview: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Connect \(provider.displayName) to Chimlo?"
        let filename = provider == .codex ? "hooks.json" : "settings.json"
        alert.informativeText = "Review the complete merged \(filename) below. Existing settings stay in place, and Chimlo keeps a one-time backup before writing."
        alert.addButton(withTitle: "Add observer")
        alert.addButton(withTitle: "Cancel")

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 250))
        textView.string = preview
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        let scrollView = NSScrollView(frame: textView.frame)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        alert.accessoryView = scrollView

        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func respondToPendingDecision(approved: Bool) {
        finishPendingDecision(outcome: approved ? .approved : .denied, note: nil)
    }

    func open(_ session: SessionDisplayModel) {
        guard let jumpURL = session.jumpURL else { return }
        NSWorkspace.shared.open(jumpURL)
    }

    private func receiveLiveEvent(_ event: AgentEvent) {
        hiddenSessionIDs.formUnion(previewSessionIDs)
        recordReceipt(for: event.agent)
        guard event.sequence == 0 else {
            consume(event, isDemo: false)
            if event.kind == .sessionEnded { scheduleSessionRemoval(event.sessionID) }
            return
        }

        // Hook helpers are short-lived and can run concurrently. Chimlo owns
        // their ordering so adapters need no shared counter or lock.
        if reducer.sessions[event.sessionID] == nil, event.kind != .sessionStarted {
            consume(
                AgentEvent(
                    sessionID: event.sessionID,
                    sequence: 1,
                    kind: .sessionStarted,
                    agent: event.agent,
                    title: event.title,
                    detail: "Connected locally",
                    model: event.model,
                    terminal: event.terminal,
                    projectPath: event.projectPath,
                    jumpURL: event.jumpURL,
                    timestamp: event.timestamp
                ),
                isDemo: false
            )
        }

        let nextSequence = (reducer.sessions[event.sessionID]?.lastSequence ?? 0) + 1
        consume(event.replacingSequence(with: nextSequence), isDemo: false)
        if event.kind == .sessionEnded {
            scheduleSessionRemoval(event.sessionID)
        }
    }

    private func consume(_ event: AgentEvent, isDemo: Bool) {
        if isDemo { demoSessionIDs.insert(event.sessionID) }
        let result = reducer.apply(event)
        guard case .applied = result else { return }
        syncSessionProjections()
        if !isDemo { localSessionRuntime.persist(reducer.orderedSessions) }

        if soundsEnabled {
            switch event.kind {
            case .sessionStarted:
                chiptunePlayer.play(.arrival)
            case .permissionRequested, .questionRequested, .failed:
                chiptunePlayer.play(.attention)
            case .completed:
                chiptunePlayer.play(.success)
            case .activity, .permissionResolved, .questionResolved, .sessionEnded:
                break
            }
        }

        if let session = reducer.sessions[event.sessionID],
           (session.pendingRequest != nil || session.phase == .failed),
           panelMode != .onboarding {
            cancelCollapse()
            panelMode = .sessions
            scheduleCollapseAfterHover()
        }
    }

    private func syncSessionProjections() {
        sessions = reducer.orderedSessions.compactMap { session in
            guard !hiddenSessionIDs.contains(session.id) else { return nil }
            let isDemo = demoSessionIDs.contains(session.id)
            return SessionDisplayModel(
                id: session.id,
                agentName: Self.agentName(session.agent),
                title: session.title,
                detail: session.detail,
                mood: mood(for: session),
                startedAt: session.startedAt,
                isDemo: isDemo,
                needsAttention: session.pendingRequest != nil || session.phase == .failed,
                terminal: session.terminal,
                projectPath: session.projectPath,
                jumpURL: session.jumpURL,
                model: session.model
            )
        }
    }

    private func configureSessionRuntime() {
        localSessionRuntime.onCandidate = { [weak self] candidate in
            self?.receive(candidate)
        }
        localSessionRuntime.onSessionEnded = { [weak self] sessionID in
            self?.removeSession(sessionID)
        }
        localSessionRuntime.onInitialScanCompleted = { [weak self] in
            self?.isScanningSessions = false
        }
        codexDesktopAdapter.onCandidate = { [weak self] candidate in
            guard let self else { return }
            codexAppServerConnected = true
            receive(candidate)
            refreshAgentConnections()
        }
        codexDesktopAdapter.onEvent = { [weak self] event in
            guard let self else { return }
            codexAppServerConnected = true
            receiveLiveEvent(event)
            refreshAgentConnections()
        }
        codexDesktopAdapter.onSessionEnded = { [weak self] sessionID in
            self?.removeSession(sessionID)
        }
        codexDesktopAdapter.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            codexAppServerConnected = connected
            refreshAgentConnections()
        }
    }

    private func receive(_ candidate: SessionCandidate) {
        hiddenSessionIDs.formUnion(previewSessionIDs)
        sessionRemovalTasks.removeValue(forKey: candidate.id)?.cancel()
        _ = reducer.merge(candidate)
        syncSessionProjections()
        localSessionRuntime.persist(reducer.orderedSessions)
    }

    private func removeSession(_ sessionID: String) {
        sessionRemovalTasks.removeValue(forKey: sessionID)?.cancel()
        guard reducer.remove(sessionID: sessionID) != nil else { return }
        syncSessionProjections()
        localSessionRuntime.persist(reducer.orderedSessions)
    }

    private func scheduleSessionRemoval(_ sessionID: String) {
        sessionRemovalTasks.removeValue(forKey: sessionID)?.cancel()
        sessionRemovalTasks[sessionID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.removeSession(sessionID)
        }
    }

    private func recordReceipt(for agent: AgentKind) {
        let provider: AgentProvider?
        switch agent {
        case .codex: provider = .codex
        case .claude: provider = .claude
        default: provider = nil
        }
        guard let provider else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: receiptKey(for: provider))
        refreshAgentConnections()
    }

    private func connectionState(for provider: AgentProvider) -> AgentConnectionState {
        let timestamp = defaults.double(forKey: receiptKey(for: provider))
        let receipt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        return integrationManager.status(for: provider, lastReceiptAt: receipt)
    }

    private func setConnectionState(_ state: AgentConnectionState, for provider: AgentProvider) {
        switch provider {
        case .codex: codexConnectionState = state
        case .claude: claudeConnectionState = state
        }
    }

    private func connectionText(for provider: AgentProvider, state: AgentConnectionState) -> String {
        switch state {
        case .checking:
            "Checking \(provider.displayName)"
        case .disconnected:
            "Not connected"
        case .installedAwaitingEvent:
            provider == .codex ? "Installed - confirm with /hooks" : "Installed - awaiting a session"
        case let .receiving(date):
            "Receiving - \(date.formatted(.relative(presentation: .named)))"
        case .needsRepair:
            "Observer needs repair"
        case let .unavailable(message):
            message
        }
    }

    private func receiptKey(for provider: AgentProvider) -> String {
        "chimlo.integration.\(provider.rawValue).lastReceipt"
    }

    private func mood(for session: AgentSession) -> AvatarMood {
        if previewSessionIDs.contains(session.id) || deniedDemoSessionIDs.contains(session.id) {
            return .idle
        }
        switch session.phase {
        case .working:
            return .working
        case .waitingForApproval, .waitingForAnswer:
            return .waiting
        case .completed:
            return .success
        case .failed:
            return .failed
        }
    }

    private func serverStateChanged(_ state: LocalServerState) {
        serverState = state
        if case .failed = state, keepPreviewSession, sessions.isEmpty,
           defaults.bool(forKey: Keys.completedOnboarding) {
            installPreviewSession()
        }
    }

    private func requestDecision(_ request: ChimloDecisionRequest) async -> ChimloDecisionResponse {
        if let expiresAt = request.expiresAt, expiresAt <= Date() {
            return .unavailable(for: request.id, reason: "Decision request expired")
        }
        guard pendingDecision == nil, decisionContinuation == nil else {
            return .unavailable(for: request.id, reason: "Another decision is already awaiting the owner")
        }

        return await withCheckedContinuation { continuation in
            cancelCollapse()
            pendingDecision = request
            decisionContinuation = continuation
            panelMode = .sessions
            scheduleDecisionExpiry(for: request)
        }
    }

    private func scheduleDecisionExpiry(for request: ChimloDecisionRequest) {
        decisionExpiryTask?.cancel()
        guard let expiresAt = request.expiresAt else { return }
        let nanoseconds = UInt64(max(0, expiresAt.timeIntervalSinceNow) * 1_000_000_000)
        decisionExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, self?.pendingDecision?.id == request.id else { return }
            self?.finishPendingDecision(outcome: .unavailable, note: "Decision request expired")
        }
    }

    private func finishPendingDecision(outcome: ChimloDecisionOutcome, note: String?) {
        guard let request = pendingDecision else { return }
        decisionExpiryTask?.cancel()
        decisionExpiryTask = nil
        let continuation = decisionContinuation
        decisionContinuation = nil
        pendingDecision = nil
        continuation?.resume(
            returning: ChimloDecisionResponse(
                requestID: request.id,
                outcome: outcome,
                note: note
            )
        )
        scheduleCollapseAfterHover()
    }

    private func installPreviewSession() {
        guard !sessions.contains(where: \.isDemo) else { return }
        let sessionID = "chimlo-listener-preview-\(UUID().uuidString.lowercased())"
        previewSessionIDs.insert(sessionID)
        demoSessionIDs.insert(sessionID)
        consume(
            AgentEvent(
                sessionID: sessionID,
                sequence: 1,
                kind: .sessionStarted,
                agent: .other,
                title: "Local listener preview",
                detail: "Waiting for the local server to become available",
                timestamp: .now
            ),
            isDemo: true
        )
    }

    private func hideExistingDemoSessions() {
        hiddenSessionIDs.formUnion(demoSessionIDs)
        syncSessionProjections()
    }

    private func makeOnboardingEvents(sessionID: String, start: Date) -> [AgentEvent] {
        DemoScript.make(start: start).map { beat in
            let event = beat.event
            return AgentEvent(
                id: UUID(),
                sessionID: sessionID,
                sequence: event.sequence,
                kind: event.kind,
                agent: event.agent,
                title: event.title,
                detail: event.detail,
                model: event.model,
                terminal: event.terminal,
                projectPath: event.projectPath,
                jumpURL: event.jumpURL,
                request: event.request,
                decision: event.decision,
                timestamp: start.addingTimeInterval(Double(beat.offsetMilliseconds) / 1_000)
            )
        }
    }

    private static func agentName(_ agent: AgentKind) -> String {
        switch agent {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .cursor: "Cursor"
        case .openCode: "OpenCode"
        case .hermes: "Hermes"
        case .other: "Local agent"
        }
    }

    @objc private func accessibilityOptionsChanged() {
        accessibility = .current
    }

    private enum Keys {
        static let completedOnboarding = "chimlo.onboarding.completed"
        static let soundsEnabled = "chimlo.sound.enabled"
        static let keepPreviewSession = "chimlo.preview.keepSession"
    }
}

private extension AgentEvent {
    func replacingSequence(with sequence: Int) -> AgentEvent {
        AgentEvent(
            id: id,
            sessionID: sessionID,
            sequence: sequence,
            kind: kind,
            agent: agent,
            title: title,
            detail: detail,
            model: model,
            terminal: terminal,
            projectPath: projectPath,
            jumpURL: jumpURL,
            request: request,
            decision: decision,
            timestamp: timestamp
        )
    }
}

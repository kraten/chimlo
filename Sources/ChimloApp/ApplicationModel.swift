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
    var isDemo: Bool
    var needsAttention: Bool
    var terminal: String?
    var projectPath: String?
    var jumpURL: URL?
    var model: String?
    var latestUserPrompt: String?
    var latestAgentResponse: String?
    var latestResponseReceivedAt: Date?

    var displayTitle: String {
        guard let projectPath else { return title }
        let workspace = URL(fileURLWithPath: projectPath).lastPathComponent
        guard !workspace.isEmpty,
              title.localizedCaseInsensitiveCompare(workspace) != .orderedSame,
              !title.localizedCaseInsensitiveContains("\(workspace) ·") else {
            return title
        }
        return "\(workspace) · \(title)"
    }

    var showsCompletedConversation: Bool {
        guard let latestResponseReceivedAt else { return false }
        return mood == .success
            && latestUserPrompt != nil
            && latestAgentResponse != nil
            && latestResponseReceivedAt >= Date.now.addingTimeInterval(
                -IslandCollapsePolicy.completionDetailLifetimeSeconds
            )
    }

    func preferredRowHeight(responseTextWidth: CGFloat) -> CGFloat {
        guard showsCompletedConversation,
              let latestUserPrompt,
              let latestAgentResponse else { return 70 }

        let promptFont = NSFont.systemFont(ofSize: 11, weight: .medium)
        let promptLabelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let doneFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let promptFixedWidth = ("You:" as NSString).size(withAttributes: [.font: promptLabelFont]).width
            + ("Done" as NSString).size(withAttributes: [.font: doneFont]).width
            + 26
        let promptTextWidth = max(1, responseTextWidth - promptFixedWidth)
        let promptLineHeight = ceil(promptFont.ascender - promptFont.descender + promptFont.leading)
        let promptLineCount = measuredLineCount(
            latestUserPrompt,
            font: promptFont,
            width: promptTextWidth,
            maximum: 2
        )
        let promptHeight = CGFloat(promptLineCount) * promptLineHeight + 20

        let responseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let responseLineHeight = ceil(
            responseFont.ascender - responseFont.descender + responseFont.leading
        )
        let responseLineCount = measuredLineCount(
            latestAgentResponse,
            font: responseFont,
            width: responseTextWidth,
            maximum: 6
        )
        let responseHeight = CGFloat(responseLineCount) * responseLineHeight
            + CGFloat(responseLineCount - 1) * 2
            + 20

        return 70 + 8 + promptHeight + responseHeight
    }

    private func measuredLineCount(
        _ text: String,
        font: NSFont,
        width: CGFloat,
        maximum: Int
    ) -> Int {
        let lineHeight = max(1, ceil(font.ascender - font.descender + font.leading))
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: max(1, width), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(maximum, max(1, Int(ceil(bounds.height / lineHeight))))
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
    private var archivedSessionMarkers: [String: SessionArchiveMarker]
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
    private var sessionsArmedForCompletion: Set<String> = []
    private var latestResponseReceivedAt: [String: Date] = [:]
    private var completionDetailExpiryTasks: [String: Task<Void, Never>] = [:]
    private var lastPresentedResponse: [String: String] = [:]

    var panelSize: CGSize {
        switch panelMode {
        case .compact:
            return CGSize(width: islandLayout.compactWidth, height: islandLayout.compactHeight)
        case .sessions:
            let responseTextWidth = max(1, islandLayout.expandedWidth - 56)
            let rowsHeight = sessions.reduce(CGFloat.zero) { partial, session in
                partial + session.preferredRowHeight(responseTextWidth: responseTextWidth)
            }
            let rowSpacing = CGFloat(max(0, sessions.count - 1)) * 6
            let rowHeight = sessions.isEmpty ? 62 : min(320, rowsHeight + rowSpacing)
            let decisionHeight: CGFloat = pendingDecision == nil ? 0 : 132
            let contentHeight = min(366, 12 + rowHeight + decisionHeight)
            return CGSize(
                width: islandLayout.expandedWidth,
                height: islandLayout.expandedContentTopInset + contentHeight
            )
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
        archivedSessionMarkers = Self.loadArchivedSessionMarkers(from: defaults)
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
        for task in completionDetailExpiryTasks.values { task.cancel() }
        completionDetailExpiryTasks.removeAll()
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

    private func scheduleCollapseAfterHover(
        delayMilliseconds: Int = IslandCollapsePolicy.hoverDelayMilliseconds
    ) {
        guard hasStarted, IslandCollapsePolicy.shouldCollapse(
            pointerInside: pointerInsideIsland,
            isSessionPanel: panelMode == .sessions,
            hasBlockingDecision: pendingDecision != nil
        ) else { return }
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
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

    func archiveSession(_ session: SessionDisplayModel) {
        guard !session.isDemo,
              let source = reducer.sessions[session.id],
              source.pendingRequest == nil else { return }

        archivedSessionMarkers[session.id] = SessionArchiveMarker()
        persistArchivedSessionMarkers()
        syncSessionProjections()
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
        let wasArmedForCompletion = sessionsArmedForCompletion.contains(event.sessionID)
        let result = reducer.apply(event)
        guard case .applied = result else { return }
        if !isDemo { restoreArchivedSessionIfNeeded(for: event) }
        let isNewCompletion = IslandCollapsePolicy.isNewCompletion(
            wasArmedForCompletion: wasArmedForCompletion,
            eventKind: event.kind
        )
        var completionReceivedAt: Date?
        if isNewCompletion,
           reducer.sessions[event.sessionID]?.latestAgentResponse != nil {
            let receivedAt = latestResponseReceivedAt[event.sessionID] ?? .now
            recordLatestResponse(for: event.sessionID, receivedAt: receivedAt)
            completionReceivedAt = receivedAt
        }
        updateCompletionArm(for: event)
        syncSessionProjections()
        if !isDemo { localSessionRuntime.persist(reducer.orderedSessions) }

        let presentsCompletion = completionReceivedAt.map {
            presentCompletionIfNeeded(sessionID: event.sessionID, receivedAt: $0)
        } ?? false

        if soundsEnabled {
            switch event.kind {
            case .sessionStarted:
                chiptunePlayer.play(.arrival)
            case .permissionRequested, .questionRequested, .failed:
                chiptunePlayer.play(.attention)
            case .activity, .permissionResolved, .questionResolved, .completed, .sessionEnded:
                break
            }
        }

        if presentsCompletion {
            scheduleCollapseAfterHover(
                delayMilliseconds: IslandCollapsePolicy.completionHoldMilliseconds
            )
            return
        }

        if let session = reducer.sessions[event.sessionID],
           (session.pendingRequest != nil || session.phase == .failed),
           panelMode != .onboarding {
            cancelCollapse()
            panelMode = .sessions
            scheduleCollapseAfterHover()
        }
    }

    private func updateCompletionArm(for event: AgentEvent) {
        switch event.kind {
        case .sessionStarted, .activity, .permissionResolved, .questionResolved:
            sessionsArmedForCompletion.insert(event.sessionID)
            lastPresentedResponse.removeValue(forKey: event.sessionID)
        case .completed, .failed, .sessionEnded:
            sessionsArmedForCompletion.remove(event.sessionID)
        case .permissionRequested, .questionRequested:
            break
        }
    }

    private func recordLatestResponse(for sessionID: String, receivedAt: Date) {
        let observedAt = min(receivedAt, .now)
        let lifetime = IslandCollapsePolicy.completionDetailLifetimeSeconds
        guard observedAt >= Date.now.addingTimeInterval(-lifetime) else { return }
        if let current = latestResponseReceivedAt[sessionID], current > observedAt { return }

        latestResponseReceivedAt[sessionID] = observedAt
        completionDetailExpiryTasks.removeValue(forKey: sessionID)?.cancel()

        let remainingSeconds = max(0, observedAt.addingTimeInterval(lifetime).timeIntervalSinceNow)
        let nanoseconds = UInt64(remainingSeconds * 1_000_000_000)
        completionDetailExpiryTasks[sessionID] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self,
                  latestResponseReceivedAt[sessionID] == observedAt else { return }
            latestResponseReceivedAt.removeValue(forKey: sessionID)
            completionDetailExpiryTasks.removeValue(forKey: sessionID)
            syncSessionProjections()
        }
    }

    @discardableResult
    private func presentCompletionIfNeeded(sessionID: String, receivedAt: Date) -> Bool {
        guard panelMode != .onboarding,
              receivedAt >= Date.now.addingTimeInterval(
                -IslandCollapsePolicy.completionDetailLifetimeSeconds
              ),
              let response = reducer.sessions[sessionID]?.latestAgentResponse,
              lastPresentedResponse[sessionID] != response else { return false }

        lastPresentedResponse[sessionID] = response
        cancelCollapse()
        panelMode = .sessions
        if soundsEnabled { chiptunePlayer.play(.success) }
        return true
    }

    private func syncSessionProjections() {
        sessions = reducer.orderedSessions.compactMap { session in
            guard !hiddenSessionIDs.contains(session.id),
                  archivedSessionMarkers[session.id] == nil else { return nil }
            let isDemo = demoSessionIDs.contains(session.id)
            return SessionDisplayModel(
                id: session.id,
                agentName: Self.agentName(session.agent),
                title: session.title,
                detail: session.detail,
                mood: mood(for: session),
                isDemo: isDemo,
                needsAttention: session.pendingRequest != nil || session.phase == .failed,
                terminal: session.terminal,
                projectPath: session.projectPath,
                jumpURL: session.jumpURL,
                model: session.model,
                latestUserPrompt: session.latestUserPrompt,
                latestAgentResponse: session.latestAgentResponse,
                latestResponseReceivedAt: latestResponseReceivedAt[session.id]
            )
        }
    }

    private func configureSessionRuntime() {
        localSessionRuntime.onCandidate = { [weak self] candidate in
            self?.receive(candidate)
        }
        localSessionRuntime.onSessionEnded = { [weak self] sessionID in
            self?.scheduleSessionRemoval(sessionID)
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
            self?.scheduleSessionRemoval(sessionID)
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
        restoreArchivedSessionIfNeeded(for: candidate)
        let previous = reducer.sessions[candidate.id]
        let merged = reducer.merge(candidate)
        let hasNewResponse = candidate.latestAgentResponse != nil
            && candidate.latestAgentResponse != previous?.latestAgentResponse

        if merged.phase == .working, previous?.phase != .working {
            lastPresentedResponse.removeValue(forKey: candidate.id)
        }
        if hasNewResponse,
           candidate.updatedAt >= Date.now.addingTimeInterval(
            -IslandCollapsePolicy.completionDetailLifetimeSeconds
           ) {
            recordLatestResponse(for: candidate.id, receivedAt: .now)
        }

        let presentsCompletion = merged.phase == .completed
            && merged.latestAgentResponse != nil
            && (previous?.phase != .completed || hasNewResponse)
        syncSessionProjections()
        localSessionRuntime.persist(reducer.orderedSessions)

        if presentsCompletion,
           presentCompletionIfNeeded(
            sessionID: candidate.id,
            receivedAt: latestResponseReceivedAt[candidate.id] ?? candidate.updatedAt
           ) {
            scheduleCollapseAfterHover(
                delayMilliseconds: IslandCollapsePolicy.completionHoldMilliseconds
            )
        }
    }

    private func removeSession(_ sessionID: String) {
        sessionRemovalTasks.removeValue(forKey: sessionID)?.cancel()
        completionDetailExpiryTasks.removeValue(forKey: sessionID)?.cancel()
        sessionsArmedForCompletion.remove(sessionID)
        latestResponseReceivedAt.removeValue(forKey: sessionID)
        lastPresentedResponse.removeValue(forKey: sessionID)
        if archivedSessionMarkers.removeValue(forKey: sessionID) != nil {
            persistArchivedSessionMarkers()
        }
        guard reducer.remove(sessionID: sessionID) != nil else { return }
        syncSessionProjections()
        localSessionRuntime.persist(reducer.orderedSessions)
    }

    private func scheduleSessionRemoval(_ sessionID: String) {
        sessionRemovalTasks.removeValue(forKey: sessionID)?.cancel()
        let recentResponseDelay = latestResponseReceivedAt[sessionID].map { receivedAt in
            max(
                0,
                receivedAt.addingTimeInterval(
                    IslandCollapsePolicy.completionDetailLifetimeSeconds
                ).timeIntervalSinceNow
            )
        } ?? 0
        let delayMilliseconds = Int(ceil(max(4, recentResponseDelay) * 1_000))
        sessionRemovalTasks[sessionID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
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

    private func restoreArchivedSessionIfNeeded(for candidate: SessionCandidate) {
        guard let marker = archivedSessionMarkers[candidate.id],
              marker.shouldRestore(for: candidate) else { return }
        archivedSessionMarkers.removeValue(forKey: candidate.id)
        persistArchivedSessionMarkers()
    }

    private func restoreArchivedSessionIfNeeded(for event: AgentEvent) {
        guard let marker = archivedSessionMarkers[event.sessionID],
              marker.shouldRestore(for: event) else { return }
        archivedSessionMarkers.removeValue(forKey: event.sessionID)
        persistArchivedSessionMarkers()
    }

    private func persistArchivedSessionMarkers() {
        let values = archivedSessionMarkers.mapValues { $0.archivedAt.timeIntervalSince1970 }
        defaults.set(values, forKey: Keys.archivedSessions)
    }

    private static func loadArchivedSessionMarkers(
        from defaults: UserDefaults
    ) -> [String: SessionArchiveMarker] {
        guard let stored = defaults.dictionary(forKey: Keys.archivedSessions) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            guard let timestamp = entry.value as? NSNumber else { return }
            result[entry.key] = SessionArchiveMarker(
                archivedAt: Date(timeIntervalSince1970: timestamp.doubleValue)
            )
        }
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
        static let archivedSessions = "chimlo.sessions.archived"
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

import ChimloCore
import ChimloProtocol
import Darwin
import Foundation

@main
enum ChimloChecks {
    static func main() async {
        if CommandLine.arguments.contains("--watch-transition") {
            await LiveWindowTransitionCheck.run()
            return
        }
        var suite = CheckSuite()
        if CommandLine.arguments.contains("--session-discovery-retention-only") {
            suite.runSessionDiscoveryRetentionOnly()
        } else if CommandLine.arguments.contains("--session-list-layout-only") {
            suite.runSessionListLayoutOnly()
        } else if CommandLine.arguments.contains("--session-visibility-only") {
            suite.runSessionVisibilityOnly()
        } else if CommandLine.arguments.contains("--layout-only") {
            suite.runLayoutOnly()
        } else {
            await suite.run()
        }
        if suite.failures.isEmpty {
            print("\nAll \(suite.passes) Chimlo checks passed.")
        } else {
            FileHandle.standardError.write(
                Data("\n\(suite.failures.count) check(s) failed:\n\(suite.failures.joined(separator: "\n"))\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    }
}

private struct CheckSuite {
    private(set) var passes = 0
    private(set) var failures: [String] = []

    mutating func run() async {
        notchLayout()
        sessionListLayout()
        systemFeedback()
        hookPrivacyMapping()
        transcriptMetadataPrivacy()
        modelDisplayNames()
        sessionRelativeTime()
        sessionDiscoveryRetention()
        sessionVisibility()
        sessionArchiveVisibility()
        codexHookConfiguration()
        claudeHookConfiguration()
        coreLifecycle()
        coreOrderingAndDeduplication()
        candidateMergePreservesActionableState()
        frameRoundTripAndBounds()
        descriptorPermissions()
        await networkRoundTrip()
        await decisionFailureIsClosed()
    }

    mutating func runLayoutOnly() {
        notchLayout()
        systemFeedback()
    }

    mutating func runSessionVisibilityOnly() {
        sessionVisibility()
    }

    mutating func runSessionListLayoutOnly() {
        sessionListLayout()
    }

    mutating func runSessionDiscoveryRetentionOnly() {
        sessionDiscoveryRetention()
    }

    mutating func sessionListLayout() {
        let focusedHeight = SessionListLayout.contentHeight(
            displayedRowHeights: [420],
            hasSessions: true,
            hasDecision: false,
            showsDisclosureControl: true,
            isDisclosureContextActive: true
        )
        let revealedHeight = SessionListLayout.contentHeight(
            displayedRowHeights: [420, 70, 70, 70, 70],
            hasSessions: true,
            hasDecision: false,
            showsDisclosureControl: false,
            isDisclosureContextActive: true
        )
        expect(
            revealedHeight == focusedHeight,
            "revealing hidden sessions keeps the scroll viewport stable"
        )
        expect(
            SessionListLayout.contentHeight(
                displayedRowHeights: [70, 70],
                hasSessions: true,
                hasDecision: false,
                showsDisclosureControl: false,
                isDisclosureContextActive: true
            ) == 158,
            "a short revealed list does not reserve empty disclosure space"
        )
    }

    mutating func systemFeedback() {
        let volume = SystemFeedbackPresentation(
            kind: .outputVolume,
            value: 0.5
        )
        expect(volume.percentage == 50, "system feedback exposes an exact percentage")
        expect(
            volume.accessibilityDescription == "Output volume 50 percent",
            "system feedback announces the exact percentage"
        )
        expect(
            SystemFeedbackPolicy.meterFillWidth(for: volume.value, trackWidth: 23) == 11.5,
            "system feedback fills the pixel meter to the exact value"
        )
        expect(
            SystemFeedbackPolicy.adjustedValue(from: 0.5, direction: 1, fine: false) == 0.5625,
            "system feedback uses native-sized coarse steps"
        )
    }

    mutating func sessionRelativeTime() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let label: (TimeInterval) -> String = { secondsAgo in
            SessionRelativeTime.shortLabel(
                since: now.addingTimeInterval(-secondsAgo),
                now: now
            )
        }

        expect(label(59) == "<1m", "fresh sessions show the first-minute badge")
        expect(label(60) == "1m", "session age advances to whole minutes")
        expect(label(3_600) == "1h", "session age advances to whole hours")
        expect(label(86_400) == "1d", "session age advances to whole days")
        expect(label(604_800) == "1w", "session age advances to whole weeks")
        expect(label(-10) == "<1m", "future clock skew stays in the first-minute bucket")
        expect(
            SessionRelativeTime.accessibilityLabel(
                since: now.addingTimeInterval(-2 * 3_600),
                now: now
            ) == "Session activity updated 2 hours ago",
            "session age exposes a spoken accessibility label"
        )
    }

    mutating func sessionDiscoveryRetention() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        expect(
            SessionDiscoveryRetentionPolicy.shouldRetain(
                phase: .completed,
                updatedAt: now.addingTimeInterval(-119 * 60),
                hasActiveProcess: false,
                hasLastResponse: true,
                now: now
            ),
            "a response-backed session remains visible inside two hours"
        )
        expect(
            !SessionVisibilityPolicy.wasActiveRecently(
                updatedAt: now.addingTimeInterval(-2 * 60 * 60),
                now: now
            ) && !SessionDiscoveryRetentionPolicy.shouldRetain(
                phase: .completed,
                updatedAt: now.addingTimeInterval(-2 * 60 * 60),
                hasActiveProcess: false,
                hasLastResponse: true,
                now: now
            ),
            "sessions expire at the two-hour activity boundary"
        )
        expect(
            !SessionDiscoveryRetentionPolicy.shouldRetain(
                phase: .completed,
                updatedAt: now.addingTimeInterval(-24 * 60),
                hasActiveProcess: false,
                hasLastResponse: false,
                now: now
            ),
            "a metadata-only completion retains the short cleanup window"
        )
    }

    mutating func notchLayout() {
        let display = IslandDisplayMetrics(
            screenWidth: 1_728,
            screenHeight: 1_117,
            visibleTop: 1_084,
            safeTopInset: 32,
            cameraHousingLeftEdge: 771,
            cameraHousingRightEdge: 956
        )
        let layout = IslandLayout.make(for: display)

        expect(layout.compactHeight == 32, "compact island fits the notch height")
        expect(layout.compactWidth == 249, "compact island provides two 32-point activity wings")
        expect(
            abs(layout.expandedWidth - 518.4) < 0.01,
            "expanded island uses three-tenths of the display width"
        )
        expect(layout.expandedContentTopInset == 32, "expanded content clears the camera housing")
        expect(layout.expandedNeckWidth == 249, "expanded panel grows from the compact notch neck")
        expect(layout.cameraHousingWidth == 185, "compact center matches the physical camera housing")
        expect(layout.activityWingWidth == 32, "compact activity wings remain symmetric")
        expect(
            layout.activityWingWidth >= 23,
            "compact activity wings fully contain the system feedback meter"
        )

        let expandedSilhouette = ExpandedIslandSilhouette(
            width: layout.expandedWidth
        )
        expect(
            expandedSilhouette.topLeftX == 0
                && expandedSilhouette.topRightX == layout.expandedWidth
                && expandedSilhouette.topY == 0,
            "expanded surface covers its full width from the camera band"
        )

        expect(
            IslandCollapsePolicy.shouldCollapse(
                pointerInside: false,
                isSessionPanel: true,
                hasBlockingDecision: false
            ),
            "outside session panel collapses"
        )
        expect(
            !IslandCollapsePolicy.shouldCollapse(
                pointerInside: true,
                isSessionPanel: true,
                hasBlockingDecision: false
            ),
            "re-entry cancels collapse"
        )
        expect(
            !IslandCollapsePolicy.shouldCollapse(
                pointerInside: false,
                isSessionPanel: true,
                hasBlockingDecision: true
            ),
            "blocking decision pins the expanded panel"
        )
        expect(
            !IslandCollapsePolicy.shouldCollapse(
                pointerInside: false,
                isSessionPanel: false,
                hasBlockingDecision: false
            ),
            "onboarding and compact modes never auto-collapse"
        )
        expect(
            IslandCollapsePolicy.isNewCompletion(
                wasArmedForCompletion: true,
                eventKind: .completed
            ),
            "working to completed presents the completion panel"
        )
        expect(
            !IslandCollapsePolicy.isNewCompletion(
                wasArmedForCompletion: false,
                eventKind: .completed
            ),
            "repeated completion does not replay feedback"
        )
        expect(
            IslandCollapsePolicy.completionHoldMilliseconds
                > IslandCollapsePolicy.hoverDelayMilliseconds,
            "completion remains readable longer than hover expansion"
        )
    }

    mutating func hookPrivacyMapping() {
        let payload = Data(
            #"{"session_id":"codex-local-1","hook_event_name":"PermissionRequest","cwd":"/Users/example/Projects/chimlo","model":"gpt-local","tool_name":"Bash","prompt":"DO NOT RETAIN THIS PROMPT","transcript_path":"/private/secret/transcript.jsonl","tool_input":{"command":"DO NOT RETAIN THIS COMMAND"}}"#.utf8
        )

        do {
            let event = try PrivacySafeHookMapper.event(
                from: payload,
                source: .codex,
                timestamp: Date(timeIntervalSince1970: 1_785_000_000)
            )
            expect(event?.kind == .permissionRequested, "Codex permission hook maps to waiting state")
            expect(event?.sequence == 0, "provider hook sequencing is delegated to Chimlo")
            expect(event?.title == "chimlo", "hook exposes only the local project basename")

            let encoded = event.flatMap { try? JSONEncoder().encode($0) }
                .map { String(decoding: $0, as: UTF8.self) } ?? ""
            expect(!encoded.contains("DO NOT RETAIN"), "hook discards prompt and tool contents")
            expect(!encoded.contains("transcript.jsonl"), "hook discards transcript paths")
        } catch {
            failures.append("FAIL  privacy-safe hook mapping: \(error)")
        }
    }

    mutating func sessionArchiveVisibility() {
        let archivedAt = Date(timeIntervalSince1970: 1_000)
        let marker = SessionArchiveMarker(archivedAt: archivedAt)
        let stale = SessionCandidate(
            id: "archive-check",
            agent: .codex,
            title: "Archive check",
            detail: "Working",
            latestUserPrompt: "Same message",
            latestConversationUpdatedAt: archivedAt,
            phase: .working,
            updatedAt: archivedAt,
            evidence: .codexRollout
        )
        var newer = stale
        newer.latestConversationUpdatedAt = archivedAt.addingTimeInterval(1)

        expect(!marker.shouldRestore(for: stale), "archive ignores the conversation already shown")
        expect(marker.shouldRestore(for: newer), "a newer message restores an archived session")
        expect(
            !marker.shouldRestore(for: AgentEvent(
                sessionID: stale.id,
                sequence: 1,
                kind: .activity,
                agent: .codex,
                timestamp: archivedAt.addingTimeInterval(1)
            )),
            "tool activity does not restore an archived session"
        )
        expect(
            !marker.shouldRestore(for: AgentEvent(
                sessionID: stale.id,
                sequence: 2,
                kind: .sessionStarted,
                agent: .codex,
                timestamp: archivedAt.addingTimeInterval(1)
            )),
            "a lifecycle restart does not restore an archived session"
        )
        expect(
            marker.shouldRestore(for: AgentEvent(
                sessionID: stale.id,
                sequence: 3,
                kind: .permissionRequested,
                agent: .codex,
                timestamp: archivedAt.addingTimeInterval(1)
            )),
            "an approval request restores an archived session"
        )
    }

    mutating func codexHookConfiguration() {
        let helperPath = "/Users/example/Library/Application Support/Chimlo/bin/chimlo"
        let existing = Data(
            #"{"description":"keep","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"existing-observer"}]}],"Unrelated":[{"hooks":[{"type":"command","command":"leave-this-alone"}]}]}}"#.utf8
        )

        do {
            let merged = try CodexHookConfiguration.merging(
                existingData: existing,
                helperPath: helperPath
            )
            expect(merged.changed, "Codex observer merge reports a change")
            let installedState = try CodexHookConfiguration.installationState(
                in: merged.data,
                helperPath: helperPath
            )
            expect(
                installedState == .current,
                "Codex observer merge covers every activity event"
            )
            let mergedText = String(decoding: merged.data, as: UTF8.self)
            expect(mergedText.contains("leave-this-alone"), "Codex observer merge preserves unrelated hooks")

            let repeated = try CodexHookConfiguration.merging(
                existingData: merged.data,
                helperPath: helperPath
            )
            expect(!repeated.changed && repeated.data == merged.data, "Codex observer merge is idempotent")

            let movedState = try CodexHookConfiguration.installationState(
                in: merged.data,
                helperPath: "/tmp/Moved Chimlo.app/Contents/Helpers/chimlo"
            )
            expect(movedState == .needsRepair, "a moved Chimlo app is reported for repair")

            let removed = try CodexHookConfiguration.removing(existingData: merged.data)
            let removedText = String(decoding: removed.data, as: UTF8.self)
            expect(
                removed.changed && removedText.contains("existing-observer")
                    && !removedText.contains(CodexHookConfiguration.marker),
                "Codex observer removal is marker scoped"
            )
        } catch {
            failures.append("FAIL  Codex observer configuration: \(error)")
        }
    }

    mutating func transcriptMetadataPrivacy() {
        var codex = PrivacySafeSessionMetadataScanner(provider: .codex)
        codex.consume(line: Data(
            #"{"type":"session_meta","timestamp":"2026-07-20T13:00:00.123Z","payload":{"id":"codex-transcript-1","cwd":"/Users/example/Projects/chimlo","model":"gpt-local","prompt":"DO NOT RETAIN CODEX PROMPT"}}"#.utf8
        ))
        codex.consume(line: Data(
            #"{"type":"event_msg","timestamp":"2026-07-20T13:01:00.456Z","payload":{"type":"task_started","tool_input":{"command":"DO NOT RETAIN CODEX TOOL"}}}"#.utf8
        ))
        codex.consume(line: Data(
            #"{"type":"event_msg","timestamp":"2026-07-20T13:01:01.456Z","payload":{"type":"user_message","message":"Polish the expanded session row"}}"#.utf8
        ))
        codex.consume(line: Data(
            #"{"type":"event_msg","timestamp":"2026-07-20T13:01:02.456Z","payload":{"type":"agent_message","message":"Implemented the compact three-line layout."}}"#.utf8
        ))
        let codexCandidate = codex.candidate(
            transcriptPath: "/private/codex-rollout.jsonl",
            fallbackUpdatedAt: .distantPast
        )
        expect(codexCandidate?.phase == .working, "Codex rollout lifecycle maps to working")
        expect(codexCandidate?.updatedAt != .distantPast, "fractional Codex timestamps are parsed")
        expect(codexCandidate?.latestUserPrompt == "Polish the expanded session row", "Codex user prompt is projected")
        expect(codexCandidate?.latestAgentResponse == "Implemented the compact three-line layout.", "Codex response is projected")

        var claude = PrivacySafeSessionMetadataScanner(provider: .claude)
        claude.consume(line: Data(
            #"{"sessionId":"claude-transcript-1","cwd":"/Users/example/Projects/chimlo","timestamp":"2026-07-20T13:02:00.789Z","type":"assistant","message":{"role":"assistant","model":"claude-local","content":"Implemented the compact three-line layout."},"toolUseResult":"DO NOT RETAIN CLAUDE TOOL"}"#.utf8
        ))
        let claudeCandidate = claude.candidate(
            transcriptPath: "/private/claude-transcript.jsonl",
            fallbackUpdatedAt: .distantPast
        )
        expect(claudeCandidate?.phase == .working, "Claude transcript lifecycle maps to working")
        expect(claudeCandidate?.latestAgentResponse == "Implemented the compact three-line layout.", "Claude response is projected")

        let encoded = [codexCandidate, claudeCandidate].compactMap { $0 }
            .compactMap { try? JSONEncoder().encode($0) }
            .map { String(decoding: $0, as: UTF8.self) }
            .joined()
        expect(!encoded.contains("Implemented the compact three-line layout."), "conversation previews are not persisted")
        expect(!encoded.contains("DO NOT RETAIN"), "transcript discovery discards tool contents")
        expect(!encoded.contains("transcript.jsonl"), "transcript discovery does not persist transcript paths")
    }

    mutating func modelDisplayNames() {
        expect(
            ModelDisplayName.resolve(
                modelID: "claude-sonnet-5-20260701",
                agent: .claude
            ) == "Sonnet 5",
            "Claude model IDs become concise dynamic names"
        )
        expect(
            ModelDisplayName.resolve(
                modelID: "claude-opus-4-8-20250514",
                agent: .claude
            ) == "Opus 4.8",
            "Claude minor versions use a readable decimal"
        )
        expect(
            ModelDisplayName.resolve(
                modelID: "gpt-5.6-sol",
                agent: .codex,
                providerDisplayName: "GPT-5.6-Sol"
            ) == "5.6 Sol",
            "Codex catalog names stay compact beside the provider label"
        )
        expect(
            ModelDisplayName.resolve(
                modelID: "gpt-5.3-codex-spark",
                agent: .codex
            ) == "5.3 Codex Spark",
            "Codex compound model families remain readable"
        )
    }

    mutating func sessionVisibility() {
        expect(
            !SessionVisibilityPolicy.shouldDisplay(
                title: "chimlo",
                titleKind: .workspace,
                isDemo: false,
                hasActionableRequest: false
            ),
            "workspace fallback is not shown as a session title"
        )
        expect(
            SessionVisibilityPolicy.shouldDisplay(
                title: "chimlo",
                titleKind: .workspace,
                isDemo: false,
                hasActionableRequest: false,
                hasConversationPreview: true
            ),
            "a response-backed Claude workspace session remains visible"
        )
        expect(
            !SessionVisibilityPolicy.shouldDisplay(
                title: "Review recent changes",
                titleKind: .task,
                isDemo: false,
                hasActionableRequest: false,
                hasConversationPreview: true,
                agent: .codex,
                model: "codex-auto-review"
            ),
            "Codex Auto Review sessions stay hidden"
        )
        expect(
            SessionVisibilityPolicy.shouldDisplay(
                title: "Review recent changes",
                titleKind: .task,
                isDemo: false,
                hasActionableRequest: false,
                hasConversationPreview: true,
                agent: .codex,
                model: "gpt-5.6-sol"
            ),
            "ordinary Codex sessions remain visible"
        )
        expect(
            SessionVisibilityPolicy.shouldDisplay(
                title: "Fix model display names",
                titleKind: .task,
                isDemo: false,
                hasActionableRequest: false
            ),
            "provider task titles remain visible"
        )
        expect(
            SessionVisibilityPolicy.shouldDisplay(
                title: "Fix the tiny lighthouse",
                titleKind: .workspace,
                isDemo: true,
                hasActionableRequest: false
            ),
            "the titled onboarding demo remains visible"
        )
        expect(
            SessionVisibilityPolicy.shouldDisplay(
                title: "chimlo",
                titleKind: .workspace,
                isDemo: false,
                hasActionableRequest: true
            ),
            "an untitled session stays visible while owner action is required"
        )
    }

    mutating func claudeHookConfiguration() {
        let helperPath = "/Users/example/Library/Application Support/Chimlo/bin/chimlo"
        let existing = Data(
            #"{"theme":"dark","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"existing-observer"}]}],"Unrelated":[{"hooks":[{"type":"command","command":"leave-this-alone"}]}]}}"#.utf8
        )

        do {
            let merged = try ClaudeHookConfiguration.merging(
                existingData: existing,
                helperPath: helperPath
            )
            expect(merged.changed, "Claude observer merge reports a change")
            let installedState = try ClaudeHookConfiguration.installationState(
                in: merged.data,
                helperPath: helperPath
            )
            expect(
                installedState == .current,
                "Claude observer merge covers every activity event"
            )
            let mergedText = String(decoding: merged.data, as: UTF8.self)
            expect(
                mergedText.contains("leave-this-alone") && mergedText.contains("\"theme\""),
                "Claude observer merge preserves unrelated settings and hooks"
            )
            expect(
                mergedText.contains(ClaudeHookConfiguration.questionMarker)
                    && mergedText.contains("AskUserQuestion"),
                "Claude question bridge is installed as a blocking AskUserQuestion hook"
            )
            expect(
                mergedText.contains(ClaudeHookConfiguration.permissionMarker)
                    && mergedText.contains("hook claude permission")
                    && mergedText.contains("PermissionRequest"),
                "Claude permission bridge is installed as a blocking PermissionRequest hook"
            )

            let repeated = try ClaudeHookConfiguration.merging(
                existingData: merged.data,
                helperPath: helperPath
            )
            expect(!repeated.changed && repeated.data == merged.data, "Claude observer merge is idempotent")

            let movedState = try ClaudeHookConfiguration.installationState(
                in: merged.data,
                helperPath: "/tmp/moved/chimlo"
            )
            expect(movedState == .needsRepair, "a stale Claude helper path is reported for repair")

            let removed = try ClaudeHookConfiguration.removing(existingData: merged.data)
            let removedText = String(decoding: removed.data, as: UTF8.self)
            expect(
                removed.changed && removedText.contains("existing-observer")
                    && !removedText.contains(ClaudeHookConfiguration.marker)
                    && !removedText.contains(ClaudeHookConfiguration.questionMarker)
                    && !removedText.contains(ClaudeHookConfiguration.permissionMarker),
                "Claude observer removal is marker scoped"
            )
        } catch {
            failures.append("FAIL  Claude observer configuration: \(error)")
        }
    }

    mutating func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
        if condition() {
            passes += 1
            print("PASS  \(label)")
        } else {
            failures.append("FAIL  \(label)")
        }
    }

    mutating func coreLifecycle() {
        var reducer = SessionReducer()
        let started = AgentEvent(
            sessionID: "checks-core",
            sequence: 1,
            kind: .sessionStarted,
            agent: .codex,
            title: "Check the reducer",
            detail: "Starting"
        )
        let approval = AgentEvent(
            sessionID: "checks-core",
            sequence: 2,
            kind: .permissionRequested,
            agent: .codex,
            detail: "Waiting",
            request: .approval(.init(id: "checks-approval", summary: "Run a harmless check?"))
        )
        let completed = AgentEvent(
            sessionID: "checks-core",
            sequence: 3,
            kind: .completed,
            agent: .codex,
            detail: "Done"
        )

        _ = reducer.apply(started)
        _ = reducer.apply(approval)
        expect(reducer.sessions[started.sessionID]?.phase == .waitingForApproval, "approval enters waiting state")
        expect(reducer.sessions[started.sessionID]?.pendingRequest?.id == "checks-approval", "request identity survives reduction")
        _ = reducer.apply(completed)
        expect(reducer.sessions[started.sessionID]?.phase == .completed, "completion clears attention")
        expect(reducer.sessions[started.sessionID]?.pendingRequest == nil, "completion clears pending request")
    }

    mutating func coreOrderingAndDeduplication() {
        var reducer = SessionReducer()
        let started = AgentEvent(
            sessionID: "checks-ordering",
            sequence: 4,
            kind: .sessionStarted,
            agent: .claude,
            title: "Order events"
        )
        _ = reducer.apply(started)
        expect(reducer.apply(started) == .ignoredDuplicate, "duplicate message IDs are ignored")
        let stale = AgentEvent(
            sessionID: started.sessionID,
            sequence: 3,
            kind: .activity,
            agent: .claude,
            detail: "Too old"
        )
        expect(reducer.apply(stale) == .ignoredStale, "stale session sequences are ignored")
        expect(DemoScript.make() == DemoScript.make(), "demo event script is deterministic")
    }

    mutating func candidateMergePreservesActionableState() {
        var reducer = SessionReducer()
        _ = reducer.apply(AgentEvent(
            sessionID: "candidate-merge",
            sequence: 1,
            kind: .sessionStarted,
            agent: .codex,
            title: "Workspace",
            detail: "Working"
        ))
        _ = reducer.apply(AgentEvent(
            sessionID: "candidate-merge",
            sequence: 2,
            kind: .permissionRequested,
            agent: .codex,
            detail: "Approval needed",
            request: .approval(.init(id: "approval-1", summary: "Continue in Codex"))
        ))
        _ = reducer.merge(SessionCandidate(
            id: "candidate-merge",
            agent: .codex,
            title: "Named Codex task",
            titleKind: .task,
            detail: "Recent Codex activity",
            phase: .working,
            updatedAt: .now.addingTimeInterval(5),
            evidence: .codexAppServer
        ))
        _ = reducer.merge(SessionCandidate(
            id: "candidate-merge",
            agent: .codex,
            title: "workspace-name",
            detail: "Codex is working",
            phase: .working,
            updatedAt: .now.addingTimeInterval(10),
            evidence: .codexRollout
        ))
        let merged = reducer.sessions["candidate-merge"]
        expect(merged?.title == "Named Codex task", "strong task names survive newer workspace metadata")
        expect(merged?.phase == .waitingForApproval, "metadata cannot overwrite a live approval state")
        expect(merged?.pendingRequest?.id == "approval-1", "metadata preserves the exact pending request")
    }

    mutating func frameRoundTripAndBounds() {
        do {
            let envelope = ChimloEnvelope(
                sentAt: Date(timeIntervalSince1970: 1_785_000_000),
                authenticationToken: String(repeating: "a", count: 64),
                message: .ping
            )
            let frame = try ChimloFrameCodec.encode(envelope)
            let decoded = try ChimloFrameCodec.decode(frame)
            expect(decoded == envelope, "wire frames round-trip")
        } catch {
            failures.append("FAIL  wire frames round-trip: \(error)")
        }

        do {
            let request = ChimloDecisionRequest(
                title: "Oversized",
                message: String(repeating: "x", count: ChimloFrameCodec.maximumPayloadBytes * 2)
            )
            _ = try ChimloFrameCodec.encode(
                ChimloEnvelope(
                    authenticationToken: String(repeating: "b", count: 64),
                    message: .decisionRequest(request)
                )
            )
            failures.append("FAIL  oversized payloads are rejected")
        } catch {
            passes += 1
            print("PASS  oversized payloads are rejected")
        }
    }

    mutating func descriptorPermissions() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-checks-descriptor-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
            let descriptor = RuntimeDescriptor(
                port: 42_001,
                authenticationToken: String(repeating: "c", count: 64),
                processID: 42,
                startedAt: Date(timeIntervalSince1970: 1_785_000_000)
            )
            try store.write(descriptor)
            let storedDescriptor = try store.read()
            expect(storedDescriptor == descriptor, "runtime descriptor round-trips")
            let attributes = try FileManager.default.attributesOfItem(atPath: store.descriptorURL.path)
            expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "runtime descriptor is mode 0600")
        } catch {
            failures.append("FAIL  runtime descriptor protection: \(error)")
        }
    }

    mutating func networkRoundTrip() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-checks-network-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let box = EventBox()
        do {
            let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("runtime.json"))
            let server = try ChimloServer(descriptorStore: store) { event in
                await box.set(event)
            }
            defer { server.stop() }
            _ = try await server.start()
            let client = try ChimloClient(descriptorStore: store, timeout: .seconds(2))
            _ = try await client.ping()
            let event = AgentEvent(
                sessionID: "checks-network",
                sequence: 1,
                kind: .sessionStarted,
                agent: .other,
                title: "Travel through loopback"
            )
            _ = try await client.sendEvent(event)
            let receivedEvent = await box.value()
            expect(receivedEvent?.id == event.id, "authenticated loopback event arrives")
        } catch {
            failures.append("FAIL  authenticated loopback event arrives: \(error)")
        }
    }

    mutating func decisionFailureIsClosed() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("chimlo-checks-missing-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let store = RuntimeDescriptorStore(descriptorURL: directory.appendingPathComponent("missing.json"))
            let client = try ChimloClient(descriptorStore: store, timeout: .milliseconds(30))
            let request = ChimloDecisionRequest(title: "Delete files?", message: "Must remain unresolved")
            let response = await client.requestDecision(request)
            expect(response.outcome == .unavailable, "offline decisions become unavailable")
            expect(!response.outcome.isApproved, "transport failure never approves")
        } catch {
            failures.append("FAIL  fail-closed decision client setup: \(error)")
        }
    }
}

private actor EventBox {
    private var event: AgentEvent?

    func set(_ event: AgentEvent) {
        self.event = event
    }

    func value() -> AgentEvent? {
        event
    }
}

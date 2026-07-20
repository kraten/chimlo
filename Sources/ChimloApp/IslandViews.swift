import ChimloProtocol
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var model: ApplicationModel
    let openSettings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                islandSurface

                switch model.panelMode {
                case .compact:
                    CompactIslandView(model: model)
                        .padding(.horizontal, model.islandLayout.hasCameraHousing ? 0 : 13)
                        .padding(.vertical, model.islandLayout.hasCameraHousing ? 0 : 5)
                case .sessions:
                    if model.islandLayout.hasCameraHousing {
                        ExpandedStatusBand(model: model, openSettings: openSettings)
                    }
                    SessionListView(model: model)
                        .padding(.horizontal, 10)
                        .padding(.top, model.islandLayout.expandedContentTopInset + 2)
                        .padding(.bottom, 10)
                        .frame(width: model.panelSize.width)
                        .frame(width: geometry.size.width, alignment: .center)
                case .onboarding:
                    OnboardingView(model: model)
                        .padding(.horizontal, 18)
                        .padding(.top, model.islandLayout.expandedContentTopInset + 12)
                        .padding(.bottom, 18)
                }
            }
            // Follow AppKit's live, intermediate bounds while the NSPanel grows
            // and shrinks. Using model.panelSize here jumps to the final width
            // before the window animation and makes the content open to one side.
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chimlo agent monitor")
    }

    @ViewBuilder
    private var islandSurface: some View {
        let surface = ChimloTheme.surface(increasedContrast: model.accessibility.increaseContrast)
        if model.islandLayout.hasCameraHousing, model.panelMode == .compact {
            CompactNotchIslandShape()
                .fill(surface)
        } else if model.islandLayout.hasCameraHousing {
            NotchExpandedIslandShape()
            .fill(surface)
        } else {
            ChamferedIslandShape(
                shoulder: model.panelMode == .compact ? 9 : 12,
                lowerCut: model.panelMode == .compact ? 9 : 14
            )
            .fill(surface)
        }
    }
}

private struct ExpandedStatusBand: View {
    @ObservedObject var model: ApplicationModel
    let openSettings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let cameraWidth = min(model.islandLayout.cameraHousingWidth, geometry.size.width)
            let wingWidth = max(0, (geometry.size.width - cameraWidth) / 2)

            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    PixelAvatar(
                        mood: model.activeMood,
                        seed: model.sessions.first?.id.hashValue ?? 0,
                        size: 17,
                        reduceMotion: model.accessibility.reduceMotion
                    )
                    PixelText(text: "CHIMLO", pixelSize: 1, color: ChimloTheme.quietPaper, spacing: 1)
                }
                .padding(.leading, 10)
                .frame(width: wingWidth, height: geometry.size.height, alignment: .leading)
                .clipped()
                .accessibilityHidden(true)

                Color.clear
                    .frame(width: cameraWidth, height: geometry.size.height)
                    .accessibilityHidden(true)

                HStack(spacing: 0) {
                    Button {
                        model.soundsEnabled.toggle()
                    } label: {
                        Image(systemName: model.soundsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(
                        ExpandedControlButtonStyle(
                            color: model.soundsEnabled ? ChimloTheme.paper : ChimloTheme.clayText
                        )
                    )
                    .help(model.soundsEnabled ? "Mute Chimlo sounds" : "Unmute Chimlo sounds")
                    .accessibilityLabel(model.soundsEnabled ? "Mute Chimlo sounds" : "Unmute Chimlo sounds")
                    .accessibilityValue(model.soundsEnabled ? "Sounds on" : "Sounds muted")

                    Button(action: openSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(ExpandedControlButtonStyle(color: ChimloTheme.quietPaper))
                    .help("Open Chimlo settings")
                    .accessibilityLabel("Open Chimlo settings")
                }
                .padding(.trailing, 7)
                .frame(width: wingWidth, height: geometry.size.height, alignment: .trailing)
                .clipped()
            }
        }
        .frame(height: model.islandLayout.expandedContentTopInset)
    }
}

private struct ExpandedControlButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color.opacity(configuration.isPressed ? 0.55 : 1))
            .frame(width: 25, height: 26)
            .contentShape(Rectangle())
    }
}

private struct CompactIslandView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        Button(action: model.openPanel) {
            Group {
                if model.islandLayout.hasCameraHousing {
                    notchContent
                } else {
                    standardContent
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Chimlo. \(summary). \(model.compactLabel.lowercased()).")
    }

    private var standardContent: some View {
        HStack(spacing: 9) {
            PixelAvatar(
                mood: model.activeMood,
                seed: model.sessions.first?.id.hashValue ?? 0,
                size: 31,
                reduceMotion: model.accessibility.reduceMotion
            )
            PixelText(text: model.compactLabel, pixelSize: 1.7, spacing: 1)
            Spacer(minLength: 5)
            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChimloTheme.quietPaper)
                .monospacedDigit()
        }
    }

    private var notchContent: some View {
        HStack(spacing: 0) {
            PixelAvatar(
                mood: model.activeMood,
                seed: model.sessions.first?.id.hashValue ?? 0,
                size: 19,
                reduceMotion: model.accessibility.reduceMotion
            )
            .frame(
                width: model.islandLayout.activityWingWidth,
                height: model.islandLayout.compactHeight,
                alignment: .center
            )

            Color.clear
                .frame(
                    width: model.islandLayout.cameraHousingWidth,
                    height: model.islandLayout.compactHeight
                )

            Text(compactCount)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(compactCountColor)
                .monospacedDigit()
                .frame(
                    width: model.islandLayout.activityWingWidth,
                    height: model.islandLayout.compactHeight,
                    alignment: .center
                )
        }
    }

    private var compactCount: String {
        if model.pendingDecision != nil { return "!" }
        guard !model.sessions.isEmpty else { return "" }
        return "\(min(model.sessions.count, 9))"
    }

    private var compactCountColor: Color {
        if model.pendingDecision != nil { return ChimloTheme.paper }
        if model.sessions.contains(where: { $0.mood == .failed }) { return ChimloTheme.clayText }
        if model.sessions.contains(where: { $0.mood == .working }) { return ChimloTheme.amber }
        return ChimloTheme.quietPaper
    }

    private var summary: String {
        if model.sessions.isEmpty { return "no sessions" }
        if model.sessions.count == 1 { return "1 session" }
        return "\(model.sessions.count) sessions"
    }
}

private struct SessionListView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Local agent activity")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ChimloTheme.paper)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 5) {
                    ConnectionMark(isConnected: model.isReceivingAgentEvents)
                    Text(headerContext)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ChimloTheme.quietPaper)
                        .lineLimit(1)
                }
            }

            if model.sessions.isEmpty {
                VStack(spacing: 8) {
                    if let decision = model.pendingDecision {
                        LiveDecisionView(decision: decision, model: model)
                    }
                    EmptySessionView(model: model)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if let decision = model.pendingDecision {
                            LiveDecisionView(decision: decision, model: model)
                        }
                        ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                            SessionRow(
                                session: session,
                                seed: index,
                                reduceMotion: model.accessibility.reduceMotion,
                                increasedContrast: model.accessibility.increaseContrast,
                                onOpen: session.jumpURL == nil ? nil : { model.open(session) }
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

        }
    }

    private var headerContext: String {
        if model.sessions.count > 1 { return "\(model.sessions.count) sessions" }
        if let session = model.sessions.first { return session.agentName }
        return model.connectionSummary
    }
}

private struct ConnectionMark: View {
    let isConnected: Bool

    var body: some View {
        Canvas { context, _ in
            let color = isConnected ? ChimloTheme.moss : ChimloTheme.clayText
            context.fill(Path(CGRect(x: 1, y: 1, width: 4, height: 4)), with: .color(color))
            context.fill(Path(CGRect(x: 5, y: 2, width: 1, height: 2)), with: .color(color.opacity(0.7)))
        }
        .frame(width: 7, height: 6)
        .accessibilityHidden(true)
    }
}

private struct LiveDecisionView: View {
    let decision: ChimloDecisionRequest
    @ObservedObject var model: ApplicationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                PixelAvatar(
                    mood: .waiting,
                    seed: decision.id.hashValue,
                    size: 38,
                    reduceMotion: model.accessibility.reduceMotion
                )
                VStack(alignment: .leading, spacing: 3) {
                    PixelText(text: "YOUR CALL", pixelSize: 1.2, color: ChimloTheme.paper, spacing: 1)
                    Text(decision.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ChimloTheme.paper)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }

            Text(decision.message)
                .font(.system(size: 11))
                .foregroundStyle(ChimloTheme.quietPaper)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()
                Button(decision.denyLabel) {
                    model.respondToPendingDecision(approved: false)
                }
                .buttonStyle(ChimloButtonStyle(kind: .destructive, compact: true))
                .keyboardShortcut(.cancelAction)

                Button(decision.approveLabel) {
                    model.respondToPendingDecision(approved: true)
                }
                .buttonStyle(ChimloButtonStyle(kind: .primary, compact: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(11)
        .background(ChimloTheme.raisedSurface(increasedContrast: model.accessibility.increaseContrast))
        .clipShape(SteppedPanelShape())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Decision needed. \(decision.title). \(decision.message)")
    }
}

struct SessionRow: View {
    let session: SessionDisplayModel
    let seed: Int
    let reduceMotion: Bool
    let increasedContrast: Bool
    var onOpen: (() -> Void)? = nil

    var body: some View {
        Group {
            if let onOpen {
                Button(action: onOpen) {
                    rowContent
                }
                .buttonStyle(.plain)
                .accessibilityHint("Returns to the originating session")
            } else {
                rowContent
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.agentName), \(session.title), \(session.mood.accessibilityDescription), \(session.detail)")
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            PixelAvatar(mood: session.mood, seed: seed, size: 32, reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChimloTheme.paper)
                    .lineLimit(1)
                Text(metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(ChimloTheme.quietPaper)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 5) {
                        Text(session.elapsedText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ChimloTheme.quietPaper)
                            .monospacedDigit()
                        if onOpen != nil {
                            PixelJumpMark(color: stateColor)
                        }
                    }
                }
                Text(stateLabel.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(stateColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ChimloTheme.raisedSurface(increasedContrast: increasedContrast))
        .clipShape(SteppedPanelShape())
    }

    private var metadata: String {
        var parts = [session.agentName]
        if let model = session.model, !model.isEmpty { parts.append(model) }
        parts.append(session.detail)
        if session.isDemo { parts.append("Preview") }
        return parts.joined(separator: " · ")
    }

    private var stateLabel: String {
        switch session.mood {
        case .idle: "IDLE"
        case .working: "WORK"
        case .waiting: "WAIT"
        case .success: "DONE"
        case .failed: "STOP"
        }
    }

    private var stateColor: Color {
        switch session.mood {
        case .idle: ChimloTheme.quietPaper
        case .working: ChimloTheme.amber
        case .waiting: ChimloTheme.paper
        case .success: ChimloTheme.moss
        case .failed: ChimloTheme.clayText
        }
    }
}

private struct EmptySessionView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        HStack(spacing: 11) {
            PixelAvatar(mood: .idle, size: 34, reduceMotion: model.accessibility.reduceMotion)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChimloTheme.paper)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ChimloTheme.quietPaper)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(ChimloTheme.raisedSurface(increasedContrast: model.accessibility.increaseContrast))
        .clipShape(SteppedPanelShape())
    }

    private var title: String {
        if model.isScanningSessions { return "Finding local sessions" }
        if model.isReceivingAgentEvents { return "No active sessions" }
        if model.hasInstalledAgent { return "Waiting for the first event" }
        return "Connect a coding agent"
    }

    private var detail: String {
        if model.isScanningSessions { return "Checking Codex, Claude, and live processes." }
        if model.isReceivingAgentEvents { return "Chimlo is live. Start or resume a turn." }
        if model.hasInstalledAgent { return "Send a new prompt. Codex may require /hooks approval." }
        return "Set up Codex or Claude Code once in Settings."
    }

    @ViewBuilder
    private var action: some View {
        if !model.codexConnectionState.isInstalled {
            switch model.codexConnectionState {
            case .disconnected, .needsRepair:
                Button(model.codexConnectionState == .needsRepair ? "Repair" : "Connect") {
                    model.connectCodex()
                }
                .buttonStyle(ChimloButtonStyle(kind: .primary, compact: true))
            case .unavailable:
                Button("Retry") { model.refreshAgentConnections() }
                    .buttonStyle(ChimloButtonStyle(kind: .quiet, compact: true))
            case .checking, .installedAwaitingEvent, .receiving:
                EmptyView()
            }
        } else if !model.claudeConnectionState.isInstalled,
                  model.claudeConnectionState == .disconnected {
            Button("Add Claude") { model.connectClaude() }
                .buttonStyle(ChimloButtonStyle(kind: .quiet, compact: true))
        }
    }
}

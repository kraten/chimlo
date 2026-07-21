import ChimloCore
import ChimloProtocol
import SwiftUI

private let expandedHorizontalGutter: CGFloat = 16

struct IslandRootView: View {
    @ObservedObject var model: ApplicationModel
    let openSettings: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                islandSurface

                switch model.panelMode {
                case .compact:
                    CompactIslandView(model: model, media: model.mediaPlayback)
                        .padding(.horizontal, model.islandLayout.hasCameraHousing ? 0 : 13)
                        .padding(.vertical, model.islandLayout.hasCameraHousing ? 0 : 5)
                case .sessions:
                    if model.islandLayout.hasCameraHousing {
                        ExpandedStatusBand(model: model, openSettings: openSettings)
                    }
                    SessionListView(model: model)
                        .padding(.horizontal, expandedHorizontalGutter)
                        .padding(.top, model.islandLayout.expandedContentTopInset + 2)
                        .padding(.bottom, 10)
                        .frame(width: model.panelSize.width)
                        .frame(width: geometry.size.width, alignment: .center)
                case .onboarding:
                    OnboardingView(model: model)
                        .padding(.horizontal, 18)
                        .padding(.top, model.islandLayout.expandedContentTopInset + 12)
                        .padding(.bottom, 18)
                    if model.islandLayout.hasCameraHousing,
                       let feedback = model.systemFeedback {
                        SystemFeedbackNotchBand(
                            feedback: feedback,
                            cameraWidth: model.islandLayout.cameraHousingWidth,
                            reduceMotion: model.accessibility.reduceMotion
                        )
                        .frame(height: model.islandLayout.expandedContentTopInset)
                    }
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
        .accessibilityLabel("Chimlo activity island")
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
        Group {
            if let feedback = model.systemFeedback {
                SystemFeedbackNotchBand(
                    feedback: feedback,
                    cameraWidth: model.islandLayout.cameraHousingWidth,
                    reduceMotion: model.accessibility.reduceMotion
                )
            } else {
                GeometryReader { geometry in
                    let cameraWidth = min(model.islandLayout.cameraHousingWidth, geometry.size.width)
                    let wingWidth = max(0, (geometry.size.width - cameraWidth) / 2)

                    HStack(spacing: 0) {
                        PixelText(text: "CHIMLO", pixelSize: 1, color: ChimloTheme.quietPaper, spacing: 1)
                            .padding(.leading, expandedHorizontalGutter)
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
                        .padding(.trailing, expandedHorizontalGutter)
                        .frame(width: wingWidth, height: geometry.size.height, alignment: .trailing)
                        .clipped()
                    }
                }
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

private struct SystemFeedbackNotchBand: View {
    let feedback: SystemFeedbackPresentation
    let cameraWidth: CGFloat
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            let resolvedCameraWidth = min(cameraWidth, geometry.size.width)
            let wingWidth = max(0, (geometry.size.width - resolvedCameraWidth) / 2)

            HStack(spacing: 0) {
                PixelSystemGlyph(kind: glyphKind, size: 16)
                    .padding(.leading, expandedHorizontalGutter)
                    .frame(width: wingWidth, height: geometry.size.height, alignment: .leading)
                    .clipped()

                Color.clear
                    .frame(width: resolvedCameraWidth, height: geometry.size.height)
                    .accessibilityHidden(true)

                PixelLevelMeter(value: feedback.value, reduceMotion: reduceMotion)
                    .padding(.trailing, expandedHorizontalGutter)
                    .frame(width: wingWidth, height: geometry.size.height, alignment: .trailing)
                    .clipped()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedback.accessibilityDescription)
    }

    private var glyphKind: PixelSystemGlyphKind {
        switch feedback.kind {
        case .outputVolume:
            feedback.isMuted || feedback.value == 0 ? .mutedSpeaker : .speaker
        case .displayBrightness:
            .sun
        }
    }
}

private struct PixelLevelMeter: View {
    let value: Double
    let reduceMotion: Bool

    private let trackWidth: CGFloat = 23

    private var fillWidth: CGFloat {
        CGFloat(SystemFeedbackPolicy.meterFillWidth(
            for: value,
            trackWidth: Double(trackWidth)
        ))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            PixelMeterPips(color: ChimloTheme.mutedPaper)
            PixelMeterPips(color: ChimloTheme.paper)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: fillWidth, height: 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
        }
        .frame(width: trackWidth, height: 12, alignment: .center)
        .animation(
            reduceMotion ? nil : .linear(duration: 0.09),
            value: fillWidth
        )
        .accessibilityHidden(true)
    }
}

private struct PixelMeterPips: View {
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<SystemFeedbackPolicy.meterCellCount, id: \.self) { _ in
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: 8)
            }
        }
    }
}

private struct SystemFeedbackCompactContent: View {
    let feedback: SystemFeedbackPresentation
    let model: ApplicationModel

    var body: some View {
        if model.islandLayout.hasCameraHousing {
            HStack(spacing: 0) {
                PixelSystemGlyph(kind: glyphKind, size: 16)
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

                PixelLevelMeter(
                    value: feedback.value,
                    reduceMotion: model.accessibility.reduceMotion
                )
                .frame(
                    width: model.islandLayout.activityWingWidth,
                    height: model.islandLayout.compactHeight,
                    alignment: .center
                )
            }
        } else {
            HStack(spacing: 8) {
                PixelSystemGlyph(kind: glyphKind, size: 16)
                PixelText(text: shortLabel, pixelSize: 1, color: ChimloTheme.quietPaper, spacing: 1)
                Spacer(minLength: 4)
                PixelLevelMeter(
                    value: feedback.value,
                    reduceMotion: model.accessibility.reduceMotion
                )
                PixelText(
                    text: "\(feedback.percentage)%",
                    pixelSize: 1,
                    color: ChimloTheme.paper,
                    spacing: 1
                )
            }
        }
    }

    private var glyphKind: PixelSystemGlyphKind {
        switch feedback.kind {
        case .outputVolume:
            feedback.isMuted || feedback.value == 0 ? .mutedSpeaker : .speaker
        case .displayBrightness:
            .sun
        }
    }

    private var shortLabel: String {
        feedback.kind == .outputVolume ? "VOL" : "LUX"
    }
}

private struct CompactIslandView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var media: MediaPlaybackMonitor

    var body: some View {
        Group {
            if let feedback = model.systemFeedback {
                openPanelButton {
                    SystemFeedbackCompactContent(feedback: feedback, model: model)
                }
            } else if model.shouldShowCompactMedia, media.presentation != nil {
                CompactMusicPlayerView(model: model, media: media)
            } else {
                openPanelButton {
                    if model.islandLayout.hasCameraHousing {
                        notchContent
                    } else {
                        standardContent
                    }
                }
            }
        }
        .accessibilityLabel(compactAccessibilityLabel)
    }

    private func openPanelButton<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: model.openPanel) {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var compactAccessibilityLabel: String {
        if let feedback = model.systemFeedback {
            return "Open Chimlo. \(feedback.accessibilityDescription)."
        }
        if model.shouldShowCompactMedia, let presentation = media.presentation {
            return "\(presentation.accessibilityDescription)."
        }
        return "Open Chimlo. \(summary). \(model.compactLabel.lowercased())."
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
                size: 17,
                pixelUnit: 1.4,
                reduceMotion: model.accessibility.reduceMotion
            )
            .offset(x: 1.5)
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
        if model.pendingDecision != nil || model.sessions.contains(where: { $0.mood == .waiting }) {
            return "!"
        }
        if model.sessions.contains(where: { $0.mood == .question }) { return "?" }
        guard !model.sessions.isEmpty else { return "" }
        return "\(min(model.sessions.count, 9))"
    }

    private var compactCountColor: Color {
        if model.pendingDecision != nil { return ChimloTheme.paper }
        if model.sessions.contains(where: { $0.mood == .waiting || $0.mood == .question }) {
            return ChimloTheme.attention
        }
        if model.sessions.contains(where: { $0.mood == .failed }) { return ChimloTheme.clayText }
        if model.sessions.contains(where: { $0.mood == .working }) { return ChimloTheme.liveGreen }
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
            if model.sessions.isEmpty {
                Group {
                    if let decision = model.pendingDecision {
                        LiveDecisionView(decision: decision, model: model)
                    } else {
                        EmptySessionView(model: model)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    // The local registry is capped at 40 sessions. Eager rows
                    // avoid SwiftUI's macOS lazy-placement livelock when a
                    // dynamically sized permission row is scrolled after reveal.
                    VStack(spacing: 6) {
                        if let decision = model.pendingDecision {
                            LiveDecisionView(decision: decision, model: model)
                        }
                        ForEach(Array(model.displayedSessions.enumerated()), id: \.element.id) { index, session in
                            SessionRow(
                                session: session,
                                seed: index,
                                reduceMotion: model.accessibility.reduceMotion,
                                increasedContrast: model.accessibility.increaseContrast,
                                onOpen: session.jumpURL == nil ? nil : { model.open(session) },
                                onArchive: session.needsAttention || session.isDemo
                                    ? nil
                                    : { model.archiveSession(session) },
                                onPermissionDecision: { outcome in
                                    model.respondToSessionPermission(
                                        sessionID: session.id,
                                        outcome: outcome
                                    )
                                },
                                onQuestionOption: { label in
                                    model.selectQuestionOption(sessionID: session.id, label: label)
                                },
                                onSubmitQuestion: {
                                    model.submitQuestionSelections(sessionID: session.id)
                                },
                                onAnswerInClaude: {
                                    model.answerQuestionInClaudeCode(sessionID: session.id)
                                }
                            )
                        }

                        if model.canRevealAllSessions {
                            Button(action: model.revealAllSessions) {
                                Text(showAllSessionsLabel)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(ChimloTheme.mutedPaper)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(
                                "Shows sessions hidden while this question or approval is active"
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var showAllSessionsLabel: String {
        let count = model.sessions.count
        return count == 1 ? "Show all 1 session" : "Show all \(count) sessions"
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
                    PixelText(text: "YOUR CALL", pixelSize: 1.2, color: ChimloTheme.attention, spacing: 1)
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
        .background(
            model.accessibility.increaseContrast
                ? ChimloTheme.raisedAttentionInk
                : ChimloTheme.attentionInk
        )
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
    var onArchive: (() -> Void)? = nil
    var onPermissionDecision: ((ProviderPermissionOutcome) -> Void)? = nil
    var onQuestionOption: ((String) -> Void)? = nil
    var onSubmitQuestion: (() -> Void)? = nil
    var onAnswerInClaude: (() -> Void)? = nil
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            summaryCard

            if let permission = session.permission {
                SessionPermissionView(
                    presentation: permission,
                    decide: { onPermissionDecision?($0) }
                )
            }

            if let question = session.question {
                SessionQuestionView(
                    presentation: question,
                    select: { onQuestionOption?($0) },
                    submit: { onSubmitQuestion?() },
                    answerInClaude: { onAnswerInClaude?() }
                )
            }

            if session.showsCompletedConversation {
                completionDetails
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var summaryCard: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let onOpen {
                    Button(action: onOpen) {
                        rowContent
                    }
                    .buttonStyle(SessionMessageButtonStyle(
                        isHovering: isHovering
                    ))
                    .accessibilityLabel(accessibilitySummary)
                    .accessibilityHint("Returns to the originating session")
                } else {
                    rowContent
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilitySummary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingControls
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isHovering ? ChimloTheme.rowHoverEdge : .clear,
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        }
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            PixelAvatar(mood: session.mood, seed: seed, size: 34, reduceMotion: reduceMotion)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ChimloTheme.paper)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: 6)

                    SessionMetadataBadge(
                        text: session.agentName,
                        foreground: providerColor,
                        background: providerColor.opacity(isHovering ? 0.24 : 0.15)
                    )

                    if let model = session.model, !model.isEmpty {
                        SessionMetadataBadge(
                            text: model,
                            background: neutralBadgeBackground
                        )
                    }

                    if let terminal = session.terminal, !terminal.isEmpty {
                        SessionMetadataBadge(
                            text: terminal,
                            background: neutralBadgeBackground
                        )
                    }
                }
                .padding(.trailing, trailingControlInset)

                if let prompt = session.latestUserPrompt {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("You:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ChimloTheme.quietPaper)
                        Text(prompt)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ChimloTheme.quietPaper)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if session.isDemo {
                            Text("Preview")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(ChimloTheme.mutedPaper)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(session.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusDetailColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let response = session.latestAgentResponse {
                    Text(response)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusDetailColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if session.latestUserPrompt != nil {
                    Text(session.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusDetailColor)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 62)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailingControls: some View {
        HStack(spacing: 0) {
            if let onArchive {
                Button(action: onArchive) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12, weight: .medium))
                        .offset(x: 3)
                        .frame(width: 20, height: 28)
                }
                .buttonStyle(SessionArchiveButtonStyle())
                .help("Archive in Chimlo")
                .accessibilityLabel("Archive \(session.displayTitle) in Chimlo")
            }

            if let onOpen {
                Button(action: onOpen) {
                    PixelJumpMark(color: ChimloTheme.mutedPaper)
                        .frame(width: 20, height: 28)
                }
                .buttonStyle(.plain)
                .help("Open source session")
                .accessibilityLabel("Open \(session.displayTitle) in the source app")
            }
        }
        .padding(.top, trailingControlsTopPadding)
        .padding(.trailing, 6)
    }

    private var trailingControlInset: CGFloat {
        let controlCount = (onArchive == nil ? 0 : 1) + (onOpen == nil ? 0 : 1)
        guard controlCount > 0 else { return 0 }
        return CGFloat(controlCount * 20 - 4)
    }

    private var neutralBadgeBackground: Color {
        isHovering ? ChimloTheme.hoveredBadgeInk : ChimloTheme.badgeInk
    }

    private var trailingControlsTopPadding: CGFloat {
        let hasConversationPreview = session.latestUserPrompt != nil
            || session.latestAgentResponse != nil
        return hasConversationPreview ? 3 : 9
    }

    private var completionDetails: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("You:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ChimloTheme.mutedPaper)

                Text(session.latestUserPrompt ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChimloTheme.quietPaper)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text("Done")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ChimloTheme.mutedPaper)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChimloTheme.selectedInk)

            Text(session.latestAgentResponse ?? "")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ChimloTheme.quietPaper)
                .lineSpacing(2)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(ChimloTheme.raisedInk)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    increasedContrast ? ChimloTheme.quietPaper : ChimloTheme.selectedInk,
                    lineWidth: 1
                )
        }
    }

    private var cardBackground: Color {
        if isHovering { return ChimloTheme.rowHoverInk }

        switch session.mood {
        case .waiting, .question: return ChimloTheme.attentionInk
        case .failed: return ChimloTheme.failureInk
        case .idle, .working, .success: return .clear
        }
    }

    private var statusDetailColor: Color {
        switch session.mood {
        case .waiting, .question: ChimloTheme.attention
        case .failed: ChimloTheme.clayText
        case .idle, .working, .success: ChimloTheme.quietPaper
        }
    }

    private var providerColor: Color {
        session.agentName.localizedCaseInsensitiveContains("claude")
            ? ChimloTheme.providerOrange
            : ChimloTheme.providerBlue
    }

    private var accessibilitySummary: String {
        let prompt = session.latestUserPrompt.map { "User prompt: \($0)." } ?? ""
        let response = session.latestAgentResponse ?? session.detail
        return "\(session.agentName), \(session.displayTitle), \(session.mood.accessibilityDescription). \(prompt) Latest response: \(response)"
    }
}

private struct SessionPermissionView: View {
    let presentation: SessionPermissionPresentation
    let decide: (ProviderPermissionOutcome) -> Void

    private var request: ProviderPermissionRequest { presentation.request }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 7) {
                PixelSystemGlyph(
                    kind: .warning,
                    color: ChimloTheme.providerOrange,
                    size: 15
                )

                Text(request.toolName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ChimloTheme.providerOrange)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text("Claude permission")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ChimloTheme.mutedPaper)
            }

            Text(request.prompt)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ChimloTheme.paper)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = request.detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ChimloTheme.quietPaper)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let preview = request.preview {
                Text(preview)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ChimloTheme.quietPaper)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(ChimloTheme.raisedInk)
                    .clipShape(SteppedPanelShape())
            }

            HStack(spacing: 6) {
                Button("Deny") {
                    decide(.denied)
                }
                .buttonStyle(PermissionActionButtonStyle(kind: .deny))
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Deny this Claude Code tool request")

                Button("Allow Once") {
                    decide(.allowedOnce)
                }
                .buttonStyle(PermissionActionButtonStyle(kind: .once))
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Allow only this Claude Code tool request")

                Button("Allow All") {
                    decide(.allowedForSession)
                }
                .buttonStyle(PermissionActionButtonStyle(kind: .session))
                .accessibilityHint("Allow Claude's matching requests for this session only")
            }
        }
        // The stepped cut removes six points at the top-left. Twelve points of
        // leading padding keeps the icon, type, and buttons fully clear of it.
        .padding(.top, 10)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.bottom, 9)
        .background(ChimloTheme.attentionInk)
        .clipShape(SteppedPanelShape())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Claude Code permission for \(request.toolName). \(request.prompt)"
        )
    }
}

private struct PermissionActionButtonStyle: ButtonStyle {
    enum Kind {
        case deny
        case once
        case session
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 31)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(SteppedPanelShape())
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch kind {
        case .deny: ChimloTheme.clayText
        case .once, .session: ChimloTheme.ink
        }
    }

    private func background(isPressed: Bool) -> Color {
        switch kind {
        case .deny:
            isPressed ? ChimloTheme.clay.opacity(0.42) : ChimloTheme.clay.opacity(0.24)
        case .once:
            isPressed ? ChimloTheme.quietPaper : ChimloTheme.paper
        case .session:
            isPressed ? ChimloTheme.attention : ChimloTheme.providerOrange
        }
    }
}

private struct SessionQuestionView: View {
    let presentation: SessionQuestionPresentation
    let select: (String) -> Void
    let submit: () -> Void
    let answerInClaude: () -> Void

    private var question: ProviderQuestion { presentation.question }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(question.header ?? "Claude asks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ChimloTheme.providerOrange)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if presentation.questionCount > 1 {
                    Text("\(presentation.questionIndex + 1) of \(presentation.questionCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ChimloTheme.mutedPaper)
                        .monospacedDigit()
                }
            }

            Text(question.prompt)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ChimloTheme.paper)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 5) {
                ForEach(question.options, id: \.label) { option in
                    Button {
                        select(option.label)
                    } label: {
                        HStack(alignment: .center, spacing: 8) {
                            if question.allowsMultipleSelections {
                                PixelChoiceMark(
                                    selected: presentation.selectedLabels.contains(option.label)
                                )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(ChimloTheme.paper)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let detail = option.detail {
                                    Text(detail)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(ChimloTheme.quietPaper)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, option.detail == nil ? 7 : 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(QuestionOptionButtonStyle(
                        selected: presentation.selectedLabels.contains(option.label)
                    ))
                    .accessibilityHint(
                        question.allowsMultipleSelections
                            ? "Toggles this answer"
                            : "Sends this answer to Claude Code"
                    )
                }
            }

            HStack(spacing: 10) {
                Button("Answer in Claude Code", action: answerInClaude)
                    .buttonStyle(ProviderFallbackButtonStyle())

                Spacer(minLength: 8)

                if question.allowsMultipleSelections {
                    Button(submitLabel, action: submit)
                        .buttonStyle(ChimloButtonStyle(kind: .primary, compact: true))
                        .disabled(presentation.selectedLabels.isEmpty)
                } else {
                    Text("Choose an option to continue")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(ChimloTheme.mutedPaper)
                }
            }
        }
        // The stepped top-left cut is six points. Twelve points of leading
        // padding keeps every glyph and control fully inside the live region.
        .padding(.top, 10)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.bottom, 10)
        .background(ChimloTheme.attentionInk)
        .clipShape(SteppedPanelShape())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude Code asks: \(question.prompt)")
    }

    private var submitLabel: String {
        let count = presentation.selectedLabels.count
        return count == 1 ? "Send 1 answer" : "Send \(count) answers"
    }
}

private struct QuestionOptionButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(background(isPressed: configuration.isPressed))
            .clipShape(SteppedPanelShape())
            .contentShape(Rectangle())
    }

    private func background(isPressed: Bool) -> Color {
        if isPressed { return ChimloTheme.hoveredBadgeInk }
        if selected { return ChimloTheme.raisedAttentionInk }
        return ChimloTheme.raisedInk
    }
}

private struct ProviderFallbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(
                configuration.isPressed ? ChimloTheme.paper : ChimloTheme.quietPaper
            )
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}

private struct PixelChoiceMark: View {
    let selected: Bool

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            let unit: CGFloat = 2
            let points = selected
                ? [
                    CGPoint(x: 0, y: 2), CGPoint(x: 1, y: 3), CGPoint(x: 2, y: 2),
                    CGPoint(x: 3, y: 1), CGPoint(x: 4, y: 0),
                ]
                : [
                    CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0),
                    CGPoint(x: 0, y: 4), CGPoint(x: 4, y: 4),
                ]
            for point in points {
                context.fill(
                    Path(CGRect(
                        x: point.x * unit,
                        y: point.y * unit,
                        width: unit,
                        height: unit
                    )),
                    with: .color(selected ? ChimloTheme.attention : ChimloTheme.mutedPaper)
                )
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

private struct SessionArchiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                configuration.isPressed ? ChimloTheme.paper : ChimloTheme.mutedPaper
            )
            .contentShape(Rectangle())
    }
}

private struct SessionMessageButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func background(isPressed: Bool) -> Color {
        if isPressed { return ChimloTheme.badgeInk }
        if isHovering { return ChimloTheme.rowHoverInk }
        return .clear
    }
}

private struct SessionMetadataBadge: View {
    let text: String
    var foreground = ChimloTheme.quietPaper
    var background = ChimloTheme.badgeInk

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .monospacedDigit()
            .padding(.horizontal, 6)
            .frame(height: 18)
            .fixedSize(horizontal: true, vertical: false)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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

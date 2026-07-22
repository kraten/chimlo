import AppKit
import ChimloCore
import ChimloProtocol
import SwiftUI

private let expandedHorizontalGutter: CGFloat = 16

struct IslandRootView: View {
    @ObservedObject var model: ApplicationModel
    let openSettings: () -> Void

    var body: some View {
        GeometryReader { hostGeometry in
            GeometryReader { islandGeometry in
                ZStack(alignment: .top) {
                    islandSurface

                    switch model.presentedPanelMode {
                    case .compact:
                        CompactIslandView(model: model, media: model.mediaPlayback)
                            .padding(.horizontal, model.islandLayout.hasCameraHousing ? 0 : 13)
                            .padding(.vertical, model.islandLayout.hasCameraHousing ? 0 : 5)
                    case .sessions:
                        if model.islandLayout.hasCameraHousing {
                            ExpandedStatusBand(model: model, openSettings: openSettings)
                        }
                        if model.showsUsageDetails {
                            UsageDashboardView(model: model)
                                .padding(.horizontal, expandedHorizontalGutter)
                                .padding(.top, model.islandLayout.expandedContentTopInset + 2)
                        }
                        SessionListView(model: model)
                            .padding(.horizontal, expandedHorizontalGutter)
                            .padding(
                                .top,
                                model.islandLayout.expandedContentTopInset
                                    + 2
                                    + (model.showsUsageDetails ? CapacityLayout.disclosureHeight : 0)
                            )
                            .padding(.bottom, 10)
                            .frame(width: model.panelSize.width)
                            .frame(width: islandGeometry.size.width, alignment: .center)
                    case .onboarding:
                        OnboardingView(model: model)
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
                // Follow the live SwiftUI bounds while the visible island grows
                // inside the fixed AppKit host. WindowServer now sees one stable
                // frame across Spaces instead of an in-flight window resize.
                .frame(width: islandGeometry.size.width, height: islandGeometry.size.height)
                .clipped()
            }
            .frame(width: model.panelSize.width, height: model.panelSize.height)
            .animation(islandResizeAnimation, value: model.panelSize)
            .frame(
                width: hostGeometry.size.width,
                height: hostGeometry.size.height,
                alignment: .top
            )
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chimlo activity island")
    }

    private var islandResizeAnimation: Animation? {
        guard !model.accessibility.reduceMotion else { return nil }
        return .timingCurve(0.32, 0.72, 0, 1, duration: 0.24)
    }

    @ViewBuilder
    private var islandSurface: some View {
        let surface = ChimloTheme.surface(increasedContrast: model.accessibility.increaseContrast)
        if model.islandLayout.hasCameraHousing, model.presentedPanelMode == .compact {
            CompactNotchIslandShape()
                .fill(surface)
        } else if model.islandLayout.hasCameraHousing {
            NotchExpandedIslandShape()
            .fill(surface)
        } else {
            ChamferedIslandShape(
                shoulder: model.presentedPanelMode == .compact ? 9 : 12,
                lowerCut: model.presentedPanelMode == .compact ? 9 : 14
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
                        InlineCapacityView(model: model)
                            .padding(.leading, expandedHorizontalGutter)
                            .frame(width: wingWidth, height: geometry.size.height, alignment: .leading)
                            .clipped()

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
                .padding(.trailing, 8)
                .frame(
                    width: model.islandLayout.activityWingWidth,
                    height: model.islandLayout.compactHeight,
                    alignment: .trailing
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
                if model.fullScreenMediaPresentationMode == .systemFeedbackOnly {
                    SystemFeedbackCompactContent(feedback: feedback, model: model)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(feedback.accessibilityDescription)
                } else {
                    openPanelButton {
                        SystemFeedbackCompactContent(feedback: feedback, model: model)
                    }
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
            if model.fullScreenMediaPresentationMode == .systemFeedbackOnly {
                return feedback.accessibilityDescription
            }
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

            ZStack {
                // Keep this wing in the layout even when there is no count,
                // warning, or owner-interaction signal to draw. EmptyView does
                // not retain its frame, which otherwise shifts the avatar by
                // half of the missing 32-point wing toward the camera housing.
                Color.clear
                compactTrailingSignal
            }
                .frame(
                    width: model.islandLayout.activityWingWidth,
                    height: model.islandLayout.compactHeight,
                    alignment: .center
                )
        }
    }

    @ViewBuilder
    private var compactTrailingSignal: some View {
        if model.pendingDecision != nil || model.sessions.contains(where: { $0.mood == .waiting }) {
            compactSignalText("!", color: model.pendingDecision != nil ? ChimloTheme.paper : ChimloTheme.attention)
        } else if model.sessions.contains(where: { $0.mood == .question }) {
            compactSignalText("?", color: ChimloTheme.attention)
        } else if model.sessions.contains(where: { $0.mood == .failed }) {
            compactSignalText("×", color: ChimloTheme.clayText)
        } else if !model.sessions.isEmpty {
            compactSignalText(
                "\(min(model.sessions.count, 9))",
                color: model.sessions.contains(where: { $0.mood == .working })
                    ? ChimloTheme.liveGreen
                    : ChimloTheme.quietPaper
            )
        }
    }

    private func compactSignalText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .monospacedDigit()
    }

    private var summary: String {
        if model.sessions.isEmpty { return "no sessions" }
        if model.sessions.count == 1 { return "1 session" }
        return "\(model.sessions.count) sessions"
    }
}

private struct InlineCapacityView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        let codex = model.capacityReading(provider: .codex, kind: .weekly)
        let claude = model.capacityReading(provider: .claude, kind: .weekly)
        let help = capacityDisclosureHelp(
            codexReading: codex,
            claudeReading: claude,
            isExpanded: model.showsUsageDetails
        )

        Button(action: model.toggleUsageDetails) {
            ViewThatFits(in: .horizontal) {
                providerPair(
                    codex: codex,
                    claude: claude,
                    logoSize: 11,
                    segmentWidth: 3,
                    segmentCount: 5,
                    percentageSize: 10,
                    percentageWidth: 32,
                    providerSpacing: 8
                )
                providerPair(
                    codex: codex,
                    claude: claude,
                    logoSize: 9,
                    segmentWidth: 2.5,
                    segmentCount: 4,
                    percentageSize: 9,
                    percentageWidth: 27,
                    providerSpacing: 6
                )
            }
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(CapacityDisclosureButtonStyle())
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(model.showsUsageDetails ? "Expanded" : "Collapsed")
    }

    private func providerPair(
        codex: CapacityReading,
        claude: CapacityReading,
        logoSize: CGFloat,
        segmentWidth: CGFloat,
        segmentCount: Int,
        percentageSize: CGFloat,
        percentageWidth: CGFloat,
        providerSpacing: CGFloat
    ) -> some View {
        HStack(spacing: providerSpacing) {
            providerIndicator(
                provider: .codex,
                reading: codex,
                logoSize: logoSize,
                segmentWidth: segmentWidth,
                segmentCount: segmentCount,
                percentageSize: percentageSize,
                percentageWidth: percentageWidth
            )
            providerIndicator(
                provider: .claude,
                reading: claude,
                logoSize: logoSize,
                segmentWidth: segmentWidth,
                segmentCount: segmentCount,
                percentageSize: percentageSize,
                percentageWidth: percentageWidth
            )
        }
    }

    private func providerIndicator(
        provider: CapacityProvider,
        reading: CapacityReading,
        logoSize: CGFloat,
        segmentWidth: CGFloat,
        segmentCount: Int,
        percentageSize: CGFloat,
        percentageWidth: CGFloat
    ) -> some View {
        HStack(spacing: 4) {
            ProviderLogoView(provider: provider, size: logoSize)
            HStack(spacing: 2) {
                PixelCapacityGauge(
                    reading: reading,
                    provider: provider,
                    segmentWidth: segmentWidth,
                    segmentHeight: 7,
                    segmentCount: segmentCount,
                    segmentSpacing: 1,
                    // Header shows remaining %, so fill the bar to match that
                    // number rather than the consumed amount.
                    usedOverride: reading.remainingPercentage
                )
                capacityPercentage(
                    reading,
                    provider: provider,
                    fontSize: percentageSize,
                    width: percentageWidth
                )
            }
        }
    }

    private func capacityPercentage(
        _ reading: CapacityReading,
        provider: CapacityProvider,
        fontSize: CGFloat,
        width: CGFloat
    ) -> some View {
        Text(capacityPercentageText(reading))
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(capacityColor(reading, provider: provider))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
            .frame(width: width, alignment: .leading)
    }
}

private struct CapacityDisclosureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.58 : 1)
    }
}

private struct UsageDashboardView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        let panelShape = ChamferedIslandShape(shoulder: 6, lowerCut: 6)

        HStack(alignment: .top, spacing: 16) {
            UsageProviderBlock(
                provider: .codex,
                readings: [("7d", model.capacityReading(provider: .codex, kind: .weekly))],
                now: model.capacityClock
            )

            DottedVLine()
                .stroke(
                    ChimloTheme.mutedPaper.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )
                .frame(width: 1, height: 52)
                .frame(maxHeight: .infinity, alignment: .center)

            UsageProviderBlock(
                provider: .claude,
                readings: [
                    ("7d", model.capacityReading(provider: .claude, kind: .weekly)),
                    ("5h", model.capacityReading(provider: .claude, kind: .session)),
                ],
                now: model.capacityClock
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity)
        .frame(height: CapacityLayout.detailsHeight, alignment: .top)
        .background(
            panelShape.fill(
                ChimloTheme.raisedSurface(increasedContrast: model.accessibility.increaseContrast)
            )
        )
        .overlay(
            panelShape.stroke(ChimloTheme.selectedInk.opacity(0.72), lineWidth: 1)
        )
    }
}

private struct DottedVLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct UsageProviderBlock: View {
    let provider: CapacityProvider
    let readings: [(String, CapacityReading)]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ProviderLogoView(provider: provider, size: 9)

                PixelText(text: providerName, pixelSize: 1, color: providerColor, spacing: 1)

                if let freshness {
                    PixelText(text: freshness.text, pixelSize: 1, color: ChimloTheme.mutedPaper, spacing: 1)
                        .opacity(freshness.stale ? 0.4 : 0.85)
                        .accessibilityLabel("Updated \(freshness.text.lowercased()) ago.")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, item in
                    UsageLimitBlock(
                        label: item.0,
                        provider: provider,
                        reading: item.1,
                        now: now
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerName: String {
        provider == .codex ? "CODEX" : "CLAUDE"
    }

    // "Last updated" age shown beside the provider name; dimmed further once the
    // data is stale past the freshness window so a failed or slow fetch is
    // visible rather than confident stale numbers.
    private var freshness: (text: String, stale: Bool)? {
        guard let updated = readings.first?.1.lastUpdatedAt else { return nil }
        let elapsed = max(0, now.timeIntervalSince(updated))
        return (compactAge(elapsed), elapsed > CapacityPolicy.freshnessInterval)
    }

    private func compactAge(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "NOW" }
        if minutes < 60 { return "\(minutes)M" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)H" }
        return "\(hours / 24)D"
    }

    private var providerColor: Color {
        provider == .codex ? ChimloTheme.providerBlue : ChimloTheme.providerOrange
    }
}

private struct UsageLimitBlock: View {
    let label: String
    let provider: CapacityProvider
    let reading: CapacityReading
    let now: Date

    var body: some View {
        Group {
            if provider == .codex {
                VStack(alignment: .leading, spacing: 3) {
                    capacityRow
                    paceRow
                }
            } else {
                capacityRow
            }
        }
        .help(rowHelp(label: label, provider: provider, reading: reading))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowHelp(label: label, provider: provider, reading: reading))
    }

    // LABEL · gauge · PERCENT · RESET — label sits on the left, the reset
    // countdown is pinned inline on the right. The gauge flexes to fill, so the
    // reset always has room and is shown.
    private var capacityRow: some View {
        mainRowContent(includesReset: true)
            .frame(height: 16, alignment: .leading)
    }

    private func mainRowContent(includesReset: Bool) -> some View {
        // At the limit the remaining percentage is always "0%" and tells you
        // nothing — blank that cell and surface the reset countdown in red in
        // its own (already reserved) column. Every frame is retained so the
        // row does not reflow.
        let atLimit = reading.isExhausted
        let reset = includesReset ? resetDuration(reading, now: now) : nil
        let hidePercent = atLimit && reset != nil
        return HStack(spacing: 5) {
            rowLabel(label)

            gauge(
                usedOverride: reading.remainingPercentage,
                colorOverride: atLimit ? ChimloTheme.clayText.opacity(0.4) : nil
            )

            if hidePercent {
                percentText("", color: .clear)
            } else {
                percentText(
                    capacityPercentageText(reading),
                    color: capacityColor(reading, provider: provider)
                )
            }

            trailingText(
                reset ?? "",
                color: atLimit && reset != nil ? ChimloTheme.clayText : ChimloTheme.quietPaper
            )
            .accessibilityHidden(reset == nil)
        }
    }

    // Codex-only: how far through the weekly window you are, so you can read
    // your used percentage against the pace you are burning it at.
    @ViewBuilder private var paceRow: some View {
        if let pace = paceFraction(reading, now: now) {
            let pacePercent = pace * 100
            let percent = Int(pacePercent.rounded())
            // If usage is meaningfully ahead of pace you are burning the window
            // early — tint the pace bar and value amber; otherwise leave grey.
            let burningEarly = (reading.usedPercentage ?? 0) - pacePercent > paceWarningMargin
            let barColor = burningEarly ? ChimloTheme.attention : ChimloTheme.mutedPaper
            let valueColor = burningEarly ? ChimloTheme.attention : ChimloTheme.quietPaper
            HStack(spacing: 5) {
                rowLabel("PACE")

                gauge(usedOverride: pacePercent, colorOverride: barColor)

                percentText("\(percent)%", color: valueColor)

                trailingText("OF 7D")
            }
            .frame(height: 16, alignment: .leading)
            .help("Codex weekly pace: \(percent) percent of the window elapsed.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Codex weekly pace: \(percent) percent of the window elapsed.")
        }
    }

    // Fixed column so gauges line up across rows (Codex must fit "PACE") and a
    // deliberate gap sits between the window label and the bar.
    private var labelColumnWidth: CGFloat {
        provider == .codex ? 26 : 15
    }

    // How far usage must lead pace (in points) before the pace row warns that
    // the window is being burned early.
    private let paceWarningMargin: Double = 10

    private func rowLabel(_ text: String) -> some View {
        PixelText(text: text, pixelSize: 1, color: ChimloTheme.quietPaper, spacing: 1)
            .frame(width: labelColumnWidth, alignment: .leading)
    }

    private func gauge(usedOverride: Double?, colorOverride: Color?) -> some View {
        PixelCapacityGauge(
            reading: reading,
            provider: provider,
            segmentWidth: 5,
            segmentHeight: 8,
            segmentCount: 10,
            fillsWidth: true,
            usedOverride: usedOverride,
            colorOverride: colorOverride
        )
    }

    private func percentText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .monospacedDigit()
            .frame(width: 34, alignment: .leading)
            .padding(.leading, 2)
    }

    // Fixed column so every row's gauge ends at the same x (7d row and pace
    // row line up) and the reset stays pinned to the right edge, away from the
    // percentage which hugs the bar.
    private func trailingText(_ text: String, color: Color = ChimloTheme.quietPaper) -> some View {
        PixelText(text: text, pixelSize: 1, color: color, spacing: 1)
            .frame(width: 42, alignment: .trailing)
    }
}

private struct PixelCapacityGauge: View {
    let reading: CapacityReading
    let provider: CapacityProvider
    var segmentWidth: CGFloat = 5
    var segmentHeight: CGFloat = 7
    var segmentCount = 5
    var segmentSpacing: CGFloat = 2
    // When true the segments stretch to fill the available width instead of
    // using a fixed segmentWidth, so the bar spans the full row.
    var fillsWidth = false
    // When set, the gauge fills by this used-percentage (0...100) in the given
    // color instead of deriving from the reading. Used by the codex pace row.
    var usedOverride: Double?
    var colorOverride: Color?

    var body: some View {
        HStack(spacing: segmentSpacing) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Rectangle()
                    .fill(fillStyle(for: index))
                    .frame(
                        width: fillsWidth ? nil : segmentWidth,
                        height: segmentHeight
                    )
                    .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .accessibilityHidden(true)
    }

    private enum SegmentState { case lit, dimmed, empty }

    private var usedValue: Double? {
        if let usedOverride { return usedOverride }
        if let reading = reading.usedPercentage { return reading }
        return nil
    }

    private func fillStyle(for index: Int) -> Color {
        switch segmentState(index) {
        case .lit:    return fillColor
        case .dimmed: return fillColor.opacity(0.4)
        case .empty:  return ChimloTheme.mutedPaper.opacity(0.24)
        }
    }

    // The bar fills as capacity is consumed: a full bar means fully used.
    // Blocks light only once a whole segment's worth is used (round down, not
    // to nearest). Any leftover fraction below a full block shows as a single
    // dimmed block rather than lighting a whole one.
    private func segmentState(_ index: Int) -> SegmentState {
        guard let used = usedValue, used > 0 else { return .empty }
        let percentagePerSegment = 100 / Double(segmentCount)
        let fullSegments = min(segmentCount, Int((used / percentagePerSegment).rounded(.down)))
        if index < fullSegments { return .lit }
        let hasPartial = fullSegments < segmentCount
            && used - Double(fullSegments) * percentagePerSegment > 0
        if index == fullSegments && hasPartial { return .dimmed }
        return .empty
    }

    private var fillColor: Color {
        colorOverride ?? capacityColor(reading, provider: provider)
    }
}

private struct ProviderLogoView: View {
    let provider: CapacityProvider
    let size: CGFloat

    var body: some View {
        Image(nsImage: ProviderLogo.image(for: provider))
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(provider == .codex ? ChimloTheme.providerBlue : ChimloTheme.providerOrange)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private enum ProviderLogo {
    static func image(for provider: CapacityProvider) -> NSImage {
        let svg = provider == .codex ? openAISVG : claudeSVG
        return NSImage(data: Data(svg.utf8)) ?? NSImage(size: NSSize(width: 24, height: 24))
    }

    private static let claudeSVG = ##"<svg fill="#D97757" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"/></svg>"##
    private static let openAISVG = #"<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"/></svg>"#
}

private func capacityPercentageText(_ reading: CapacityReading) -> String {
    guard let remaining = reading.remainingPercentage else { return "—%" }
    return "\(Int(remaining.rounded()))%"
}

// Fraction (0...1) of the window that has elapsed — the "pace" you are burning
// the limit at, independent of how much has actually been used.
private func paceFraction(_ reading: CapacityReading, now: Date) -> Double? {
    guard let window = reading.window, let reset = window.resetsAt else { return nil }
    let duration: TimeInterval
    switch window.kind {
    case .weekly: duration = 7 * 24 * 60 * 60
    case .session: duration = 5 * 60 * 60
    }
    guard duration > 0 else { return nil }
    let elapsed = duration - reset.timeIntervalSince(now)
    return min(1, max(0, elapsed / duration))
}

// Urgency comes from colour, not row position: any bar and its percentage go
// amber above 80% used and red at 100%, on whichever row it sits.
private func capacityColor(_ reading: CapacityReading, provider: CapacityProvider) -> Color {
    guard let used = reading.usedPercentage else { return ChimloTheme.mutedPaper }
    if used >= 100 { return ChimloTheme.clayText }
    if used > 80 { return ChimloTheme.attention }
    return provider == .codex ? ChimloTheme.providerBlue : ChimloTheme.providerOrange
}

private func capacityDisclosureHelp(
    codexReading: CapacityReading,
    claudeReading: CapacityReading,
    isExpanded: Bool
) -> String {
    let action = isExpanded ? "Hide all usage limits." : "Show all usage limits."
    let readings: [(String, CapacityReading)] = [
        ("Codex", codexReading),
        ("Claude", claudeReading),
    ]
    let summaries = readings.map { provider, reading in
        guard let remaining = reading.remainingPercentage else {
            return "\(provider) weekly usage unavailable."
        }
        let qualifier = reading.isApproximate ? "approximately " : ""
        return "\(provider) weekly capacity: \(qualifier)\(Int(remaining.rounded())) percent remaining."
    }
    return "\(summaries.joined(separator: " ")) \(action)"
}

private func resetDuration(_ reading: CapacityReading, now: Date) -> String? {
    guard let window = reading.window, let reset = window.resetsAt else { return nil }
    return compactDuration(until: reset, now: now).uppercased()
}

private func rowHelp(
    label: String,
    provider: CapacityProvider,
    reading: CapacityReading
) -> String {
    let name = provider == .codex ? "Codex" : "Claude"
    guard let window = reading.window, let remaining = reading.remainingPercentage else {
        if let lastUpdatedAt = reading.lastUpdatedAt {
            return "\(name) \(label) usage unavailable. Last updated \(exactTimestamp(lastUpdatedAt))."
        }
        return "\(name) \(label) usage unavailable."
    }
    let qualifier = reading.isApproximate ? "Approximately " : ""
    let reset = window.resetsAt.map { " Resets \(exactTimestamp($0))." } ?? " Reset time unavailable."
    return "\(name) \(label): \(qualifier)\(Int(remaining.rounded())) percent remaining.\(reset)"
}

private func compactDuration(until date: Date, now: Date) -> String {
    let totalMinutes = max(0, Int(date.timeIntervalSince(now) / 60))
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60
    // Zero-pad the trailing unit so the column keeps a fixed width and the
    // digits do not jump as the countdown drops (e.g. "6D 04H" vs "5D 09H").
    if days > 0 { return String(format: "%dd %02dh", days, hours) }
    if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
    return String(format: "%02dm", minutes)
}

private func exactTimestamp(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .standard)
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

            trailingAccessory
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
            PixelAvatar(
                mood: session.mood,
                seed: seed,
                size: 34,
                reduceMotion: reduceMotion,
                palette: isClaudeSession ? .claudeOrange : .stateDriven
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ChimloTheme.paper)
                        .lineLimit(1)
                        .layoutPriority(1)

                    if onOpen != nil {
                        PixelJumpMark(
                            color: isHovering ? ChimloTheme.paper : ChimloTheme.mutedPaper
                        )
                        .fixedSize()
                    }

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
                .padding(.trailing, trailingAccessoryInset)

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

    private var trailingAccessory: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ZStack {
                SessionTimeBadge(
                    text: SessionRelativeTime.shortLabel(
                        since: session.updatedAt,
                        now: timeline.date
                    ),
                    accessibilityLabel: SessionRelativeTime.accessibilityLabel(
                        since: session.updatedAt,
                        now: timeline.date
                    )
                )
                .opacity(onArchive != nil && isHovering ? 0 : 1)
                .accessibilityHidden(onArchive != nil && isHovering)

                if let onArchive {
                    Button(action: onArchive) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 34, height: 28)
                    }
                    .buttonStyle(SessionArchiveButtonStyle())
                    .help("Archive in Chimlo")
                    .accessibilityLabel("Archive \(session.displayTitle) in Chimlo")
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
                    .accessibilityHidden(!isHovering)
                }
            }
        }
        .frame(width: 34, height: 28)
        .padding(.top, trailingAccessoryTopPadding)
        .padding(.trailing, 6)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private let trailingAccessoryInset: CGFloat = 36

    private var neutralBadgeBackground: Color {
        isHovering ? ChimloTheme.hoveredBadgeInk : ChimloTheme.badgeInk
    }

    private var trailingAccessoryTopPadding: CGFloat {
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
        isClaudeSession
            ? ChimloTheme.providerOrange
            : ChimloTheme.providerBlue
    }

    private var isClaudeSession: Bool {
        session.agentName.localizedCaseInsensitiveContains("claude")
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

private struct SessionTimeBadge: View {
    let text: String
    let accessibilityLabel: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(ChimloTheme.mutedPaper)
            .lineLimit(1)
            .monospacedDigit()
            .frame(width: 34, height: 18)
            .background(ChimloTheme.badgeInk)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel(accessibilityLabel)
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

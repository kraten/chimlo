import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: ApplicationModel

    private var bandHeight: CGFloat {
        max(model.islandLayout.expandedContentTopInset, 36)
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStatusBand(model: model)
                .frame(height: bandHeight)

            Group {
                switch model.onboardingStep {
                case .welcome:
                    welcome
                case .working:
                    working
                case .permission:
                    permission
                case let .resolving(allowed):
                    resolving(allowed: allowed)
                case let .complete(allowed):
                    complete(allowed: allowed)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chimlo first-run tour")
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chimlo lives in your notch.")
                .font(.system(size: 19, weight: .bold))
                .tracking(-0.25)
                .foregroundStyle(ChimloTheme.paper)
                .fixedSize(horizontal: false, vertical: true)

            Text("See agents, media, system controls, and usage.")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ChimloTheme.quietPaper)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 9) {
                HStack(spacing: 14) {
                    TourCapability(kind: .agents, model: model)
                    TourCapability(kind: .media, model: model)
                }
                HStack(spacing: 14) {
                    TourCapability(kind: .system, model: model)
                    TourCapability(kind: .usage, model: model)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 7) {
                PixelSystemGlyph(kind: .warning, color: ChimloTheme.attention, size: 12)
                    .padding(.top, 1)

                Text("Restart Chimlo after granting Accessibility access. Volume, brightness, and media controls activate on the next launch.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ChimloTheme.quietPaper)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                Button("Skip tour", action: model.finishOnboarding)
                    .buttonStyle(TourTextButtonStyle())

                Spacer(minLength: 8)

                Button("Run demo", action: model.beginOnboardingDemo)
                    .buttonStyle(ChimloButtonStyle(kind: .primary, compact: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 10) {
            TourStepHeader(step: "1 / 2", title: "Agent working")

            demoSessionRow

            Text("Chimlo shows live agent activity.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ChimloTheme.quietPaper)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Skip tour", action: model.finishOnboarding)
                    .buttonStyle(TourTextButtonStyle())
                Spacer()
                PixelText(text: "DEMO RUNNING", pixelSize: 1, color: ChimloTheme.mutedPaper, spacing: 1)
            }
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 9) {
            TourStepHeader(step: "2 / 2", title: "Your call")

            demoSessionRow

            HStack(alignment: .top, spacing: 9) {
                PixelSystemGlyph(kind: .warning, color: ChimloTheme.attention, size: 15)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Run project checks")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ChimloTheme.paper)
                    Text("swift test --filter LighthouseTests")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(ChimloTheme.quietPaper)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 9)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChimloTheme.attentionInk)
            .clipShape(SteppedPanelShape())

            HStack(spacing: 8) {
                Button("Deny") { model.resolveDemoPermission(allowed: false) }
                    .buttonStyle(ChimloButtonStyle(kind: .destructive, compact: true))
                    .keyboardShortcut(.cancelAction)

                Spacer(minLength: 8)

                Text("Demo only. Nothing runs.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ChimloTheme.mutedPaper)

                Button("Allow once") { model.resolveDemoPermission(allowed: true) }
                    .buttonStyle(ChimloButtonStyle(kind: .primary, compact: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func resolving(allowed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TourStepHeader(
                step: allowed ? "APPROVED" : "DENIED",
                title: allowed ? "Agent continues" : "Agent stopped"
            )

            demoSessionRow

            Text(
                allowed
                    ? "Chimlo waits for the result."
                    : "Nothing ran."
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ChimloTheme.quietPaper)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func complete(allowed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TourStepHeader(
                step: "DONE",
                title: "Demo complete"
            )

            demoSessionRow

            Text(
                allowed
                    ? "Finish returns Chimlo to the notch."
                    : "Nothing ran. Your choice was respected."
            )
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(ChimloTheme.quietPaper)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Replay demo", action: model.replayOnboarding)
                    .buttonStyle(TourTextButtonStyle())
                Spacer(minLength: 8)
                Button("Finish", action: model.finishOnboarding)
                    .buttonStyle(ChimloButtonStyle(kind: .primary, compact: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var demoSessionRow: some View {
        if let session = model.onboardingSession {
            SessionRow(
                session: session,
                seed: 0,
                reduceMotion: model.accessibility.reduceMotion,
                increasedContrast: model.accessibility.increaseContrast
            )
        }
    }
}

private struct OnboardingStatusBand: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        GeometryReader { geometry in
            if model.islandLayout.hasCameraHousing {
                let cameraWidth = min(
                    model.islandLayout.cameraHousingWidth,
                    geometry.size.width
                )
                let wingWidth = max(0, (geometry.size.width - cameraWidth) / 2)

                HStack(spacing: 0) {
                    brand
                        .padding(.leading, 16)
                        .frame(width: wingWidth, height: geometry.size.height, alignment: .leading)
                        .clipped()

                    Color.clear
                        .frame(width: cameraWidth, height: geometry.size.height)
                        .accessibilityHidden(true)

                    status
                        .padding(.trailing, 16)
                        .frame(width: wingWidth, height: geometry.size.height, alignment: .trailing)
                        .clipped()
                }
            } else {
                HStack(spacing: 0) {
                    brand
                    Spacer(minLength: 20)
                    status
                }
                .padding(.horizontal, 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chimlo is \(statusLabel.lowercased())")
    }

    private var brand: some View {
        PixelText(text: "CHIMLO", pixelSize: 1.1, color: ChimloTheme.paper, spacing: 1)
    }

    private var status: some View {
        HStack(spacing: 5) {
            PixelAvatar(
                mood: statusMood,
                seed: 7,
                size: 20,
                reduceMotion: model.accessibility.reduceMotion
            )
            PixelText(text: statusLabel, pixelSize: 1, color: statusColor, spacing: 1)
        }
    }

    private var statusMood: AvatarMood {
        switch model.onboardingStep {
        case .welcome: .idle
        case .working: .working
        case .permission: .waiting
        case let .resolving(allowed): allowed ? .working : .idle
        case let .complete(allowed): allowed ? .success : .idle
        }
    }

    private var statusLabel: String {
        switch model.onboardingStep {
        case .welcome: "READY"
        case .working: "WORK"
        case .permission: "WAIT"
        case let .resolving(allowed): allowed ? "WORK" : "STOP"
        case let .complete(allowed): allowed ? "DONE" : "SAFE"
        }
    }

    private var statusColor: Color {
        switch model.onboardingStep {
        case .working, .permission:
            ChimloTheme.attention
        case .complete(true):
            ChimloTheme.moss
        case .welcome, .resolving, .complete(false):
            ChimloTheme.paper
        }
    }
}

private enum TourCapabilityKind {
    case agents
    case media
    case system
    case usage
}

private struct TourCapability: View {
    let kind: TourCapabilityKind
    @ObservedObject var model: ApplicationModel

    var body: some View {
        HStack(spacing: 7) {
            icon
                .frame(width: 34, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                PixelText(text: label, pixelSize: 1, color: labelColor, spacing: 1)
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(ChimloTheme.mutedPaper)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized): \(detail)")
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .agents:
            PixelAvatar(
                mood: .working,
                seed: 0,
                size: 30,
                reduceMotion: model.accessibility.reduceMotion
            )
        case .media:
            PixelSystemGlyph(kind: .music, color: ChimloTheme.moss, size: 20)
        case .system:
            HStack(spacing: 2) {
                PixelSystemGlyph(kind: .speaker, color: ChimloTheme.paper, size: 15)
                PixelSystemGlyph(kind: .sun, color: ChimloTheme.attention, size: 15)
            }
        case .usage:
            TourUsageGlyph()
        }
    }

    private var label: String {
        switch kind {
        case .agents: "AGENTS"
        case .media: "MEDIA"
        case .system: "SYSTEM"
        case .usage: "USAGE"
        }
    }

    private var detail: String {
        switch kind {
        case .agents: "Work + approvals"
        case .media: "Now playing"
        case .system: "Volume + brightness"
        case .usage: "Codex + Claude"
        }
    }

    private var labelColor: Color {
        switch kind {
        case .agents, .system: ChimloTheme.attention
        case .media: ChimloTheme.moss
        case .usage: ChimloTheme.paper
        }
    }
}

private struct TourUsageGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(label: "7D", litCells: 3, color: ChimloTheme.providerBlue)
            row(label: "5H", litCells: 2, color: ChimloTheme.providerOrange)
        }
        .accessibilityHidden(true)
    }

    private func row(label: String, litCells: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            PixelText(text: label, pixelSize: 1, color: ChimloTheme.mutedPaper, spacing: 1)
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { index in
                    Rectangle()
                        .fill(index < litCells ? color : ChimloTheme.mutedPaper.opacity(0.28))
                        .frame(width: 3, height: 5)
                }
            }
        }
    }
}

private struct TourStepHeader: View {
    let step: String
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            PixelText(text: step, pixelSize: 1, color: ChimloTheme.mutedPaper, spacing: 1)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.1)
                .foregroundStyle(ChimloTheme.paper)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TourTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(
                configuration.isPressed ? ChimloTheme.paper : ChimloTheme.mutedPaper
            )
            .padding(.horizontal, 2)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
    }
}

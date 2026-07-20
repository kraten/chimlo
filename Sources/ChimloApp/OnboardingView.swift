import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        VStack(spacing: 15) {
            header

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chimlo onboarding")
    }

    private var header: some View {
        HStack {
            PixelText(text: "CHIMLO", pixelSize: 2, color: ChimloTheme.paper, spacing: 1)
            Spacer()
            if model.onboardingStep != .welcome {
                Button("Restart", action: model.replayOnboarding)
                    .buttonStyle(ChimloButtonStyle(kind: .quiet, compact: true))
            }
            Button("Hide") { model.panelMode = .compact }
                .buttonStyle(ChimloButtonStyle(kind: .quiet, compact: true))
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Your agents now have somewhere to land.")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ChimloTheme.paper)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: 22) {
                PixelAvatar(
                    mood: .idle,
                    seed: 4,
                    size: 112,
                    reduceMotion: model.accessibility.reduceMotion
                )

                VStack(alignment: .leading, spacing: 13) {
                    Text("Try the real island flow. Nothing leaves this Mac, and the demo runs no commands.")
                        .font(.system(size: 12))
                        .foregroundStyle(ChimloTheme.quietPaper)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Run the live demo", action: model.beginOnboardingDemo)
                        .buttonStyle(ChimloButtonStyle(kind: .primary))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("This is the live session view")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ChimloTheme.paper)
            Text("The avatar is working because the same session state that powers the island says it is working.")
                .font(.system(size: 12))
                .foregroundStyle(ChimloTheme.quietPaper)
            demoSessionRow
            HStack(spacing: 9) {
                PixelText(text: "1", pixelSize: 1.5, color: ChimloTheme.amber)
                Text("The demo will pause when the agent needs your decision.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChimloTheme.paper)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                PixelAvatar(mood: .waiting, seed: 1, size: 50, reduceMotion: model.accessibility.reduceMotion)
                VStack(alignment: .leading, spacing: 4) {
                    PixelText(text: "YOUR CALL", pixelSize: 1.5, color: ChimloTheme.paper, spacing: 1)
                    Text("The demo agent is waiting for approval.")
                        .font(.system(size: 12))
                        .foregroundStyle(ChimloTheme.quietPaper)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Run project checks")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ChimloTheme.paper)
                Text("swift test --filter LighthouseTests")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(ChimloTheme.paper)
                    .textSelection(.enabled)
                Text("This is a simulation. No process will be launched.")
                    .font(.system(size: 10))
                    .foregroundStyle(ChimloTheme.quietPaper)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ChimloTheme.raisedSurface(increasedContrast: model.accessibility.increaseContrast))
            .clipShape(SteppedPanelShape())

            HStack(spacing: 9) {
                Button("Deny", action: { model.resolveDemoPermission(allowed: false) })
                    .buttonStyle(ChimloButtonStyle(kind: .destructive))
                    .keyboardShortcut(.cancelAction)
                Button("Allow once", action: { model.resolveDemoPermission(allowed: true) })
                    .buttonStyle(ChimloButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func resolving(allowed: Bool) -> some View {
        HStack(spacing: 22) {
            PixelAvatar(
                mood: allowed ? .working : .idle,
                seed: 2,
                size: 88,
                reduceMotion: model.accessibility.reduceMotion
            )
            VStack(alignment: .leading, spacing: 9) {
                PixelText(
                    text: allowed ? "CHECKING" : "DENIED",
                    pixelSize: 1.6,
                    color: allowed ? ChimloTheme.amber : ChimloTheme.paper,
                    spacing: 1
                )
                Text(allowed ? "The approved work continues without stealing focus." : "The agent stopped. Nothing ran, and nothing changed.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ChimloTheme.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func complete(allowed: Bool) -> some View {
        HStack(spacing: 22) {
            PixelAvatar(
                mood: allowed ? .success : .idle,
                seed: 3,
                size: 96,
                reduceMotion: model.accessibility.reduceMotion
            )
            VStack(alignment: .leading, spacing: 11) {
                PixelText(
                    text: allowed ? "ALL CLEAR" : "GOOD CALL",
                    pixelSize: 1.6,
                    color: allowed ? ChimloTheme.moss : ChimloTheme.paper,
                    spacing: 1
                )
                Text(allowed ? "You approved in place, the work finished, and the island stayed out of your way." : "Deny is a first-class outcome. Chimlo never turns a missing response into permission.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ChimloTheme.paper)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Use Chimlo", action: model.finishOnboarding)
                    .buttonStyle(ChimloButtonStyle(kind: .primary))
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var demoSessionRow: some View {
        Group {
            if let session = model.sessions.first {
                SessionRow(
                    session: session,
                    seed: 0,
                    reduceMotion: model.accessibility.reduceMotion,
                    increasedContrast: model.accessibility.increaseContrast
                )
            }
        }
    }
}

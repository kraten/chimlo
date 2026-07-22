import AppKit
import SwiftUI

private enum ChimloSettingsTab: String, CaseIterable, Identifiable {
    case general
    case agents
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .agents: "Agents"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .agents: "terminal.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(nsColor: .systemGray)
        case .agents: Color(nsColor: .systemGreen)
        case .about: Color(nsColor: .systemGray)
        }
    }
}

private enum SettingsAppearance {
    static var detailBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }
}

struct ChimloSettingsView: View {
    @ObservedObject var model: ApplicationModel
    @State private var selectedTab: ChimloSettingsTab

    init(model: ApplicationModel) {
        self.model = model
        _selectedTab = State(initialValue: model.isUpdateTestMode ? .about : .general)
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedTab) {
                Section("Chimlo") {
                    sidebarRow(for: .general)
                    sidebarRow(for: .agents)
                    sidebarRow(for: .about)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()
                .ignoresSafeArea(.container, edges: .top)

            SettingsDetailPane(title: selectedTab.title) {
                switch selectedTab {
                case .general:
                    GeneralSettingsPane(model: model)
                case .agents:
                    AgentSettingsPane(model: model)
                case .about:
                    AboutSettingsPane(model: model)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 400, idealHeight: 440)
    }

    private func sidebarRow(for tab: ChimloSettingsTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.systemImage)
                .foregroundStyle(tab.tint)
                .frame(width: 17)
        }
        .tag(tab)
    }
}

private struct SettingsDetailPane<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsAppearance.detailBackground)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        Form {
            Section {
                Toggle("Play sounds", isOn: $model.soundsEnabled)
            } header: {
                Text("Sounds")
            }

            Section {
                Toggle("Show in Chimlo", isOn: $model.replacesSystemFeedback)

                LabeledContent("Status") {
                    feedbackStatus
                }
            } header: {
                Text("Volume and brightness")
            } footer: {
                Text("Restart Chimlo after granting Accessibility access. Volume, brightness, and media controls activate on the next launch. macOS takes over if Chimlo cannot show a control.")
            }

            Section {
                Button("Replay tour") {
                    model.replayOnboarding()
                }
            } header: {
                Text("Tour")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SettingsAppearance.detailBackground)
    }

    @ViewBuilder
    private var feedbackStatus: some View {
        switch model.systemFeedbackState {
        case .permissionRequired:
            HStack(spacing: 8) {
                Text(model.systemFeedbackStatusText)
                    .foregroundStyle(.secondary)
                Button("Allow") {
                    model.requestSystemFeedbackPermission()
                }
                .controlSize(.small)
                Button("Settings") {
                    model.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
        case .unavailable:
            HStack(spacing: 8) {
                Text(model.systemFeedbackStatusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Retry") {
                    model.retrySystemFeedback()
                }
                .controlSize(.small)
            }
        default:
            Text(model.systemFeedbackStatusText)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AgentSettingsPane: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        Form {
            Section {
                connectionRow(
                    title: "Codex",
                    detail: model.codexConnectionText,
                    state: model.codexConnectionState,
                    connect: model.connectCodex,
                    disconnect: model.disconnectCodex
                )

                connectionRow(
                    title: "Claude Code",
                    detail: model.claudeConnectionText,
                    state: model.claudeConnectionState,
                    connect: model.connectClaude,
                    disconnect: model.disconnectClaude
                )
            } header: {
                Text("Connections")
            } footer: {
                Text("Connect an agent to show its local sessions and usage.")
            }

            Section {
                Text("Session data stays on this Mac. Chimlo does not save prompts, responses, tool data, or files.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SettingsAppearance.detailBackground)
    }

    private func connectionRow(
        title: String,
        detail: String,
        state: AgentConnectionState,
        connect: @escaping () -> Void,
        disconnect: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            connectionStatus(for: state)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)
            connectionAction(state: state, connect: connect, disconnect: disconnect)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func connectionStatus(for state: AgentConnectionState) -> some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16)
        case .disconnected:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .frame(width: 16)
        case .installedAwaitingEvent, .receiving:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(nsColor: .systemGreen))
                .frame(width: 16)
        case .needsRepair:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color(nsColor: .systemOrange))
                .frame(width: 16)
        case .unavailable:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: .systemRed))
                .frame(width: 16)
        }
    }

    @ViewBuilder
    private func connectionAction(
        state: AgentConnectionState,
        connect: @escaping () -> Void,
        disconnect: @escaping () -> Void
    ) -> some View {
        switch state {
        case .checking:
            EmptyView()
        case .disconnected:
            Button("Connect", action: connect)
                .controlSize(.small)
        case .needsRepair:
            Button("Repair", action: connect)
                .controlSize(.small)
        case .installedAwaitingEvent, .receiving:
            Button("Disconnect", action: disconnect)
                .controlSize(.small)
        case .unavailable:
            Button("Retry") {
                model.refreshAgentConnections()
            }
            .controlSize(.small)
        }
    }
}

private struct AboutSettingsPane: View {
    @ObservedObject var model: ApplicationModel

    private var versionText: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.isEmpty else {
            return "Development build"
        }
        return "Version \(version)"
    }

    private var updateButtonTitle: String {
        model.updatePresentation?.actionTitle ?? "Check for Updates"
    }

    private var updateStatusText: String {
        model.updatePresentation?.statusText ?? "Not checked yet"
    }

    private var updateButtonIsDisabled: Bool {
        guard let presentation = model.updatePresentation else { return false }
        return !presentation.isActionable
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                PixelAvatar(
                    mood: .idle,
                    seed: 5,
                    size: 48,
                    reduceMotion: model.accessibility.reduceMotion
                )

                PixelText(text: "CHIMLO", pixelSize: 2, color: .primary, spacing: 1)

                Text("Agent activity in your notch")
                    .foregroundStyle(.secondary)

                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            Form {
                Section {
                    LabeledContent("Privacy") {
                        Text("Local only")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Source") {
                        Text("Open source")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("Status") {
                        HStack(spacing: 7) {
                            if model.updatePresentation?.isBusy == true {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            Text(updateStatusText)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(updateButtonTitle) {
                        if model.updatePresentation?.phase == .available {
                            model.installUpdate()
                        } else {
                            model.checkForUpdates()
                        }
                    }
                    .disabled(updateButtonIsDisabled)
                } header: {
                    Text("Updates")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(SettingsAppearance.detailBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

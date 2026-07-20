import AppKit
import SwiftUI

private enum ChimloSettingsTab: String, CaseIterable, Identifiable {
    case general
    case agents
    case accessibility
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .agents: "Agents"
        case .accessibility: "Accessibility"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .agents: "terminal.fill"
        case .accessibility: "accessibility"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(nsColor: .systemGray)
        case .agents: Color(nsColor: .systemGreen)
        case .accessibility: Color(nsColor: .systemBlue)
        case .about: Color(nsColor: .systemGray)
        }
    }
}

private enum SettingsAppearance {
    static var detailBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    static var sidebarSeparator: Color {
        Color(nsColor: .separatorColor)
    }
}

struct ChimloSettingsView: View {
    @ObservedObject var model: ApplicationModel
    @State private var selectedTab: ChimloSettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selectedTab) {
                Section("Chimlo") {
                    sidebarRow(for: .general)
                    sidebarRow(for: .agents)
                    sidebarRow(for: .accessibility)
                }

                Section("App") {
                    sidebarRow(for: .about)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(SettingsAppearance.sidebarSeparator)
                    .frame(width: 1)
                    .ignoresSafeArea(.container, edges: .top)
                    .accessibilityHidden(true)
            }

            SettingsDetailPane(title: selectedTab.title) {
                switch selectedTab {
                case .general:
                    GeneralSettingsPane(model: model)
                case .agents:
                    AgentSettingsPane(model: model)
                case .accessibility:
                    AccessibilitySettingsPane(model: model)
                case .about:
                    AboutSettingsPane(model: model)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 440, idealHeight: 480)
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
                Toggle("Play event sounds", isOn: $model.soundsEnabled)

                LabeledContent("Completion cue") {
                    Button("Play") {
                        model.previewSound()
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("Sound")
            } footer: {
                Text("Sounds accompany visible state changes and can be turned off at any time.")
            }

            Section {
                Toggle("Show a preview session when disconnected", isOn: $model.keepPreviewSession)

                LabeledContent("First-run tour") {
                    Button("Replay") {
                        model.replayOnboarding()
                    }
                    .controlSize(.small)
                }

                LabeledContent("Preview data") {
                    Button("Clear", role: .destructive) {
                        model.clearPreviewData()
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("Preview and onboarding")
            } footer: {
                Text("Preview sessions are local examples. They never run commands or send data off this Mac.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SettingsAppearance.detailBackground)
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
                Text("Agent connections")
            } footer: {
                Text("Connect installs Chimlo's local observer. Existing agent settings are preserved.")
            }

            Section("Local bridge") {
                LabeledContent("Status", value: model.serverStatusText)

                LabeledContent("Agent status") {
                    Button("Refresh") {
                        model.refreshAgentConnections()
                    }
                    .controlSize(.small)
                }
            }

            Section {
                Text("Chimlo keeps minimal session metadata on this Mac. Prompt text, assistant responses, tool input and output, and file contents are not retained.")
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

private struct AccessibilitySettingsPane: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        Form {
            Section {
                accessibilityRow("Reduce Motion", enabled: model.accessibility.reduceMotion)
                accessibilityRow("Reduce Transparency", enabled: model.accessibility.reduceTransparency)
                accessibilityRow("Increase Contrast", enabled: model.accessibility.increaseContrast)
            } header: {
                Text("macOS display settings")
            } footer: {
                Text("Chimlo follows these system preferences automatically. Avatar animation stops when Reduce Motion is enabled.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(SettingsAppearance.detailBackground)
    }

    private func accessibilityRow(_ title: String, enabled: Bool) -> some View {
        LabeledContent(title) {
            Text(enabled ? "On" : "Off")
                .foregroundStyle(.secondary)
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

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                PixelAvatar(
                    mood: .idle,
                    seed: 5,
                    size: 62,
                    reduceMotion: model.accessibility.reduceMotion
                )

                PixelText(text: "CHIMLO", pixelSize: 2, color: .primary, spacing: 1)

                Text("Local agent activity, at a glance")
                    .foregroundStyle(.secondary)

                Text(versionText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            Form {
                Section {
                    LabeledContent("Data") {
                        Text("Stays on this Mac")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Implementation") {
                        Text("Open source")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About Chimlo")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(SettingsAppearance.detailBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

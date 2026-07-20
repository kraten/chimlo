import ChimloCore
import Foundation

enum AgentProvider: String, CaseIterable, Sendable {
    case codex
    case claude

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }
}

enum AgentConnectionState: Equatable, Sendable {
    case checking
    case disconnected
    case installedAwaitingEvent
    case receiving(Date)
    case needsRepair
    case unavailable(String)

    var isInstalled: Bool {
        switch self {
        case .installedAwaitingEvent, .receiving:
            true
        case .checking, .disconnected, .needsRepair, .unavailable:
            false
        }
    }

    var isReceiving: Bool {
        if case .receiving = self { return true }
        return false
    }
}

/// Owns the complete hook-installation seam for supported agents: stable helper
/// deployment, read-only status, full preview, marker-scoped merge, validation,
/// backup, and removal.
struct AgentIntegrationManager {
    let codexHooksURL: URL
    let claudeSettingsURL: URL
    let bundledHelperURL: URL
    let stableHelperURL: URL

    static func live(bundle: Bundle = .main, fileManager: FileManager = .default) -> AgentIntegrationManager {
        let home = fileManager.homeDirectoryForCurrentUser
        return AgentIntegrationManager(
            codexHooksURL: home
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("hooks.json"),
            claudeSettingsURL: home
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json"),
            bundledHelperURL: bundle.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("chimlo"),
            stableHelperURL: home
                .appendingPathComponent("Library/Application Support/Chimlo/bin", isDirectory: true)
                .appendingPathComponent("chimlo")
        )
    }

    /// Copies the signed helper out of the movable app bundle. Hook files only
    /// reference this stable path, so renaming or relocating Chimlo.app does not
    /// silently break future events.
    @discardableResult
    func prepareStableHelper(fileManager: FileManager = .default) throws -> URL {
        guard fileManager.isExecutableFile(atPath: bundledHelperURL.path) else {
            if fileManager.isExecutableFile(atPath: stableHelperURL.path) {
                return stableHelperURL
            }
            throw IntegrationError.helperUnavailable
        }

        let directory = stableHelperURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let needsCopy = !fileManager.fileExists(atPath: stableHelperURL.path)
            || !fileManager.contentsEqual(
                atPath: bundledHelperURL.path,
                andPath: stableHelperURL.path
            )

        if needsCopy {
            let stagingURL = directory.appendingPathComponent("chimlo.installing")
            if fileManager.fileExists(atPath: stagingURL.path) {
                try fileManager.removeItem(at: stagingURL)
            }
            try fileManager.copyItem(at: bundledHelperURL, to: stagingURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)

            if fileManager.fileExists(atPath: stableHelperURL.path) {
                _ = try fileManager.replaceItemAt(stableHelperURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: stableHelperURL)
            }
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stableHelperURL.path)
        guard fileManager.isExecutableFile(atPath: stableHelperURL.path) else {
            throw IntegrationError.helperUnavailable
        }
        return stableHelperURL
    }

    func status(
        for provider: AgentProvider,
        lastReceiptAt: Date?,
        fileManager: FileManager = .default
    ) -> AgentConnectionState {
        guard fileManager.isExecutableFile(atPath: stableHelperURL.path) else {
            return .unavailable("Package Chimlo once to install its local helper")
        }

        do {
            let data = try configurationData(for: provider, fileManager: fileManager)
            switch provider {
            case .codex:
                switch try CodexHookConfiguration.installationState(
                    in: data,
                    helperPath: stableHelperURL.path
                ) {
                case .missing: return .disconnected
                case .needsRepair: return .needsRepair
                case .current: break
                }
            case .claude:
                switch try ClaudeHookConfiguration.installationState(
                    in: data,
                    helperPath: stableHelperURL.path
                ) {
                case .missing: return .disconnected
                case .needsRepair: return .needsRepair
                case .current: break
                }
            }

            if let lastReceiptAt, lastReceiptAt >= Date.now.addingTimeInterval(-30 * 60) {
                return .receiving(lastReceiptAt)
            }
            return .installedAwaitingEvent
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    func preview(for provider: AgentProvider, fileManager: FileManager = .default) throws -> String {
        _ = try prepareStableHelper(fileManager: fileManager)
        let existing = try configurationData(for: provider, fileManager: fileManager)
        let data: Data
        switch provider {
        case .codex:
            data = try CodexHookConfiguration.merging(
                existingData: existing,
                helperPath: stableHelperURL.path
            ).data
        case .claude:
            data = try ClaudeHookConfiguration.merging(
                existingData: existing,
                helperPath: stableHelperURL.path
            ).data
        }
        return String(decoding: data, as: UTF8.self)
    }

    func connect(_ provider: AgentProvider, fileManager: FileManager = .default) throws {
        _ = try prepareStableHelper(fileManager: fileManager)
        let destination = configurationURL(for: provider)
        let existing = try configurationData(for: provider, fileManager: fileManager)
        let plannedData: Data
        let changed: Bool

        switch provider {
        case .codex:
            let plan = try CodexHookConfiguration.merging(
                existingData: existing,
                helperPath: stableHelperURL.path
            )
            plannedData = plan.data
            changed = plan.changed
        case .claude:
            let plan = try ClaudeHookConfiguration.merging(
                existingData: existing,
                helperPath: stableHelperURL.path
            )
            plannedData = plan.data
            changed = plan.changed
        }
        guard changed else { return }

        try writeConfiguration(
            plannedData,
            to: destination,
            existingData: existing,
            provider: provider,
            fileManager: fileManager
        )
    }

    func disconnect(_ provider: AgentProvider, fileManager: FileManager = .default) throws {
        let destination = configurationURL(for: provider)
        guard fileManager.fileExists(atPath: destination.path) else { return }
        let existing = try Data(contentsOf: destination)
        let data: Data
        let changed: Bool
        switch provider {
        case .codex:
            let plan = try CodexHookConfiguration.removing(existingData: existing)
            data = plan.data
            changed = plan.changed
        case .claude:
            let plan = try ClaudeHookConfiguration.removing(existingData: existing)
            data = plan.data
            changed = plan.changed
        }
        guard changed else { return }

        let permissions = try fileManager.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: permissions ?? NSNumber(value: 0o600)],
            ofItemAtPath: destination.path
        )
    }

    private func configurationURL(for provider: AgentProvider) -> URL {
        switch provider {
        case .codex: codexHooksURL
        case .claude: claudeSettingsURL
        }
    }

    private func configurationData(
        for provider: AgentProvider,
        fileManager: FileManager
    ) throws -> Data? {
        let url = configurationURL(for: provider)
        return fileManager.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
    }

    private func writeConfiguration(
        _ data: Data,
        to destination: URL,
        existingData: Data?,
        provider: AgentProvider,
        fileManager: FileManager
    ) throws {
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let permissions = try existingData.flatMap { _ in
            try fileManager.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        }
        try preserveFirstBackup(existingData, destination: destination, fileManager: fileManager)
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: permissions ?? NSNumber(value: 0o600)],
            ofItemAtPath: destination.path
        )

        let written = try Data(contentsOf: destination)
        let isCurrent: Bool
        switch provider {
        case .codex:
            isCurrent = try CodexHookConfiguration.installationState(
                in: written,
                helperPath: stableHelperURL.path
            ) == .current
        case .claude:
            isCurrent = try ClaudeHookConfiguration.installationState(
                in: written,
                helperPath: stableHelperURL.path
            ) == .current
        }
        guard isCurrent else { throw IntegrationError.validationFailed(provider.displayName) }
    }

    private func preserveFirstBackup(
        _ existingData: Data?,
        destination: URL,
        fileManager: FileManager
    ) throws {
        guard let existingData else { return }
        let backupURL = destination.appendingPathExtension("chimlo-backup")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        try existingData.write(to: backupURL, options: .atomic)
        let permissions = try fileManager.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        try fileManager.setAttributes(
            [.posixPermissions: permissions ?? NSNumber(value: 0o600)],
            ofItemAtPath: backupURL.path
        )
    }

    private enum IntegrationError: Error, LocalizedError {
        case helperUnavailable
        case validationFailed(String)

        var errorDescription: String? {
            switch self {
            case .helperUnavailable:
                "The packaged Chimlo helper is unavailable"
            case let .validationFailed(provider):
                "The \(provider) hook merge could not be validated"
            }
        }
    }
}

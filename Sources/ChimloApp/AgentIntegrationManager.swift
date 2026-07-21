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
    let claudeStatusLineWrapperURL: URL
    let claudeStatusLineDelegateURL: URL
    let claudeCapacityCacheURL: URL

    static func live(bundle: Bundle = .main, fileManager: FileManager = .default) -> AgentIntegrationManager {
        let home = fileManager.homeDirectoryForCurrentUser
        let applicationSupport = home
            .appendingPathComponent("Library/Application Support/Chimlo", isDirectory: true)
        let binaryDirectory = applicationSupport.appendingPathComponent("bin", isDirectory: true)
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
            stableHelperURL: binaryDirectory.appendingPathComponent("chimlo"),
            claudeStatusLineWrapperURL: binaryDirectory
                .appendingPathComponent("chimlo-claude-statusline"),
            claudeStatusLineDelegateURL: binaryDirectory
                .appendingPathComponent("chimlo-claude-statusline-delegate"),
            claudeCapacityCacheURL: applicationSupport
                .appendingPathComponent("capacity", isDirectory: true)
                .appendingPathComponent("claude.json")
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
                let hookState = try ClaudeHookConfiguration.installationState(
                    in: data,
                    helperPath: stableHelperURL.path
                )
                let statusLineState = try ClaudeStatusLineConfiguration.installationState(
                    in: data,
                    wrapperPath: claudeStatusLineWrapperURL.path
                )
                if hookState == .missing && statusLineState == .missing { return .disconnected }
                guard hookState == .current,
                      statusLineState == .current,
                      fileManager.isExecutableFile(atPath: claudeStatusLineWrapperURL.path) else {
                    return .needsRepair
                }
                if try ClaudeStatusLineConfiguration.originalCommand(in: data ?? Data()) != nil,
                   !fileManager.isExecutableFile(atPath: claudeStatusLineDelegateURL.path) {
                    return .needsRepair
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
            let hookPlan = try ClaudeHookConfiguration.merging(
                existingData: existing,
                helperPath: stableHelperURL.path
            )
            data = try ClaudeStatusLineConfiguration.merging(
                existingData: hookPlan.data,
                wrapperPath: claudeStatusLineWrapperURL.path
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
            let hookPlan = try ClaudeHookConfiguration.merging(
                existingData: existing,
                helperPath: stableHelperURL.path
            )
            let statusLinePlan = try ClaudeStatusLineConfiguration.merging(
                existingData: hookPlan.data,
                wrapperPath: claudeStatusLineWrapperURL.path
            )
            plannedData = statusLinePlan.data
            changed = hookPlan.changed || statusLinePlan.changed
            try prepareClaudeStatusLineScripts(
                originalCommand: try ClaudeStatusLineConfiguration.originalCommand(
                    in: plannedData
                ),
                fileManager: fileManager
            )
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
        guard fileManager.fileExists(atPath: destination.path) else {
            if provider == .claude { removeClaudeStatusLineScripts(fileManager: fileManager) }
            return
        }
        let existing = try Data(contentsOf: destination)
        let data: Data
        let changed: Bool
        switch provider {
        case .codex:
            let plan = try CodexHookConfiguration.removing(existingData: existing)
            data = plan.data
            changed = plan.changed
        case .claude:
            let hookPlan = try ClaudeHookConfiguration.removing(existingData: existing)
            let statusLinePlan = try ClaudeStatusLineConfiguration.removing(
                existingData: hookPlan.data
            )
            data = statusLinePlan.data
            changed = hookPlan.changed || statusLinePlan.changed
        }
        guard changed else {
            if provider == .claude { removeClaudeStatusLineScripts(fileManager: fileManager) }
            return
        }

        let permissions = try fileManager.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: permissions ?? NSNumber(value: 0o600)],
            ofItemAtPath: destination.path
        )
        if provider == .claude { removeClaudeStatusLineScripts(fileManager: fileManager) }
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
                && ClaudeStatusLineConfiguration.installationState(
                    in: written,
                    wrapperPath: claudeStatusLineWrapperURL.path
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

    private func prepareClaudeStatusLineScripts(
        originalCommand: String?,
        fileManager: FileManager
    ) throws {
        let directory = claudeStatusLineWrapperURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let helper = shellQuoted(stableHelperURL.path)
        let cache = shellQuoted(claudeCapacityCacheURL.path)
        let delegate = shellQuoted(claudeStatusLineDelegateURL.path)
        let wrapper = """
        #!/bin/sh
        # Chimlo Claude capacity bridge. Managed by Chimlo.
        input=$(cat)
        printf '%s' "$input" | \(helper) __capture-claude-capacity \(cache) >/dev/null 2>&1 || true
        if [ -x \(delegate) ]; then
          printf '%s' "$input" | \(delegate)
        fi
        """ + "\n"
        try writeExecutable(wrapper, to: claudeStatusLineWrapperURL, fileManager: fileManager)

        if let originalCommand {
            let delegateScript = "#!/bin/sh\n# Original Claude Code status line preserved by Chimlo.\n\(originalCommand)\n"
            try writeExecutable(
                delegateScript,
                to: claudeStatusLineDelegateURL,
                fileManager: fileManager
            )
        } else if fileManager.fileExists(atPath: claudeStatusLineDelegateURL.path) {
            try fileManager.removeItem(at: claudeStatusLineDelegateURL)
        }
    }

    private func removeClaudeStatusLineScripts(fileManager: FileManager) {
        for url in [claudeStatusLineWrapperURL, claudeStatusLineDelegateURL]
            where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func writeExecutable(
        _ contents: String,
        to url: URL,
        fileManager: FileManager
    ) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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

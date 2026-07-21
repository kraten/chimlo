import AppKit
import Darwin
import Foundation

/// Pauses only Apple's visual OSD helper while Chimlo has a verified active
/// key filter. A separate bundled guard resumes the helper if this app crashes.
@MainActor
final class NativeOverlayGate {
    private static let helperBundleID = "com.apple.OSDUIHelper"
    private static let helperService = "com.apple.OSDUIHelper"

    private var workspaceObservers: [NSObjectProtocol] = []
    private var suspendedProcessIDs: Set<pid_t> = []
    private var recoveryGuard: Process?
    private var isArming = false
    private(set) var isActive = false

    func activate() async -> Bool {
        if isActive { return true }
        guard launchRecoveryGuard() else { return false }

        isArming = true
        installWorkspaceObservers()
        let application = await ensureHelperIsRunning()
        guard let application, pause(application) else {
            restoreAndReset()
            return false
        }
        isArming = false
        isActive = true
        return true
    }

    func deactivate() {
        restoreAndReset()
    }

    private func installWorkspaceObservers() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.isActive || self.isArming,
                      application.bundleIdentifier == Self.helperBundleID else { return }
                _ = self.pause(application)
            }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                Self.runningHelpers.forEach { _ = self.pause($0) }
            }
        })
    }

    private func ensureHelperIsRunning() async -> NSRunningApplication? {
        if let current = Self.runningHelpers.first { return current }

        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        command.arguments = ["kickstart", "gui/\(getuid())/\(Self.helperService)"]
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        do {
            try command.run()
        } catch {
            return nil
        }

        for _ in 0..<40 {
            if let application = Self.runningHelpers.first { return application }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return Self.runningHelpers.first
    }

    private func pause(_ application: NSRunningApplication) -> Bool {
        let processID = application.processIdentifier
        guard processID > 0 else { return false }
        if suspendedProcessIDs.contains(processID) { return true }
        guard Darwin.kill(processID, SIGSTOP) == 0 else { return false }
        suspendedProcessIDs.insert(processID)
        return true
    }

    private func restoreAndReset() {
        isActive = false
        isArming = false

        let processIDs = suspendedProcessIDs.union(Self.runningHelpers.map(\.processIdentifier))
        processIDs.filter { $0 > 0 }.forEach { _ = Darwin.kill($0, SIGCONT) }
        suspendedProcessIDs.removeAll()

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()

        recoveryGuard?.terminate()
        recoveryGuard = nil
    }

    private func launchRecoveryGuard() -> Bool {
        if let recoveryGuard, recoveryGuard.isRunning { return true }
        guard let executable = recoveryGuardExecutable else { return false }

        let guardProcess = Process()
        guardProcess.executableURL = executable
        guardProcess.arguments = ["__native-overlay-guard", "\(ProcessInfo.processInfo.processIdentifier)"]
        guardProcess.standardOutput = FileHandle.nullDevice
        guardProcess.standardError = FileHandle.nullDevice
        do {
            try guardProcess.run()
            recoveryGuard = guardProcess
            return true
        } catch {
            return false
        }
    }

    private var recoveryGuardExecutable: URL? {
        let packaged = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("chimlo", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: packaged.path) { return packaged }

        if let sibling = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("chimlo", isDirectory: false),
           FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        return nil
    }

    private static var runningHelpers: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: helperBundleID)
    }
}

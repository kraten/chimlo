import AppKit
import ChimloCore
import Foundation
import Sparkle

@MainActor
final class ChimloUpdater: NSObject, SPUUserDriver {
    var presentationChanged: ((AppUpdatePresentation?) -> Void)?

    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: self,
        delegate: nil
    )
    private var availableUpdateReply: ((SPUUserUpdateChoice) -> Void)?
    private var expectedDownloadLength: UInt64?
    private var receivedDownloadLength: UInt64 = 0
    private var started = false
    private var shouldPresentErrors = false

    func start() {
        guard !started, isConfigured else { return }
        do {
            try updater.start()
            started = true
        } catch {
            NSLog("Chimlo updater failed to start: %@", error.localizedDescription)
        }
    }

    func checkForUpdates() {
        shouldPresentErrors = true
        if !started {
            start()
            guard started else { return }
        }
        publish(.checking)
        updater.checkForUpdates()
    }

    func installAvailableUpdate() {
        guard let reply = availableUpdateReply else {
            checkForUpdates()
            return
        }
        availableUpdateReply = nil
        shouldPresentErrors = true
        publish(.downloading(progress: nil))
        reply(.install)
    }

    private var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feed.isEmpty,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.isEmpty else { return false }
        return true
    }

    private func publish(_ phase: AppUpdatePhase?) {
        presentationChanged?(phase.map(AppUpdatePresentation.init(phase:)))
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            automaticUpdateDownloading: false,
            sendSystemProfile: false
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        publish(.checking)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        guard !appcastItem.isInformationOnlyUpdate else {
            reply(.dismiss)
            if let infoURL = appcastItem.infoURL {
                NSWorkspace.shared.open(infoURL)
            }
            return
        }
        availableUpdateReply = reply
        publish(.available)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        availableUpdateReply = nil
        shouldPresentErrors = false
        publish(nil)
        acknowledgement()
    }

    func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        availableUpdateReply = nil
        publish(shouldPresentErrors ? .failed : nil)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedDownloadLength = nil
        receivedDownloadLength = 0
        publish(.downloading(progress: nil))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedDownloadLength = expectedContentLength > 0 ? expectedContentLength : nil
        publishDownloadProgress()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedDownloadLength += length
        publishDownloadProgress()
    }

    func showDownloadDidStartExtractingUpdate() {
        publish(.preparing)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        publish(.preparing)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        publish(.installing)
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        publish(.installing)
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        publish(nil)
        shouldPresentErrors = false
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        availableUpdateReply = nil
        expectedDownloadLength = nil
        receivedDownloadLength = 0
        shouldPresentErrors = false
        publish(nil)
    }

    private func publishDownloadProgress() {
        let progress = expectedDownloadLength.map { expected in
            Double(receivedDownloadLength) / Double(expected)
        }
        publish(.downloading(progress: progress))
    }
}

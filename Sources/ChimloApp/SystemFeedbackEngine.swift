import AppKit
import ApplicationServices
import ChimloCore
import Foundation

enum SystemFeedbackEngineState: Equatable {
    case disabled
    case starting
    case permissionRequired
    case active
    case unavailable(String)
}

@MainActor
final class SystemFeedbackEngine: HardwareKeyRouterDelegate {
    var presentationChanged: ((SystemFeedbackPresentation) -> Void)?
    var stateChanged: ((SystemFeedbackEngineState) -> Void)?

    private let keys = HardwareKeyRouter()
    private let audio = AudioOutputBridge()
    private let display = BuiltInDisplayBridge()
    private let nativeOverlay = NativeOverlayGate()
    private var activationTask: Task<Void, Never>?
    private var wantsReplacement = false
    private var state: SystemFeedbackEngineState = .disabled {
        didSet {
            guard state != oldValue else { return }
            stateChanged?(state)
        }
    }

    init() {
        keys.delegate = self
        audio.routeChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAfterAudioRouteChange()
            }
        }
    }

    func setEnabled(_ enabled: Bool, promptForPermission: Bool) {
        wantsReplacement = enabled
        activationTask?.cancel()
        activationTask = nil

        guard enabled else {
            disarm()
            state = .disabled
            return
        }
        beginActivation(promptForPermission: promptForPermission)
    }

    func retry(promptForPermission: Bool) {
        guard wantsReplacement else { return }
        beginActivation(promptForPermission: promptForPermission)
    }

    func stop() {
        wantsReplacement = false
        activationTask?.cancel()
        activationTask = nil
        disarm()
        state = .disabled
    }

    func hardwareKeyRouter(_ router: HardwareKeyRouter, received command: HardwareKeyCommand) {
        let presentation: SystemFeedbackPresentation?
        switch command {
        case let .volume(direction, fine):
            presentation = audio.adjust(direction: direction, fine: fine)
        case .mute:
            presentation = audio.toggleMute()
        case let .brightness(direction, fine):
            presentation = display.adjust(direction: direction, fine: fine)
        }

        guard let presentation else {
            failOpen(reason: "The current audio or display route cannot be controlled")
            return
        }
        presentationChanged?(presentation)
    }

    private func beginActivation(promptForPermission: Bool) {
        activationTask?.cancel()
        activationTask = Task { [weak self] in
            guard let self else { return }
            await self.activate(promptForPermission: promptForPermission)
        }
    }

    private func activate(promptForPermission: Bool) async {
        disarm()
        guard wantsReplacement else { return }
        guard AXIsProcessTrusted() else {
            if promptForPermission {
                _ = AXIsProcessTrustedWithOptions(
                    ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                )
            }
            state = .permissionRequired
            return
        }
        guard audio.isUsable, display.isUsable else {
            state = .unavailable("The current audio output or built-in display is unavailable")
            return
        }
        guard keys.start() else {
            state = .unavailable("macOS did not allow Chimlo to filter media keys")
            return
        }

        state = .starting
        keys.routing = .disabled
        guard await nativeOverlay.activate(), wantsReplacement, !Task.isCancelled else {
            disarm()
            if wantsReplacement {
                state = .unavailable("Chimlo could not safely prepare native HUD recovery")
            }
            return
        }

        keys.routing = HardwareKeyRouting(volume: true, brightness: true)
        state = .active
    }

    private func refreshAfterAudioRouteChange() {
        guard wantsReplacement else { return }
        beginActivation(promptForPermission: false)
    }

    private func failOpen(reason: String) {
        disarm()
        state = .unavailable(reason)
    }

    private func disarm() {
        keys.routing = .disabled
        keys.stop()
        nativeOverlay.deactivate()
    }
}

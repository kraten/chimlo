import ChimloCore
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import IOKit

final class AudioOutputBridge: @unchecked Sendable {
    var routeChanged: (@Sendable () -> Void)?

    private let callbackQueue = DispatchQueue(label: "dev.chimlo.audio-route")
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var rememberedAudibleLevel = 0.5

    init() {
        installDefaultDeviceListener()
    }

    deinit {
        guard let defaultDeviceListener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            callbackQueue,
            defaultDeviceListener
        )
    }

    var isUsable: Bool {
        guard let device = defaultOutputDevice() else { return false }
        return !writableElements(for: kAudioDevicePropertyVolumeScalar, device: device).isEmpty
    }

    func adjust(direction: Int, fine: Bool) -> SystemFeedbackPresentation? {
        guard let device = defaultOutputDevice(),
              let current = readVolume(device: device) else { return nil }
        let target = SystemFeedbackPolicy.adjustedValue(
            from: Double(current),
            direction: direction,
            fine: fine
        )
        if target > 0 { setMuted(false, device: device) }
        guard writeVolume(Float(target), device: device) else { return nil }
        if target > 0 { rememberedAudibleLevel = target }
        let muted = target == 0 || readMuted(device: device)
        return SystemFeedbackPresentation(
            kind: .outputVolume,
            value: target,
            isMuted: muted
        )
    }

    func toggleMute() -> SystemFeedbackPresentation? {
        guard let device = defaultOutputDevice(),
              let current = readVolume(device: device) else { return nil }
        let currentlyMuted = readMuted(device: device) || current <= 0.001

        if hasWritableProperty(kAudioDevicePropertyMute, device: device) {
            guard setMuted(!currentlyMuted, device: device) else { return nil }
            return SystemFeedbackPresentation(
                kind: .outputVolume,
                value: Double(current),
                isMuted: !currentlyMuted
            )
        }

        if currentlyMuted {
            let restored = Float(max(rememberedAudibleLevel, SystemFeedbackPolicy.standardStep))
            guard writeVolume(restored, device: device) else { return nil }
            return SystemFeedbackPresentation(kind: .outputVolume, value: Double(restored))
        }

        rememberedAudibleLevel = Double(max(current, Float(SystemFeedbackPolicy.standardStep)))
        guard writeVolume(0, device: device) else { return nil }
        return SystemFeedbackPresentation(kind: .outputVolume, value: 0, isMuted: true)
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func installDefaultDeviceListener() {
        var address = Self.defaultOutputAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.routeChanged?()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            callbackQueue,
            listener
        )
        if status == noErr { defaultDeviceListener = listener }
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.defaultOutputAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private func readVolume(device: AudioDeviceID) -> Float? {
        let elements = readableElements(for: kAudioDevicePropertyVolumeScalar, device: device)
        let values = elements.compactMap { readFloat(
            selector: kAudioDevicePropertyVolumeScalar,
            element: $0,
            device: device
        ) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    private func writeVolume(_ value: Float, device: AudioDeviceID) -> Bool {
        let clamped = min(1, max(0, value))
        let elements = writableElements(for: kAudioDevicePropertyVolumeScalar, device: device)
        guard !elements.isEmpty else { return false }
        return elements.reduce(true) { success, element in
            var next = clamped
            var address = propertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                element: element
            )
            let status = AudioObjectSetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<Float>.size),
                &next
            )
            return success && status == noErr
        }
    }

    private func readMuted(device: AudioDeviceID) -> Bool {
        let elements = readableElements(for: kAudioDevicePropertyMute, device: device)
        return elements.contains { element in
            var address = propertyAddress(selector: kAudioDevicePropertyMute, element: element)
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
                && muted != 0
        }
    }

    @discardableResult
    private func setMuted(_ muted: Bool, device: AudioDeviceID) -> Bool {
        let elements = writableElements(for: kAudioDevicePropertyMute, device: device)
        guard !elements.isEmpty else { return false }
        return elements.reduce(true) { success, element in
            var value: UInt32 = muted ? 1 : 0
            var address = propertyAddress(selector: kAudioDevicePropertyMute, element: element)
            let status = AudioObjectSetPropertyData(
                device,
                &address,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &value
            )
            return success && status == noErr
        }
    }

    private func readFloat(
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement,
        device: AudioDeviceID
    ) -> Float? {
        var address = propertyAddress(selector: selector, element: element)
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private func hasWritableProperty(
        _ selector: AudioObjectPropertySelector,
        device: AudioDeviceID
    ) -> Bool {
        !writableElements(for: selector, device: device).isEmpty
    }

    private func readableElements(
        for selector: AudioObjectPropertySelector,
        device: AudioDeviceID
    ) -> [AudioObjectPropertyElement] {
        let available = candidateElements.filter { element in
            var address = propertyAddress(selector: selector, element: element)
            return AudioObjectHasProperty(device, &address)
        }
        if available.contains(kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return available
    }

    private func writableElements(
        for selector: AudioObjectPropertySelector,
        device: AudioDeviceID
    ) -> [AudioObjectPropertyElement] {
        let writable = candidateElements.filter { element in
            var address = propertyAddress(selector: selector, element: element)
            guard AudioObjectHasProperty(device, &address) else { return false }
            var settable = DarwinBoolean(false)
            return AudioObjectIsPropertySettable(device, &address, &settable) == noErr
                && settable.boolValue
        }
        if writable.contains(kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        return writable
    }

    private var candidateElements: [AudioObjectPropertyElement] {
        [
            kAudioObjectPropertyElementMain,
            AudioObjectPropertyElement(1),
            AudioObjectPropertyElement(2),
        ]
    }

    private func propertyAddress(
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }
}

final class BuiltInDisplayBridge {
    private let privateAPI = DisplayBrightnessSymbols()

    var isUsable: Bool { currentValue() != nil }

    func adjust(direction: Int, fine: Bool) -> SystemFeedbackPresentation? {
        guard let display = builtInDisplayID(), let current = currentValue(display: display) else {
            return nil
        }
        let target = SystemFeedbackPolicy.adjustedValue(
            from: Double(current),
            direction: direction,
            fine: fine
        )
        guard setValue(Float(target), display: display) else { return nil }
        return SystemFeedbackPresentation(kind: .displayBrightness, value: target)
    }

    private func currentValue() -> Float? {
        guard let display = builtInDisplayID() else { return nil }
        return currentValue(display: display)
    }

    private func currentValue(display: CGDirectDisplayID) -> Float? {
        if let result = privateAPI.get(display), result.status == kIOReturnSuccess {
            return min(1, max(0, result.value))
        }
        guard let service = displayService() else { return nil }
        defer { IOObjectRelease(service) }
        var value: Float = 0
        guard IODisplayGetFloatParameter(
            service,
            0,
            kIODisplayBrightnessKey as CFString,
            &value
        ) == kIOReturnSuccess else { return nil }
        return min(1, max(0, value))
    }

    private func setValue(_ value: Float, display: CGDirectDisplayID) -> Bool {
        let clamped = min(1, max(0, value))
        if privateAPI.set(display, clamped) == kIOReturnSuccess { return true }
        guard let service = displayService() else { return false }
        defer { IOObjectRelease(service) }
        return IODisplaySetFloatParameter(
            service,
            0,
            kIODisplayBrightnessKey as CFString,
            clamped
        ) == kIOReturnSuccess
    }

    private func builtInDisplayID() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func displayService() -> io_service_t? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        return service == 0 ? nil : service
    }
}

private final class DisplayBrightnessSymbols {
    typealias Get = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias Set = @convention(c) (UInt32, Float) -> Int32

    private let handle: UnsafeMutableRawPointer?
    private let getter: Get?
    private let setter: Set?

    init() {
        let loaded = dlopen(
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            RTLD_NOW | RTLD_LOCAL
        )
        handle = loaded
        getter = loaded.flatMap { dlsym($0, "DisplayServicesGetBrightness") }
            .map { unsafeBitCast($0, to: Get.self) }
        setter = loaded.flatMap { dlsym($0, "DisplayServicesSetBrightness") }
            .map { unsafeBitCast($0, to: Set.self) }
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func get(_ display: UInt32) -> (status: Int32, value: Float)? {
        guard let getter else { return nil }
        var value: Float = 0
        return (getter(display, &value), value)
    }

    func set(_ display: UInt32, _ value: Float) -> Int32? {
        setter?(display, value)
    }
}

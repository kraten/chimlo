import AppKit
import ApplicationServices
import CoreGraphics
import os

enum HardwareKeyCommand: Equatable, Sendable {
    case volume(direction: Int, fine: Bool)
    case mute
    case brightness(direction: Int, fine: Bool)
}

struct HardwareKeyRouting: Equatable, Sendable {
    var volume = false
    var brightness = false

    static let disabled = HardwareKeyRouting()
}

@MainActor
protocol HardwareKeyRouterDelegate: AnyObject {
    func hardwareKeyRouter(_ router: HardwareKeyRouter, received command: HardwareKeyCommand)
}

/// Owns only the keyboard event stream. System-value writes and UI state live
/// elsewhere so a slow device cannot stall WindowServer's event callback.
@MainActor
final class HardwareKeyRouter {
    weak var delegate: (any HardwareKeyRouterDelegate)?

    private nonisolated let routingState = OSAllocatedUnfairLock(
        initialState: HardwareKeyRouting.disabled
    )
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private nonisolated static let systemDefinedEventRaw: UInt32 = 14
    private nonisolated static let soundUp: Int32 = 0
    private nonisolated static let soundDown: Int32 = 1
    private nonisolated static let brightnessUp: Int32 = 2
    private nonisolated static let brightnessDown: Int32 = 3
    private nonisolated static let mute: Int32 = 7

    var routing: HardwareKeyRouting {
        get { routingState.withLock { $0 } }
        set {
            routingState.withLock { $0 = newValue }
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: newValue != .disabled)
            }
        }
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard AXIsProcessTrusted(),
              let eventType = CGEventType(rawValue: Self.systemDefinedEventRaw) else { return false }

        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let router = Unmanaged<HardwareKeyRouter>.fromOpaque(context).takeUnretainedValue()
            return router.filter(event: event, type: type)
        }
        let mask = CGEventMask(1) << eventType.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: routing != .disabled)
        return true
    }

    func stop() {
        routingState.withLock { $0 = .disabled }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private nonisolated func filter(
        event: CGEvent,
        type: CGEventType
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor [weak self] in
                guard let self, let eventTap = self.eventTap, self.routing != .disabled else { return }
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let expectedType = CGEventType(rawValue: Self.systemDefinedEventRaw),
              type == expectedType,
              let appKitEvent = NSEvent(cgEvent: event),
              appKitEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let packed = appKitEvent.data1
        let keyCode = Int32((packed & 0xFFFF0000) >> 16)
        let flags = packed & 0x0000FFFF
        let isKeyDown = ((flags & 0xFF00) >> 8) == 0xA
        let routing = routingState.withLock { $0 }
        let handlesKey = switch keyCode {
        case Self.soundUp, Self.soundDown, Self.mute: routing.volume
        case Self.brightnessUp, Self.brightnessDown: routing.brightness
        default: false
        }
        guard handlesKey else { return Unmanaged.passUnretained(event) }

        // Key-up must be swallowed with key-down. Passing only half of the pair
        // can make the native handler wake after Chimlo already changed the value.
        guard isKeyDown else { return nil }

        let modifiers = appKitEvent.modifierFlags
        let fine = modifiers.contains(.shift) && modifiers.contains(.option)
        let command: HardwareKeyCommand
        switch keyCode {
        case Self.soundUp:
            command = .volume(direction: 1, fine: fine)
        case Self.soundDown:
            command = .volume(direction: -1, fine: fine)
        case Self.mute:
            command = .mute
        case Self.brightnessUp:
            command = .brightness(direction: 1, fine: fine)
        case Self.brightnessDown:
            command = .brightness(direction: -1, fine: fine)
        default:
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.hardwareKeyRouter(self, received: command)
        }
        return nil
    }
}

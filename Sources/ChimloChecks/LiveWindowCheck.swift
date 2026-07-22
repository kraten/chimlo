import AppKit
import CoreGraphics
import Darwin
import Foundation

enum LiveWindowTransitionCheck {
    static func run() async {
        guard let display = NotchedDisplay.current else {
            fail("no built-in notched display was found")
        }
        guard let initial = chimloWindow(on: display.bounds) else {
            fail("no visible Chimlo island window was found")
        }

        print("READY hover Chimlo open and closed; host=\(initial.bounds)")
        fflush(stdout)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        var frames: [WindowSnapshot] = [initial]

        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(8))
            if let snapshot = chimloWindow(on: display.bounds) { frames.append(snapshot) }
        }

        let centerDeltas = frames.map { abs($0.bounds.midX - initial.bounds.midX) }
        let topDeltas = frames.map { abs($0.bounds.minY - initial.bounds.minY) }
        let widthDeltas = frames.map { abs($0.bounds.width - initial.bounds.width) }
        let heightDeltas = frames.map { abs($0.bounds.height - initial.bounds.height) }

        var failures: [String] = []
        if abs(initial.bounds.midX - display.cameraCenter) > 1.5 {
            failures.append("host is not centered on the camera")
        }
        if abs(initial.bounds.width - display.bounds.width) > 1.5 {
            failures.append("host does not span the display width")
        }
        if centerDeltas.max() ?? .infinity > 0.5 {
            failures.append("host center changed while island content resized")
        }
        if topDeltas.max() ?? .infinity > 0.5 {
            failures.append("window detached from the screen edge")
        }
        if widthDeltas.max() ?? .infinity > 0.5 {
            failures.append("host width changed while island content resized")
        }
        if heightDeltas.max() ?? .infinity > 0.5 {
            failures.append("host height changed while island content resized")
        }

        if failures.isEmpty {
            print("PASS  Chimlo host remained stable while the visible island resized")
        } else {
            failures.forEach { fputs("FAIL  \($0)\n", stderr) }
            exit(EXIT_FAILURE)
        }
    }

    private static func chimloWindow(on displayBounds: CGRect) -> WindowSnapshot? {
        let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return windowInfo.compactMap { item in
            guard item[kCGWindowOwnerName as String] as? String == "Chimlo",
                  let layer = item[kCGWindowLayer as String] as? Int,
                  let rawBounds = item[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as! CFDictionary),
                  bounds.width >= 150,
                  bounds.height >= 20,
                  bounds.intersects(displayBounds) else { return nil }
            return WindowSnapshot(bounds: bounds, layer: layer)
        }.min { lhs, rhs in
            let lhsDistance = abs(lhs.bounds.minY - displayBounds.minY)
            let rhsDistance = abs(rhs.bounds.minY - displayBounds.minY)
            return lhsDistance < rhsDistance
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL  \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

private struct WindowSnapshot {
    let bounds: CGRect
    let layer: Int
}

private struct NotchedDisplay {
    let bounds: CGRect
    let cameraCenter: CGFloat

    static var current: NotchedDisplay? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let bounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
        let appKitCenter = (leftArea.maxX + rightArea.minX) / 2
        return NotchedDisplay(
            bounds: bounds,
            cameraCenter: bounds.minX + appKitCenter - screen.frame.minX
        )
    }
}

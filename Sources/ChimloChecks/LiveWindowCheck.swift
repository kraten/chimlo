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

        print("READY initial=\(initial.bounds) expectedCenter=\(display.cameraCenter)")
        fflush(stdout)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        var frames: [WindowSnapshot] = [initial]
        var transitionStarted = false

        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(8))
            guard let snapshot = chimloWindow(on: display.bounds) else { continue }
            if abs(snapshot.bounds.width - initial.bounds.width) > 0.5 {
                transitionStarted = true
                frames.append(snapshot)
                break
            }
        }

        guard transitionStarted else {
            fail("the Chimlo window did not begin resizing within thirty seconds")
        }

        let captureEnd = clock.now.advanced(by: .milliseconds(650))
        while clock.now < captureEnd {
            try? await Task.sleep(for: .milliseconds(8))
            if let snapshot = chimloWindow(on: display.bounds) { frames.append(snapshot) }
        }

        let centerDeltas = frames.map { abs($0.bounds.midX - display.cameraCenter) }
        let topDeltas = frames.map { abs($0.bounds.minY - display.bounds.minY) }
        let distinctWidths = Set(frames.map { Int(($0.bounds.width * 2).rounded()) })
        let final = frames.last?.bounds ?? initial.bounds
        let expanded = final.width > initial.bounds.width
        let expectedWidth: CGFloat = expanded ? display.expandedWidth : display.compactWidth

        var failures: [String] = []
        if centerDeltas.max() ?? .infinity > 1.5 {
            failures.append("window center drifted by \(centerDeltas.max() ?? 0) points")
        }
        if topDeltas.max() ?? .infinity > 1.5 {
            failures.append("window detached from the screen edge")
        }
        if distinctWidths.count < 4 {
            failures.append("resize did not produce a visible multi-frame size transition")
        }
        if abs(final.width - expectedWidth) > 1.5 {
            failures.append("final width \(final.width) does not match \(expectedWidth)")
        }

        if failures.isEmpty {
            print(
                "PASS  Chimlo \(expanded ? "expanded" : "collapsed") across \(distinctWidths.count) widths "
                    + "with max center delta \(String(format: "%.2f", centerDeltas.max() ?? 0))"
            )
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
    let compactWidth: CGFloat
    let expandedWidth: CGFloat

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
            cameraCenter: bounds.minX + appKitCenter - screen.frame.minX,
            compactWidth: rightArea.minX - leftArea.maxX + 64,
            expandedWidth: screen.frame.width * 0.3
        )
    }
}

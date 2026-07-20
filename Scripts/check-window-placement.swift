import AppKit
import CoreGraphics
import Darwin
import Foundation

enum ExpectedState: String {
    case any
    case compact
    case expanded
}

struct WindowSnapshot {
    let bounds: CGRect
    let layer: Int
}

let requestedState = CommandLine.arguments.dropFirst().first ?? ExpectedState.any.rawValue
guard let expectedState = ExpectedState(rawValue: requestedState) else {
    fputs("usage: swift Scripts/check-window-placement.swift [any|compact|expanded]\n", stderr)
    exit(EXIT_FAILURE)
}

guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
      let leftArea = screen.auxiliaryTopLeftArea,
      let rightArea = screen.auxiliaryTopRightArea,
      let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
    fputs("FAIL  no built-in notched display was found\n", stderr)
    exit(EXIT_FAILURE)
}

let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
let appKitCameraCenter = (leftArea.maxX + rightArea.minX) / 2
let expectedCenter = displayBounds.minX + appKitCameraCenter - screen.frame.minX
let expectedTop = displayBounds.minY

let windowInfo = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

let candidates: [WindowSnapshot] = windowInfo.compactMap { item in
    guard item[kCGWindowOwnerName as String] as? String == "Chimlo",
          let layer = item[kCGWindowLayer as String] as? Int,
          let rawBounds = item[kCGWindowBounds as String],
          let bounds = CGRect(dictionaryRepresentation: rawBounds as! CFDictionary),
          bounds.width >= 150,
          bounds.height >= 20,
          bounds.intersects(displayBounds) else { return nil }
    return WindowSnapshot(bounds: bounds, layer: layer)
}

guard let actual = candidates.min(by: { lhs, rhs in
    let lhsDistance = abs(lhs.bounds.minY - expectedTop) + abs(lhs.bounds.midX - expectedCenter)
    let rhsDistance = abs(rhs.bounds.minY - expectedTop) + abs(rhs.bounds.midX - expectedCenter)
    return lhsDistance < rhsDistance
}) else {
    fputs("FAIL  no visible Chimlo island window was found\n", stderr)
    exit(EXIT_FAILURE)
}

let menuBarLayer = windowInfo.compactMap { item -> Int? in
    guard item[kCGWindowOwnerName as String] as? String == "Window Server",
          item[kCGWindowName as String] as? String == "Menubar" else { return nil }
    return item[kCGWindowLayer as String] as? Int
}.max() ?? 24

let topDelta = abs(actual.bounds.minY - expectedTop)
let centerDelta = abs(actual.bounds.midX - expectedCenter)
let expectedWidth: CGFloat? = switch expectedState {
case .any:
    nil
case .compact:
    rightArea.minX - leftArea.maxX + 64
case .expanded:
    screen.frame.width * 0.3
}
let widthDelta = expectedWidth.map { abs(actual.bounds.width - $0) }

print("screen=\(displayBounds) cameraCenter=\(expectedCenter)")
print("chimlo=\(actual.bounds) layer=\(actual.layer) menuBarLayer=\(menuBarLayer) topDelta=\(topDelta) centerDelta=\(centerDelta)")

var failures: [String] = []
if topDelta > 1 { failures.append("island does not begin at the camera band") }
if centerDelta > 1 { failures.append("island is not centered on the camera housing") }
if actual.layer <= menuBarLayer { failures.append("macOS menu bar intercepts island pointer input") }
if let widthDelta, widthDelta > 1 {
    failures.append("island width does not match the requested \(expectedState.rawValue) state")
}

if failures.isEmpty {
    print("PASS  Chimlo \(expectedState.rawValue) placement matches the physical camera housing")
} else {
    failures.forEach { fputs("FAIL  \($0)\n", stderr) }
    exit(EXIT_FAILURE)
}

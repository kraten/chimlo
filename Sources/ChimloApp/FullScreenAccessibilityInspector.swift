import ApplicationServices
import ChimloCore
import CoreGraphics
import Foundation

struct FullScreenAccessibilityObservation: Equatable, Sendable {
    let isFullScreen: Bool
    let isPlaying: Bool
}

enum FullScreenAccessibilityInspector {
    private static let maximumElementCount = 500
    private static let maximumDepth = 8

    static func inspect(
        processIdentifier: pid_t,
        displayBounds: CGRect,
        maximumTopBandHeight: CGFloat
    ) -> FullScreenAccessibilityObservation {
        guard AXIsProcessTrusted() else {
            return FullScreenAccessibilityObservation(isFullScreen: false, isPlaying: false)
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.12)
        guard let windows = value(application, kAXWindowsAttribute as CFString)
            as? [AXUIElement] else {
            return FullScreenAccessibilityObservation(isFullScreen: false, isPlaying: false)
        }

        var foundFullScreen = false
        var foundPlayback = false
        for window in windows where windowCoversDisplayContent(
            window,
            displayBounds: displayBounds,
            maximumTopBandHeight: maximumTopBandHeight
        ) {
            if booleanValue(window, attribute: "AXFullScreen" as CFString) == true {
                foundFullScreen = true
            }

            var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
            var index = 0
            while index < queue.count, index < maximumElementCount {
                let item = queue[index]
                index += 1

                let role = stringValue(item.element, attribute: kAXRoleAttribute as CFString)
                let labels = [
                    stringValue(item.element, attribute: kAXTitleAttribute as CFString),
                    stringValue(item.element, attribute: kAXDescriptionAttribute as CFString),
                    stringValue(item.element, attribute: kAXHelpAttribute as CFString),
                    stringValue(item.element, attribute: kAXRoleDescriptionAttribute as CFString),
                ].compactMap { $0 }

                foundFullScreen = foundFullScreen
                    || FullScreenAccessibilitySemanticPolicy.indicatesActiveFullScreen(
                        role: role,
                        labels: labels
                    )
                foundPlayback = foundPlayback
                    || FullScreenAccessibilitySemanticPolicy.indicatesActivePlayback(
                        role: role,
                        labels: labels
                    )
                if foundFullScreen, foundPlayback { break }

                guard item.depth < maximumDepth,
                      let children = value(
                          item.element,
                          kAXChildrenAttribute as CFString
                      ) as? [AXUIElement] else {
                    continue
                }
                let remainingCapacity = maximumElementCount - queue.count
                guard remainingCapacity > 0 else { continue }
                queue.append(
                    contentsOf: children.prefix(remainingCapacity).map {
                        ($0, item.depth + 1)
                    }
                )
            }
            if foundFullScreen, foundPlayback { break }
        }

        return FullScreenAccessibilityObservation(
            isFullScreen: foundFullScreen,
            isPlaying: foundPlayback
        )
    }

    private static func windowCoversDisplayContent(
        _ window: AXUIElement,
        displayBounds: CGRect,
        maximumTopBandHeight: CGFloat
    ) -> Bool {
        guard let frame = frameValue(window) else { return false }
        return FullScreenWindowCoveragePolicy.coversDisplayContent(
            displayBounds,
            windows: [FullScreenWindowFrameObservation(frame: frame, layer: 0)],
            maximumTopBandHeight: maximumTopBandHeight
        )
    }

    private static func value(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &result) == .success else {
            return nil
        }
        return result
    }

    private static func stringValue(
        _ element: AXUIElement,
        attribute: CFString
    ) -> String? {
        value(element, attribute) as? String
    }

    private static func booleanValue(
        _ element: AXUIElement,
        attribute: CFString
    ) -> Bool? {
        (value(element, attribute) as? NSNumber)?.boolValue
    }

    private static func frameValue(_ element: AXUIElement) -> CGRect? {
        guard let rawValue = value(element, "AXFrame" as CFString),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        var frame = CGRect.zero
        guard AXValueGetValue(rawValue as! AXValue, .cgRect, &frame) else { return nil }
        return frame
    }
}

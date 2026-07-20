import AppKit
import ChimloCore
import SwiftUI

enum ChimloTheme {
    // The island is deliberately neutral. Color is reserved for live state,
    // provider identity, and errors so session text remains the focal point.
    static let ink = Color.black
    static let raisedInk = Color(nsColor: NSColor(calibratedWhite: 0.065, alpha: 1))
    static let selectedInk = Color(nsColor: NSColor(calibratedWhite: 0.095, alpha: 1))
    static let badgeInk = Color(nsColor: NSColor(calibratedWhite: 0.105, alpha: 1))
    static let paper = Color(nsColor: NSColor(calibratedWhite: 0.96, alpha: 1))
    static let quietPaper = Color(nsColor: NSColor(calibratedWhite: 0.61, alpha: 1))
    static let mutedPaper = Color(nsColor: NSColor(calibratedWhite: 0.36, alpha: 1))
    static let liveGreen = Color(
        nsColor: NSColor(calibratedRed: 0.14, green: 0.87, blue: 0.44, alpha: 1)
    )
    static let providerBlue = Color(
        nsColor: NSColor(calibratedRed: 0.22, green: 0.52, blue: 0.93, alpha: 1)
    )
    static let providerOrange = Color(
        nsColor: NSColor(calibratedRed: 0.78, green: 0.43, blue: 0.28, alpha: 1)
    )
    static let clay = Color(
        nsColor: NSColor(calibratedRed: 0.78, green: 0.32, blue: 0.29, alpha: 1)
    )
    static let clayText = Color(
        nsColor: NSColor(calibratedRed: 0.86, green: 0.42, blue: 0.39, alpha: 1)
    )
    static let amber = liveGreen
    static let moss = liveGreen
    static let focusRing = Color(nsColor: .keyboardFocusIndicatorColor)

    static func surface(increasedContrast _: Bool) -> Color {
        .black
    }

    static func raisedSurface(increasedContrast: Bool) -> Color {
        increasedContrast ? Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 1)) : raisedInk
    }
}

struct ChamferedIslandShape: InsettableShape {
    var shoulder: CGFloat = 11
    var lowerCut: CGFloat = 13
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let shoulder = min(shoulder, rect.width / 5, rect.height / 3)
        let lowerCut = min(lowerCut, rect.width / 5, rect.height / 3)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + shoulder))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - lowerCut))
        path.addLine(to: CGPoint(x: rect.maxX - lowerCut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + lowerCut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - lowerCut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + shoulder))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ChamferedIslandShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Expanded silhouette for a display with a camera housing. The black surface
/// spans the full panel from the screen edge while content stays below the
/// hardware band, so the camera cutout itself visibly expands into the panel.
struct NotchExpandedIslandShape: Shape {
    var lowerCut: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        let silhouette = ExpandedIslandSilhouette(width: rect.width)
        let topLeft = rect.minX + silhouette.topLeftX
        let topRight = rect.minX + silhouette.topRightX
        let topY = rect.minY + silhouette.topY
        let lowerCut = min(lowerCut, rect.width / 5, rect.height / 4)

        var path = Path()
        path.move(to: CGPoint(x: topLeft, y: topY))
        path.addLine(to: CGPoint(x: topRight, y: topY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - lowerCut))
        path.addLine(to: CGPoint(x: rect.maxX - lowerCut / 3, y: rect.maxY - lowerCut))
        path.addLine(to: CGPoint(x: rect.maxX - lowerCut / 3, y: rect.maxY - lowerCut * 2 / 3))
        path.addLine(to: CGPoint(x: rect.maxX - lowerCut * 2 / 3, y: rect.maxY - lowerCut * 2 / 3))
        path.addLine(to: CGPoint(x: rect.maxX - lowerCut * 2 / 3, y: rect.maxY - lowerCut / 3))
        path.addLine(to: CGPoint(x: rect.maxX - lowerCut, y: rect.maxY - lowerCut / 3))
        path.addLine(to: CGPoint(x: rect.maxX - lowerCut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + lowerCut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + lowerCut, y: rect.maxY - lowerCut / 3))
        path.addLine(to: CGPoint(x: rect.minX + lowerCut * 2 / 3, y: rect.maxY - lowerCut / 3))
        path.addLine(to: CGPoint(x: rect.minX + lowerCut * 2 / 3, y: rect.maxY - lowerCut * 2 / 3))
        path.addLine(to: CGPoint(x: rect.minX + lowerCut / 3, y: rect.maxY - lowerCut * 2 / 3))
        path.addLine(to: CGPoint(x: rect.minX + lowerCut / 3, y: rect.maxY - lowerCut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - lowerCut))
        path.closeSubpath()
        return path
    }
}

struct CompactNotchIslandShape: Shape {
    var lowerCut: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        let lowerCut = min(lowerCut, rect.height / 3, rect.width / 8)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - lowerCut))
        path.addLine(to: CGPoint(x: rect.maxX - lowerCut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + lowerCut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - lowerCut))
        path.closeSubpath()
        return path
    }
}

struct SteppedPanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let step = min(CGFloat(6), rect.height / 5)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + step, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - step))
        path.addLine(to: CGPoint(x: rect.maxX - step, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + step))
        path.closeSubpath()
        return path
    }
}

struct ChimloButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case quiet
        case destructive
    }

    let kind: Kind
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .frame(minHeight: compact ? 28 : 32)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(SteppedPanelShape())
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(
                .timingCurve(0.23, 1, 0.32, 1, duration: 0.14),
                value: configuration.isPressed
            )
    }

    private func foreground(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return ChimloTheme.ink
        case .quiet, .destructive:
            return isPressed ? ChimloTheme.paper : ChimloTheme.quietPaper
        }
    }

    private func background(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return isPressed ? ChimloTheme.quietPaper : ChimloTheme.paper
        case .quiet:
            return isPressed ? ChimloTheme.selectedInk : ChimloTheme.raisedInk
        case .destructive:
            return isPressed ? ChimloTheme.clay.opacity(0.45) : ChimloTheme.clay.opacity(0.22)
        }
    }
}

struct AccessibilityEnvironment {
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let increaseContrast: Bool

    static var current: AccessibilityEnvironment {
        let workspace = NSWorkspace.shared
        return AccessibilityEnvironment(
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

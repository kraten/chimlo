import AppKit
import ChimloCore
import SwiftUI

enum ChimloTheme {
    // The camera silhouette stays true black. Normal elevation is a neutral
    // graphite ladder so hover and detail surfaces never drift brown. Color is
    // reserved for provider identity and real working/attention/failure state.
    static let ink = Color.black
    static let raisedInk = color(red: 0x0F, green: 0x0F, blue: 0x0F)
    static let selectedInk = color(red: 0x1C, green: 0x1C, blue: 0x1C)
    static let badgeInk = color(red: 0x19, green: 0x19, blue: 0x19)
    static let hoveredBadgeInk = color(red: 0x2A, green: 0x2A, blue: 0x2A)
    static let rowHoverInk = color(red: 0x12, green: 0x12, blue: 0x12)
    static let rowHoverEdge = color(red: 0x26, green: 0x26, blue: 0x26)
    static let attentionInk = color(red: 0x16, green: 0x16, blue: 0x16)
    static let raisedAttentionInk = color(red: 0x29, green: 0x29, blue: 0x29)
    static let failureInk = color(red: 0x16, green: 0x16, blue: 0x16)
    static let raisedFailureInk = color(red: 0x29, green: 0x29, blue: 0x29)
    static let paper = color(red: 0xF0, green: 0xF0, blue: 0xF0)
    static let quietPaper = color(red: 0xA8, green: 0xA8, blue: 0xA8)
    static let mutedPaper = color(red: 0x7D, green: 0x7D, blue: 0x7D)
    static let liveGreen = Color(
        nsColor: NSColor(calibratedRed: 0.37, green: 0.76, blue: 0.42, alpha: 1)
    )
    static let providerBlue = Color(
        nsColor: NSColor(calibratedRed: 0.42, green: 0.57, blue: 0.83, alpha: 1)
    )
    static let providerOrange = Color(
        nsColor: NSColor(calibratedRed: 0.88, green: 0.54, blue: 0.30, alpha: 1)
    )
    static let attention = Color(
        nsColor: NSColor(calibratedRed: 0.94, green: 0.59, blue: 0.28, alpha: 1)
    )
    static let clay = Color(
        nsColor: NSColor(calibratedRed: 0.78, green: 0.29, blue: 0.23, alpha: 1)
    )
    static let clayText = Color(
        nsColor: NSColor(calibratedRed: 0.90, green: 0.42, blue: 0.34, alpha: 1)
    )
    static let amber = attention
    static let moss = liveGreen
    static let focusRing = Color(nsColor: .keyboardFocusIndicatorColor)

    static func surface(increasedContrast _: Bool) -> Color {
        .black
    }

    static func raisedSurface(increasedContrast: Bool) -> Color {
        increasedContrast ? color(red: 0x24, green: 0x24, blue: 0x24) : raisedInk
    }

    private static func color(red: Int, green: Int, blue: Int) -> Color {
        Color(
            nsColor: NSColor(
                calibratedRed: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        )
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

import AppKit
import SwiftUI

enum AvatarMood: String, CaseIterable, Sendable {
    case idle
    case working
    case waiting
    case success
    case failed

    var accessibilityDescription: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .success: "Finished"
        case .failed: "Stopped with an error"
        }
    }
}

struct PixelAvatar: View {
    let mood: AvatarMood
    var seed: Int = 0
    var size: CGFloat = 32
    var pixelUnit: CGFloat? = nil
    var reduceMotion = false

    var body: some View {
        Group {
            if reduceMotion {
                avatar(frame: 0)
            } else {
                TimelineView(.periodic(from: .now, by: frameInterval)) { timeline in
                    avatar(frame: frameIndex(at: timeline.date))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent avatar, \(mood.accessibilityDescription)")
    }

    private var frameInterval: TimeInterval {
        switch mood {
        case .idle: 0.72
        case .working: 0.16
        case .waiting: 0.34
        case .success: 0.24
        case .failed: 0.42
        }
    }

    private func frameIndex(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / frameInterval) & 1
    }

    @ViewBuilder
    private func avatar(frame: Int) -> some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, canvasSize in
            let sprite = AvatarSprites.sprite(mood: mood, frame: frame, seed: seed)
            let columns = sprite.first?.count ?? 1
            let rows = sprite.count
            let availableUnit = min(
                canvasSize.width / CGFloat(columns),
                canvasSize.height / CGFloat(rows)
            )
            let unit = min(pixelUnit ?? floor(availableUnit), availableUnit)
            let drawingWidth = unit * CGFloat(columns)
            let drawingHeight = unit * CGFloat(rows)
            let origin = CGPoint(
                x: floor((canvasSize.width - drawingWidth) / 2),
                y: floor((canvasSize.height - drawingHeight) / 2)
            )

            for (row, line) in sprite.enumerated() {
                for (column, value) in line.enumerated() where value != "." {
                    let rect = CGRect(
                        x: origin.x + CGFloat(column) * unit,
                        y: origin.y + CGFloat(row) * unit,
                        width: unit,
                        height: unit
                    )
                    context.fill(Path(rect), with: .color(AvatarSprites.color(for: value, seed: seed)))
                }
            }
        }
    }
}

private enum AvatarSprites {
    // Keep the original character palette independent from the island theme.
    // UI color changes should never silently redesign the avatar artwork.
    private enum Palette {
        static let paper = Color(
            nsColor: NSColor(calibratedRed: 0.94, green: 0.925, blue: 0.87, alpha: 1)
        )
        static let ink = Color(nsColor: NSColor(calibratedWhite: 0.035, alpha: 1))
        static let amber = Color(
            nsColor: NSColor(calibratedRed: 0.83, green: 0.64, blue: 0.31, alpha: 1)
        )
        static let moss = Color(
            nsColor: NSColor(calibratedRed: 0.48, green: 0.62, blue: 0.42, alpha: 1)
        )
        static let clay = Color(
            nsColor: NSColor(calibratedRed: 0.68, green: 0.36, blue: 0.29, alpha: 1)
        )
    }

    static func sprite(mood: AvatarMood, frame: Int, seed: Int) -> [[Character]] {
        let frames: [String]
        switch mood {
        case .idle:
            frames = [
                """
                ............
                ....KK......
                ...KAAK.....
                ..KAAAaK....
                ..KWWWWK....
                ..KWKWWK....
                ..KWWWWK....
                ...KBBK.....
                ..KBBBBK....
                ..KBBBBK....
                ...K..K.....
                ..KK..KK....
                """,
                """
                ............
                ............
                ....KK......
                ...KAAK.....
                ..KAAAaK....
                ..KWWWWK....
                ..KWWWWK....
                ...KBBK.....
                ..KBBBBK....
                ..KBBBBK....
                ..KK..KK....
                ............
                """,
            ]
        case .working:
            frames = [
                """
                ............
                ....KK......
                ...KAAK.....
                ..KAAAaK....
                ..KWKWWK....
                ..KWWWWK..T.
                ..KBBBBK.TT.
                .KKBBBBKTT..
                K.KBBBBK....
                ..KBBBBK....
                ..KK..K.....
                ......KK....
                """,
                """
                ............
                ....KK......
                ...KAAK.....
                ..KAAAaK....
                ..KWWKWK....
                T.KWWWWK....
                TT KBBBBK...
                .TTKBBBBKK..
                ...KBBBBK.K.
                ...KBBBBK...
                ...K..KK....
                ..KK........
                """.replacingOccurrences(of: " ", with: "."),
            ]
        case .waiting:
            frames = [
                """
                ............
                ....KK...T..
                ...KAAK.TT..
                ..KAAAaK.T..
                ..KWKWWK....
                ..KWWWWK....
                ..KBBBBK....
                ..KBBBBK....
                ..KBBBBK....
                ..KBBBBK....
                ..KK..KK....
                ............
                """,
                """
                ............
                ....KK......
                ...KAAK..T..
                ..KAAAaKTTT.
                ..KWWKWK.T..
                ..KWWWWK....
                ..KBBBBK....
                ..KBBBBK....
                ..KBBBBK....
                ..KBBBBK....
                ..KK..KK....
                ............
                """,
            ]
        case .success:
            frames = [
                """
                .T......T...
                ...TKK......
                ...KAAK...T.
                ..KAAAaK....
                T.KWTTWK....
                ..KWWWWK.T..
                .KKBBBBKK...
                K.KBBBBK.K..
                ..KBBBBK....
                ..KBBBBK....
                .KK....KK...
                ............
                """,
                """
                ...T........
                ....KK..T...
                T..KAAK.....
                ..KAAAaK....
                ..KWTWWK.T..
                ..KWWWWK....
                ..KBBBBK....
                .KKBBBBKK...
                K.KBBBBK.K.T
                ..KBBBBK....
                ..KK..KK....
                ............
                """,
            ]
        case .failed:
            frames = [
                """
                ............
                ....KK......
                ...KAAK.....
                ..KAAAaK..T.
                ..KWKWWK.TT.
                ..KWWWWK..T.
                ..KBBBBK....
                ..KBBBBK....
                ..KBBBBK....
                ..KBBBBK....
                ..KK..KK....
                ............
                """,
                """
                ............
                ....KK......
                ...KAAK..T..
                ..KAAAaK.TT.
                ..KWWKWK.T..
                ..KWWWWK....
                ..KBBBBK....
                ..KBBBBK....
                ..KBBBBK....
                ..KBBBBK....
                ..KK..KK....
                ............
                """,
            ]
        }

        return frames[frame % frames.count]
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(Array.init)
    }

    static func color(for value: Character, seed: Int) -> Color {
        switch value {
        case "K": Palette.paper
        case "W": Palette.ink
        case "A": seed.isMultiple(of: 2) ? Palette.amber : Palette.moss
        case "a": Palette.clay
        case "B": seed.isMultiple(of: 3) ? Palette.moss : Palette.amber
        case "T": Palette.paper
        default: .clear
        }
    }
}

/// A deliberately drawn, bare up-right mark used only when a session has a
/// real destination. It is not sourced from a general-purpose icon pack.
struct PixelJumpMark: View {
    var color: Color = ChimloTheme.quietPaper

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            let unit: CGFloat = 2
            let pixels = [
                CGPoint(x: 1, y: 4), CGPoint(x: 2, y: 3), CGPoint(x: 3, y: 2),
                CGPoint(x: 2, y: 1), CGPoint(x: 3, y: 1), CGPoint(x: 4, y: 1),
                CGPoint(x: 4, y: 2), CGPoint(x: 4, y: 3),
            ]
            for pixel in pixels {
                context.fill(
                    Path(CGRect(x: pixel.x * unit, y: pixel.y * unit, width: unit, height: unit)),
                    with: .color(color)
                )
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

enum PixelSystemGlyphKind: Equatable {
    case speaker
    case mutedSpeaker
    case sun
}

/// Chimlo-owned 7x7 system glyphs. These share the avatar's square-pixel
/// construction instead of imitating macOS or another notch app's symbols.
struct PixelSystemGlyph: View {
    let kind: PixelSystemGlyphKind
    var color: Color = ChimloTheme.paper
    var size: CGFloat = 16

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, canvasSize in
            let sprite = spriteRows
            let unit = max(1, floor(min(canvasSize.width, canvasSize.height) / 7))
            let drawingSize = unit * 7
            let origin = CGPoint(
                x: floor((canvasSize.width - drawingSize) / 2),
                y: floor((canvasSize.height - drawingSize) / 2)
            )

            for (row, line) in sprite.enumerated() {
                for (column, bit) in line.enumerated() where bit == "1" {
                    context.fill(
                        Path(CGRect(
                            x: origin.x + CGFloat(column) * unit,
                            y: origin.y + CGFloat(row) * unit,
                            width: unit,
                            height: unit
                        )),
                        with: .color(color)
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var spriteRows: [[Character]] {
        let encoded = switch kind {
        case .speaker:
            "0010000/0110100/1110010/1110001/1110010/0110100/0010000"
        case .mutedSpeaker:
            "0010001/0110010/1110100/1110000/1110100/0110010/0010001"
        case .sun:
            "0010100/1001001/0111110/0011100/0111110/1001001/0010100"
        }
        return encoded.split(separator: "/").map(Array.init)
    }
}

struct PixelText: View {
    let text: String
    var pixelSize: CGFloat = 2
    var color: Color = ChimloTheme.paper
    var spacing: CGFloat = 1

    var body: some View {
        let normalized = text.uppercased()
        let width = PixelGlyphs.width(of: normalized, pixelSize: pixelSize, spacing: spacing)
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, _ in
            var cursor: CGFloat = 0
            for character in normalized {
                let rows = PixelGlyphs.rows(for: character)
                for (rowIndex, row) in rows.enumerated() {
                    for (columnIndex, bit) in row.enumerated() where bit == "1" {
                        let rect = CGRect(
                            x: cursor + CGFloat(columnIndex) * pixelSize,
                            y: CGFloat(rowIndex) * pixelSize,
                            width: pixelSize,
                            height: pixelSize
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
                cursor += (5 * pixelSize) + spacing
            }
        }
        .frame(width: width, height: 7 * pixelSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private enum PixelGlyphs {
    static func width(of text: String, pixelSize: CGFloat, spacing: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return CGFloat(text.count) * 5 * pixelSize + CGFloat(text.count - 1) * spacing
    }

    static func rows(for character: Character) -> [[Character]] {
        let encoded = glyphs[character] ?? glyphs["?"]!
        return encoded.split(separator: "/").map(Array.init)
    }

    private static let glyphs: [Character: String] = [
        " ": "00000/00000/00000/00000/00000/00000/00000",
        "?": "01110/10001/00001/00010/00100/00000/00100",
        "-": "00000/00000/00000/11111/00000/00000/00000",
        ".": "00000/00000/00000/00000/00000/00110/00110",
        "%": "11001/11010/00100/01000/10110/00110/00000",
        "0": "01110/10001/10011/10101/11001/10001/01110",
        "1": "00100/01100/00100/00100/00100/00100/01110",
        "2": "01110/10001/00001/00010/00100/01000/11111",
        "3": "11110/00001/00001/01110/00001/00001/11110",
        "4": "00010/00110/01010/10010/11111/00010/00010",
        "5": "11111/10000/10000/11110/00001/00001/11110",
        "6": "01110/10000/10000/11110/10001/10001/01110",
        "7": "11111/00001/00010/00100/01000/01000/01000",
        "8": "01110/10001/10001/01110/10001/10001/01110",
        "9": "01110/10001/10001/01111/00001/00001/01110",
        "A": "01110/10001/10001/11111/10001/10001/10001",
        "B": "11110/10001/10001/11110/10001/10001/11110",
        "C": "01111/10000/10000/10000/10000/10000/01111",
        "D": "11110/10001/10001/10001/10001/10001/11110",
        "E": "11111/10000/10000/11110/10000/10000/11111",
        "F": "11111/10000/10000/11110/10000/10000/10000",
        "G": "01111/10000/10000/10111/10001/10001/01111",
        "H": "10001/10001/10001/11111/10001/10001/10001",
        "I": "11111/00100/00100/00100/00100/00100/11111",
        "J": "00111/00010/00010/00010/10010/10010/01100",
        "K": "10001/10010/10100/11000/10100/10010/10001",
        "L": "10000/10000/10000/10000/10000/10000/11111",
        "M": "10001/11011/10101/10101/10001/10001/10001",
        "N": "10001/11001/10101/10011/10001/10001/10001",
        "O": "01110/10001/10001/10001/10001/10001/01110",
        "P": "11110/10001/10001/11110/10000/10000/10000",
        "Q": "01110/10001/10001/10001/10101/10010/01101",
        "R": "11110/10001/10001/11110/10100/10010/10001",
        "S": "01111/10000/10000/01110/00001/00001/11110",
        "T": "11111/00100/00100/00100/00100/00100/00100",
        "U": "10001/10001/10001/10001/10001/10001/01110",
        "V": "10001/10001/10001/10001/10001/01010/00100",
        "W": "10001/10001/10001/10101/10101/10101/01010",
        "X": "10001/10001/01010/00100/01010/10001/10001",
        "Y": "10001/10001/01010/00100/00100/00100/00100",
        "Z": "11111/00001/00010/00100/01000/10000/11111",
    ]
}

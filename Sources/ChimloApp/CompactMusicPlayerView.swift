import AppKit
import SwiftUI

struct CompactMusicPlayerView: View {
    @ObservedObject var model: ApplicationModel
    @ObservedObject var media: MediaPlaybackMonitor

    var body: some View {
        if let presentation = media.presentation, presentation.isPlaying {
            Group {
                if model.islandLayout.hasCameraHousing {
                    notchContent(presentation)
                } else {
                    standardContent(presentation)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(presentation.accessibilityDescription)
        }
    }

    private func notchContent(_ presentation: MediaPlaybackPresentation) -> some View {
        HStack(spacing: 0) {
            Button(action: model.openPanel) {
                MediaArtwork(image: presentation.artwork, size: 22)
                    .frame(
                        width: model.islandLayout.activityWingWidth,
                        height: model.islandLayout.compactHeight,
                        alignment: .center
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(presentation.title)
            .accessibilityLabel("Open Chimlo")

            Color.clear
                .frame(
                    width: model.islandLayout.cameraHousingWidth,
                    height: model.islandLayout.compactHeight
                )
                .accessibilityHidden(true)

            PlaybackControl(
                isPlaying: presentation.isPlaying,
                reduceMotion: model.accessibility.reduceMotion,
                action: media.togglePlayback
            )
            .frame(
                width: model.islandLayout.activityWingWidth,
                height: model.islandLayout.compactHeight,
                alignment: .center
            )
        }
    }

    private func standardContent(_ presentation: MediaPlaybackPresentation) -> some View {
        HStack(spacing: 8) {
            Button(action: model.openPanel) {
                HStack(spacing: 8) {
                    MediaArtwork(image: presentation.artwork, size: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ChimloTheme.paper)
                            .lineLimit(1)
                        if !presentation.artist.isEmpty {
                            Text(presentation.artist)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(ChimloTheme.quietPaper)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Chimlo")

            PlaybackControl(
                isPlaying: presentation.isPlaying,
                reduceMotion: model.accessibility.reduceMotion,
                action: media.togglePlayback
            )
            .frame(width: 30, height: model.islandLayout.compactHeight)
        }
    }
}

private struct MediaArtwork: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                PixelMusicNote()
                    .foregroundStyle(ChimloTheme.paper)
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(PixelArtworkShape(cut: 3))
        .accessibilityHidden(true)
    }
}

private struct PlaybackControl: View {
    let isPlaying: Bool
    let reduceMotion: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if isPlaying && !isHovering {
                    PixelWaveform(reduceMotion: reduceMotion)
                } else {
                    PixelTransportMark(isPlaying: isPlaying)
                }
            }
            .foregroundStyle(ChimloTheme.paper)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(CompactPlaybackButtonStyle())
        .onHover { isHovering = $0 }
        .help(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

private struct CompactPlaybackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

private struct PixelWaveform: View {
    let reduceMotion: Bool

    private let restingHeights: [CGFloat] = [5, 10, 7, 12, 6]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let phase = reduceMotion
                ? 0
                : context.date.timeIntervalSinceReferenceDate * 7
            HStack(alignment: .center, spacing: 1) {
                ForEach(restingHeights.indices, id: \.self) { index in
                    let primary = (sin(phase + Double(index) * 1.3) + 1) / 2
                    let secondary = (sin(phase * 0.63 + Double(index) * 0.8) + 1) / 2
                    let height = reduceMotion
                        ? restingHeights[index]
                        : 4 + CGFloat(primary * 5 + secondary * 2)
                    Rectangle()
                        .frame(width: 2, height: height)
                }
            }
            .frame(width: 14, height: 14, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

private struct PixelTransportMark: View {
    let isPlaying: Bool

    var body: some View {
        if isPlaying {
            HStack(spacing: 3) {
                Rectangle().frame(width: 3, height: 11)
                Rectangle().frame(width: 3, height: 11)
            }
            .frame(width: 12, height: 14, alignment: .center)
            .accessibilityHidden(true)
        } else {
            Canvas { context, size in
                let color = GraphicsContext.Shading.color(ChimloTheme.paper)
                let originX = floor((size.width - 9) / 2)
                let originY = floor((size.height - 12) / 2)
                context.fill(
                    Path(CGRect(x: originX, y: originY, width: 3, height: 12)),
                    with: color
                )
                context.fill(
                    Path(CGRect(x: originX + 3, y: originY + 2, width: 3, height: 8)),
                    with: color
                )
                context.fill(
                    Path(CGRect(x: originX + 6, y: originY + 4, width: 3, height: 4)),
                    with: color
                )
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
        }
    }
}

private struct PixelMusicNote: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = max(1, floor(min(rect.width, rect.height) / 7))
        let width = unit * 2
        var path = Path()
        path.addRect(CGRect(x: rect.midX, y: rect.minY + unit, width: unit, height: unit * 4))
        path.addRect(CGRect(x: rect.midX, y: rect.minY + unit, width: unit * 3, height: unit))
        path.addRect(CGRect(x: rect.midX + unit * 2, y: rect.minY + unit, width: unit, height: unit * 3))
        path.addRect(CGRect(x: rect.midX - unit, y: rect.minY + unit * 4, width: width, height: width))
        path.addRect(CGRect(x: rect.midX + unit, y: rect.minY + unit * 3, width: width, height: width))
        return path
    }
}

private struct PixelArtworkShape: Shape {
    let cut: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

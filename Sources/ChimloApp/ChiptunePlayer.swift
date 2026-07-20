import AppKit
import Foundation

enum ChiptuneCue {
    case arrival
    case attention
    case success

    var notes: [(frequency: Double, duration: Double)] {
        switch self {
        case .arrival:
            [(392, 0.07), (523.25, 0.09)]
        case .attention:
            [(329.63, 0.09), (0, 0.035), (329.63, 0.09)]
        case .success:
            [(392, 0.07), (523.25, 0.07), (659.25, 0.11)]
        }
    }
}

@MainActor
final class ChiptunePlayer {
    private var activeSound: NSSound?

    func play(_ cue: ChiptuneCue) {
        guard let sound = NSSound(data: Self.waveData(for: cue)) else { return }
        activeSound?.stop()
        activeSound = sound
        sound.volume = 0.28
        sound.play()
    }

    private static func waveData(for cue: ChiptuneCue) -> Data {
        let sampleRate = 22_050
        var samples: [Int16] = []

        for note in cue.notes {
            let count = max(1, Int(note.duration * Double(sampleRate)))
            for index in 0..<count {
                guard note.frequency > 0 else {
                    samples.append(0)
                    continue
                }

                let cycle = (Double(index) * note.frequency / Double(sampleRate))
                    .truncatingRemainder(dividingBy: 1)
                let square = cycle < 0.5 ? 1.0 : -1.0
                let attack = min(1, Double(index) / 70)
                let release = min(1, Double(count - index) / 160)
                let value = square * attack * release * 0.42 * Double(Int16.max)
                samples.append(Int16(value.rounded()))
            }
        }

        let dataByteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + dataByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(dataByteCount)
        for sample in samples {
            data.appendLittleEndian(sample)
        }
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}

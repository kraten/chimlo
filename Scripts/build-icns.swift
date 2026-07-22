#!/usr/bin/env swift

import Foundation

private struct IconChunk {
    let type: String
    let filename: String
}

private let chunks = [
    IconChunk(type: "icp4", filename: "icon_16x16.png"),
    IconChunk(type: "icp5", filename: "icon_32x32.png"),
    IconChunk(type: "ic07", filename: "icon_128x128.png"),
    IconChunk(type: "ic08", filename: "icon_256x256.png"),
    IconChunk(type: "ic09", filename: "icon_512x512.png"),
    IconChunk(type: "ic10", filename: "icon_512x512@2x.png"),
    IconChunk(type: "ic11", filename: "icon_16x16@2x.png"),
    IconChunk(type: "ic12", filename: "icon_32x32@2x.png"),
    IconChunk(type: "ic13", filename: "icon_128x128@2x.png"),
    IconChunk(type: "ic14", filename: "icon_256x256@2x.png"),
]

private func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var encoded = value.bigEndian
    withUnsafeBytes(of: &encoded) { bytes in
        data.append(contentsOf: bytes)
    }
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: build-icns.swift <iconset-directory> <output.icns>\n".utf8)
    )
    exit(64)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
var chunkData = Data()

do {
    for chunk in chunks {
        let imageURL = iconsetURL.appendingPathComponent(chunk.filename)
        let imageData = try Data(contentsOf: imageURL)
        guard let typeData = chunk.type.data(using: .ascii), typeData.count == 4 else {
            throw CocoaError(.fileWriteUnknown)
        }

        chunkData.append(typeData)
        appendBigEndian(UInt32(imageData.count + 8), to: &chunkData)
        chunkData.append(imageData)
    }

    var outputData = Data("icns".utf8)
    appendBigEndian(UInt32(chunkData.count + 8), to: &outputData)
    outputData.append(chunkData)
    try outputData.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Could not build app icon: \(error)\n".utf8))
    exit(1)
}

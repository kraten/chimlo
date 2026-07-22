import AppKit
import CoreAudio
import Darwin
import Foundation

enum ActiveAudioApplicationResolver {
    static func processIdentifiers() -> Set<pid_t> {
        Set(activeAudioProcessIdentifiers().compactMap(resolveApplicationProcessIdentifier))
    }

    private static func activeAudioProcessIdentifiers() -> [pid_t] {
        var processListAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &processListAddress,
            0,
            nil,
            &byteCount
        ) == noErr,
        byteCount >= MemoryLayout<AudioObjectID>.size else {
            return []
        }

        var processObjects = Array(
            repeating: AudioObjectID(kAudioObjectUnknown),
            count: Int(byteCount) / MemoryLayout<AudioObjectID>.size
        )
        let readStatus = processObjects.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &processListAddress,
                0,
                nil,
                &byteCount,
                buffer.baseAddress!
            )
        }
        guard readStatus == noErr else { return [] }

        return processObjects.compactMap { objectID in
            guard readUInt32(
                objectID: objectID,
                selector: kAudioProcessPropertyIsRunningOutput
            ) != 0 else {
                return nil
            }
            return readProcessIdentifier(objectID: objectID)
        }
    }

    private static func readProcessIdentifier(objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processIdentifier = pid_t(0)
        var byteCount = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            &processIdentifier
        ) == noErr,
        processIdentifier > 0 else {
            return nil
        }
        return processIdentifier
    }

    private static func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var byteCount = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &byteCount,
            &value
        ) == noErr else {
            return nil
        }
        return value
    }

    private static func resolveApplicationProcessIdentifier(
        _ initialProcessIdentifier: pid_t
    ) -> pid_t? {
        var processIdentifier = initialProcessIdentifier
        var visited: Set<pid_t> = []

        for _ in 0..<8 {
            guard processIdentifier > 1,
                  visited.insert(processIdentifier).inserted else {
                return nil
            }
            if let application = NSRunningApplication(
                processIdentifier: processIdentifier
            ),
            application.activationPolicy != .prohibited {
                return application.processIdentifier
            }
            guard let parent = parentProcessIdentifier(of: processIdentifier) else {
                return nil
            }
            processIdentifier = parent
        }
        return nil
    }

    private static func parentProcessIdentifier(of processIdentifier: pid_t) -> pid_t? {
        var information = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let readSize = proc_pidinfo(
            processIdentifier,
            PROC_PIDTBSDINFO,
            0,
            &information,
            expectedSize
        )
        guard readSize == expectedSize, information.pbi_ppid > 0 else { return nil }
        return pid_t(information.pbi_ppid)
    }
}

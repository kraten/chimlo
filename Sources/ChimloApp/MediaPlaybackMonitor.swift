import AppKit
import Foundation

struct MediaPlaybackPresentation {
    let title: String
    let artist: String
    let album: String
    let applicationName: String?
    let bundleIdentifier: String?
    let isPlaying: Bool
    let artwork: NSImage?

    var identity: String {
        [bundleIdentifier, title, artist, album]
            .compactMap { $0 }
            .joined(separator: "\u{1f}")
    }

    var accessibilityDescription: String {
        let state = isPlaying ? "playing" : "paused"
        let byline = artist.isEmpty ? title : "\(title) by \(artist)"
        return "\(byline), \(state)"
    }

    func replacingPlaybackState(with isPlaying: Bool) -> Self {
        Self(
            title: title,
            artist: artist,
            album: album,
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            isPlaying: isPlaying,
            artwork: artwork
        )
    }
}

@MainActor
final class MediaPlaybackMonitor: ObservableObject {
    @Published private(set) var presentation: MediaPlaybackPresentation?

    private let bridge = SystemNowPlayingBridge()
    private var pollTask: Task<Void, Never>?
    private var hasStarted = false
    private var cachedArtworkIdentity: String?
    private var cachedArtwork: NSImage?

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        hasStarted = false
        pollTask?.cancel()
        pollTask = nil
        presentation = nil
        cachedArtworkIdentity = nil
        cachedArtwork = nil
    }

    func togglePlayback() {
        guard let current = presentation else { return }
        presentation = current.replacingPlaybackState(with: !current.isPlaying)

        Task { [weak self] in
            guard let self else { return }
            await bridge.send(.togglePlayPause)
            try? await Task.sleep(for: .milliseconds(160))
            await refresh()
        }
    }

    private func refresh() async {
        guard hasStarted else { return }
        let snapshot = await bridge.fetch()
        guard !Task.isCancelled, hasStarted else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: SystemNowPlayingSnapshot?) {
        guard let snapshot,
              let title = snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            presentation = nil
            return
        }

        let artist = snapshot.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let album = snapshot.album?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundleIdentifier = resolvedBundleIdentifier(for: snapshot)
        let nextIdentity = [bundleIdentifier, title, artist, album]
            .compactMap { $0 }
            .joined(separator: "\u{1f}")
        if cachedArtworkIdentity != nextIdentity {
            cachedArtworkIdentity = nextIdentity
            cachedArtwork = nil
        }
        if cachedArtwork == nil {
            cachedArtwork = decodedArtwork(snapshot.artworkDataBase64)
        }
        let artwork = cachedArtwork
            ?? applicationIcon(for: snapshot, bundleIdentifier: bundleIdentifier)

        presentation = MediaPlaybackPresentation(
            title: title,
            artist: artist,
            album: album,
            applicationName: snapshot.applicationName,
            bundleIdentifier: bundleIdentifier,
            isPlaying: snapshot.isPlaying
                ?? snapshot.playbackRate.map { $0 > 0 }
                ?? false,
            artwork: artwork
        )
    }

    private func decodedArtwork(_ encoded: String?) -> NSImage? {
        guard let encoded,
              let data = Data(base64Encoded: encoded),
              !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    private func resolvedBundleIdentifier(for snapshot: SystemNowPlayingSnapshot) -> String? {
        if let identifier = snapshot.bundleIdentifier, !identifier.isEmpty {
            return identifier
        }
        if let processIdentifier = snapshot.processIdentifier,
           let application = NSRunningApplication(processIdentifier: processIdentifier) {
            return application.bundleIdentifier
        }
        guard let applicationName = snapshot.applicationName else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName == applicationName
        }?.bundleIdentifier
    }

    private func applicationIcon(
        for snapshot: SystemNowPlayingSnapshot,
        bundleIdentifier: String?
    ) -> NSImage? {
        if let processIdentifier = snapshot.processIdentifier,
           let icon = NSRunningApplication(processIdentifier: processIdentifier)?.icon {
            return icon
        }
        if let bundleIdentifier,
           let icon = NSWorkspace.shared.runningApplications.first(where: {
               $0.bundleIdentifier == bundleIdentifier
           })?.icon {
            return icon
        }
        guard let applicationName = snapshot.applicationName else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName == applicationName
        }?.icon
    }

}

private struct SystemNowPlayingSnapshot: Decodable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let applicationName: String?
    let bundleIdentifier: String?
    let processIdentifier: pid_t?
    let playbackRate: Double?
    let isPlaying: Bool?
    let artworkDataBase64: String?
}

private struct MediaRemoteAdapterPayload: Decodable {
    let title: String?
    let artist: String?
    let album: String?
    let bundleIdentifier: String?
    let parentApplicationBundleIdentifier: String?
    let processIdentifier: pid_t?
    let playbackRate: Double?
    let playing: Bool?
    let artworkData: String?

    var snapshot: SystemNowPlayingSnapshot {
        SystemNowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            applicationName: nil,
            bundleIdentifier: parentApplicationBundleIdentifier ?? bundleIdentifier,
            processIdentifier: processIdentifier,
            playbackRate: playbackRate,
            isPlaying: playing,
            artworkDataBase64: artworkData
        )
    }
}

private actor SystemNowPlayingBridge {
    enum Command: Int, Sendable {
        case togglePlayPause = 2
    }

    func fetch() -> SystemNowPlayingSnapshot? {
        if let snapshot = fetchWithAdapter() {
            return snapshot
        }

        guard let output = runJavaScript(Self.nowPlayingScript), !output.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(
            SystemNowPlayingSnapshot.self,
            from: Data(output.utf8)
        )
    }

    func send(_ command: Command) {
        if runAdapter(arguments: ["send", String(command.rawValue)]) != nil {
            return
        }
        _ = runJavaScript(Self.commandScript(command: command.rawValue))
    }

    private func fetchWithAdapter() -> SystemNowPlayingSnapshot? {
        guard let output = runAdapter(arguments: ["get"]),
              output != "null",
              let data = output.data(using: .utf8),
              let payload = try? JSONDecoder().decode(MediaRemoteAdapterPayload.self, from: data),
              let title = payload.title,
              !title.isEmpty else { return nil }
        return payload.snapshot
    }

    private func runAdapter(arguments: [String]) -> String? {
        guard let locations = Self.adapterLocations else { return nil }
        return runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: [locations.script.path, locations.framework.path] + arguments
        )
    }

    private func runJavaScript(_ script: String) -> String? {
        runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-l", "JavaScript", "-e", script]
        )
    }

    private func runProcess(executableURL: URL, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        let buffer = ProcessOutputBuffer()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { buffer.append(data) }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        output.fileHandleForReading.readabilityHandler = nil
        buffer.append(output.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else { return nil }
        return String(data: buffer.value, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var adapterLocations: (script: URL, framework: URL)? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let root = resources.appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
        let script = root.appendingPathComponent("mediaremote-adapter.pl")
        let framework = root.appendingPathComponent(
            "MediaRemoteAdapter.framework",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path) else { return nil }
        return (script, framework)
    }

    private static let nowPlayingScript = #"""
    ObjC.import("Foundation");

    function unwrap(value) {
        if (!value) return null;
        try { return ObjC.unwrap(value); } catch (error) { return null; }
    }

    function stringValue(info, key) {
        return unwrap(info.valueForKey(key));
    }

    function numericValue(info, key) {
        const value = unwrap(info.valueForKey(key));
        return typeof value === "number" ? value : null;
    }

    function artworkValue(info) {
        const data = info.valueForKey("kMRMediaRemoteNowPlayingInfoArtworkData");
        if (!data) return null;
        try {
            return unwrap(data.base64EncodedStringWithOptions(0));
        } catch (error) {
            return null;
        }
    }

    function run() {
        const framework = $.NSBundle.bundleWithPath(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/"
        );
        if (!framework || !framework.load) return "";
        framework.load;

        const Request = $.NSClassFromString("MRNowPlayingRequest");
        if (!Request) return "";
        const item = Request.localNowPlayingItem;
        if (!item || !item.nowPlayingInfo) return "";

        const info = item.nowPlayingInfo;
        const title = stringValue(info, "kMRMediaRemoteNowPlayingInfoTitle");
        if (!title) return "";

        const playerPath = Request.localNowPlayingPlayerPath;
        const client = playerPath ? playerPath.client : null;
        let applicationName = null;
        let bundleIdentifier = null;
        let processIdentifier = null;
        if (client) {
            try { applicationName = unwrap(client.displayName); } catch (error) {}
            try { bundleIdentifier = unwrap(client.bundleIdentifier); } catch (error) {}
            try { processIdentifier = unwrap(client.processIdentifier); } catch (error) {}
        }

        return JSON.stringify({
            title: title,
            artist: stringValue(info, "kMRMediaRemoteNowPlayingInfoArtist"),
            album: stringValue(info, "kMRMediaRemoteNowPlayingInfoAlbum"),
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            playbackRate: numericValue(info, "kMRMediaRemoteNowPlayingInfoPlaybackRate"),
            isPlaying: null,
            artworkDataBase64: artworkValue(info)
        });
    }
    """#

    private static func commandScript(command: Int) -> String {
        #"""
        ObjC.import("Foundation");

        function run() {
            const framework = $.NSBundle.bundleWithPath(
                "/System/Library/PrivateFrameworks/MediaRemote.framework/"
            );
            if (!framework || !framework.load) return "";
            framework.load;

            const Controller = $.NSClassFromString("MRNowPlayingController");
            if (!Controller) return "";
            const controller = Controller.localRouteController;
            if (!controller) return "";
            controller.sendCommandOptionsCompletion(
                \#(command),
                $.NSDictionary.alloc.init,
                null
            );
            return "ok";
        }
        """#
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

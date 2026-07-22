import AppKit
import ChimloCore
import Combine
import SwiftUI

final class IslandPanel: NSPanel {
    var interactiveFrame: () -> NSRect = { .zero }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The camera housing is inside AppKit's protected safe area. Chimlo is
        // intentionally anchored there, so the normal menu-bar constraint must
        // not push this borderless panel below the hardware.
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .leftMouseUp
            || event.type == .rightMouseDown || event.type == .rightMouseUp,
           !interactiveFrame().contains(event.locationInWindow) {
            ignoresMouseEvents = true
            repostMouseEvent(event)
            return
        }

        super.sendEvent(event)
    }

    private func repostMouseEvent(_ event: NSEvent) {
        let type: CGEventType
        let button: CGMouseButton
        switch event.type {
        case .leftMouseDown:
            type = .leftMouseDown
            button = .left
        case .leftMouseUp:
            type = .leftMouseUp
            button = .left
        case .rightMouseDown:
            type = .rightMouseDown
            button = .right
        case .rightMouseUp:
            type = .rightMouseUp
            button = .right
        default:
            return
        }

        let location = event.cgEvent?.location ?? NSEvent.mouseLocation
        DispatchQueue.main.async {
            CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: location,
                mouseButton: button
            )?.post(tap: .cghidEventTap)
        }
    }
}

private final class FullBleedHostingView<Content: View>: NSHostingView<Content> {
    var hitTestFrame: () -> NSRect = { .zero }

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hitTestFrame().contains(point) else { return nil }
        return super.hitTest(point)
    }
}

private struct FullScreenWindowOwners {
    let strict: Set<pid_t>
    let displayContent: Set<pid_t>
    let displayBounds: CGRect
    let maximumTopBandHeight: CGFloat
}

@MainActor
final class IslandWindowCoordinator {
    private let model: ApplicationModel
    private let openSettings: () -> Void
    private let panel: IslandPanel
    private var cancellables: Set<AnyCancellable> = []
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var fullScreenMediaPollingTask: Task<Void, Never>?
    private var pointerInsideIntendedFrame = false
    private var fullScreenMediaPresentationMode: FullScreenMediaPresentationMode = .normal

    init(model: ApplicationModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        refreshLayout()
        configurePanel()
        observeChanges()
        updateHostFrame()
    }

    func show() {
        updateHostFrame()
        updateFullScreenMediaVisibility()
        refreshPointerPresence()
        panel.orderFrontRegardless()
    }

    func stop() {
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        globalPointerMonitor = nil
        localPointerMonitor = nil
        fullScreenMediaPollingTask?.cancel()
        fullScreenMediaPollingTask = nil
        cancellables.removeAll()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Configure floating behavior before restoring the status-bar level.
        // AppKit otherwise treats this as a movable desktop window during a
        // Space transition and can carry/scale it with the outgoing desktop.
        panel.isFloatingPanel = true
        panel.isMovable = false
        // Keep Chimlo above WindowServer's menu-bar layer so the visible wings
        // receive real pointer events. isFloatingPanel resets this to 3, so the
        // explicit level assignment must remain after it.
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        let hostingView = FullBleedHostingView(
            rootView: IslandRootView(model: model, openSettings: openSettings)
        )
        // AppKit owns one stable host window while SwiftUI animates the visible
        // island inside it. A Space switch can no longer capture a partially
        // resized WindowServer frame.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.hitTestFrame = { [weak self] in
            self?.interactiveFrameInPanel ?? .zero
        }
        panel.interactiveFrame = { [weak self] in
            self?.interactiveFrameInPanel ?? .zero
        }
        panel.contentView = hostingView
        installPointerMonitoring()
    }

    private func installPointerMonitoring() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
        ]

        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handlePointerEvent(event)
            }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handlePointerEvent(event)
            }
            return event
        }
    }

    private func handlePointerEvent(_ event: NSEvent) {
        guard fullScreenMediaPresentationMode == .normal else { return }
        refreshPointerPresence()
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !intendedPanelFrameContainsPointer {
                model.collapsePanelFromOutsideClick()
            }
        default:
            break
        }
    }

    private func refreshPointerPresence() {
        let inside = intendedPanelFrameContainsPointer
        if inside != pointerInsideIntendedFrame {
            pointerInsideIntendedFrame = inside
            model.pointerPresenceChanged(inside)
        }
        updateMouseEventRouting()
    }

    private func updateMouseEventRouting() {
        panel.ignoresMouseEvents = fullScreenMediaPresentationMode != .normal
            || !pointerInsideIntendedFrame
    }

    private var interactiveFrameInPanel: CGRect {
        let size = model.panelSize
        return CGRect(
            x: (panel.frame.width - size.width) / 2,
            y: panel.frame.height - size.height,
            width: size.width,
            height: size.height
        )
    }

    private var intendedPanelFrameContainsPointer: Bool {
        guard let screen = targetScreen else { return false }
        let intendedFrame = IslandGeometry.frame(
            for: model.panelSize,
            on: screen,
            hasCameraHousing: model.islandLayout.hasCameraHousing
        )
        return intendedFrame.contains(NSEvent.mouseLocation)
    }

    private func observeChanges() {
        model.$islandLayout
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateHostFrame() }
            .store(in: &cancellables)

        model.$systemFeedback
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFullScreenMediaVisibility() }
            .store(in: &cancellables)

        model.mediaPlayback.$presentation
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateFullScreenMediaVisibility()
            }
            .store(in: &cancellables)

        Publishers.Merge(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.activeSpaceDidChangeNotification
            ),
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.didActivateApplicationNotification
            )
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateFullScreenMediaVisibility()
            self?.refreshPointerPresence()
        }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateHostFrame()
                self?.updateFullScreenMediaVisibility()
            }
            .store(in: &cancellables)

        startFullScreenMediaPolling()
    }

    private func startFullScreenMediaPolling() {
        guard fullScreenMediaPollingTask == nil else { return }

        fullScreenMediaPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                updateFullScreenMediaVisibility()
            }
        }
    }

    private func updateFullScreenMediaVisibility() {
        guard let screen = targetScreen else { return }
        let media = model.mediaPlayback.presentation
        guard let owners = Self.fullScreenWindowOwners(on: screen) else { return }
        let activeAudioOwners = ActiveAudioApplicationResolver.processIdentifiers()
        let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?
            .processIdentifier
        let candidates = owners.strict.union(owners.displayContent)
        let fullScreenMediaIsActive = NSWorkspace.shared.runningApplications.contains {
            application in
            let processIdentifier = application.processIdentifier
            guard candidates.contains(processIdentifier) else { return false }

            let shouldInspectAccessibility = owners.displayContent.contains(processIdentifier)
                && (activeAudioOwners.contains(processIdentifier)
                    || frontmostProcessIdentifier == processIdentifier)
            let accessibility = shouldInspectAccessibility
                ? FullScreenAccessibilityInspector.inspect(
                    processIdentifier: processIdentifier,
                    displayBounds: owners.displayBounds,
                    maximumTopBandHeight: owners.maximumTopBandHeight
                )
                : FullScreenAccessibilityObservation(isFullScreen: false, isPlaying: false)

            return FullScreenMediaVisibilityPolicy.shouldHideIsland(
                mediaIsPlaying: media?.isPlaying == true,
                mediaBundleIdentifier: media?.bundleIdentifier,
                mediaApplicationName: media?.applicationName,
                windowOwnerBundleIdentifier: application.bundleIdentifier,
                windowOwnerApplicationName: application.localizedName,
                windowOwnerHasFullScreenWindow: owners.strict.contains(processIdentifier),
                windowOwnerHasAccessibleFullScreenPresentation: accessibility.isFullScreen,
                windowOwnerIsProducingAudio: activeAudioOwners.contains(processIdentifier),
                windowOwnerAccessibilityIndicatesPlayback: accessibility.isPlaying
            )
        }
        let nextMode = FullScreenMediaPresentationPolicy.mode(
            fullScreenMediaIsActive: fullScreenMediaIsActive,
            hasSystemFeedback: model.systemFeedback != nil
        )
        guard nextMode != fullScreenMediaPresentationMode else { return }

        fullScreenMediaPresentationMode = nextMode
        model.updateFullScreenMediaPresentationMode(nextMode)
        panel.alphaValue = nextMode == .hidden ? 0 : 1

        // Keep the panel ordered while it is transparent. orderOut removes the
        // replicated all-Spaces window; ordering it again can attach the
        // restored copy only to the Space where full-screen playback ended.
        panel.orderFrontRegardless()

        switch nextMode {
        case .hidden:
            pointerInsideIntendedFrame = false
            model.collapsePanelFromOutsideClick()
            updateMouseEventRouting()
        case .systemFeedbackOnly:
            updateMouseEventRouting()
        case .normal:
            refreshPointerPresence()
        }
    }

    private static func fullScreenWindowOwners(
        on screen: NSScreen
    ) -> FullScreenWindowOwners? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]],
        let displayBounds = displayBounds(for: screen) else {
            return nil
        }

        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        var windowsByOwner: [pid_t: [FullScreenWindowFrameObservation]] = [:]
        for window in windows {
            guard let owner = window[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value != ownProcessIdentifier,
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(
                    dictionaryRepresentation: bounds as CFDictionary
                  ) else {
                continue
            }
            guard frame.intersects(displayBounds) else { continue }
            windowsByOwner[owner.int32Value, default: []].append(
                FullScreenWindowFrameObservation(frame: frame, layer: layer.intValue)
            )
        }

        let maximumTopBandHeight = max(screen.safeAreaInsets.top, 44)
        let strict = Set(windowsByOwner.compactMap { processIdentifier, observations in
            FullScreenWindowCoveragePolicy.coversDisplay(
                displayBounds,
                windows: observations,
                maximumTopBandHeight: maximumTopBandHeight
            ) ? processIdentifier : nil
        })
        let displayContent = Set(windowsByOwner.compactMap {
            processIdentifier,
            observations in
            FullScreenWindowCoveragePolicy.coversDisplayContent(
                displayBounds,
                windows: observations,
                maximumTopBandHeight: maximumTopBandHeight
            ) ? processIdentifier : nil
        })
        return FullScreenWindowOwners(
            strict: strict,
            displayContent: displayContent,
            displayBounds: displayBounds,
            maximumTopBandHeight: maximumTopBandHeight
        )
    }

    private static func displayBounds(for screen: NSScreen) -> CGRect? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else { return nil }
        return CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
    }

    private func updateHostFrame() {
        guard let screen = targetScreen else { return }
        refreshLayout(for: screen)
        let target = IslandGeometry.hostFrame(
            on: screen,
            hasCameraHousing: model.islandLayout.hasCameraHousing
        )
        guard panel.frame != target else { return }
        panel.setFrame(target, display: true)
    }

    private var targetScreen: NSScreen? {
        if let builtIn = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return builtIn
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func refreshLayout(for screen: NSScreen? = nil) {
        guard let screen = screen ?? targetScreen else { return }
        let leftArea = screen.auxiliaryTopLeftArea
        let rightArea = screen.auxiliaryTopRightArea
        let safeTopInset = max(
            screen.safeAreaInsets.top,
            leftArea?.height ?? 0,
            rightArea?.height ?? 0
        )
        model.updateIslandLayout(
            IslandLayout.make(
                for: IslandDisplayMetrics(
                    screenWidth: screen.frame.width,
                    screenHeight: screen.frame.height,
                    visibleTop: screen.visibleFrame.maxY,
                    safeTopInset: safeTopInset,
                    cameraHousingLeftEdge: leftArea?.maxX,
                    cameraHousingRightEdge: rightArea?.minX
                )
            )
        )
    }
}

private enum IslandGeometry {
    private static let hostHeight: CGFloat = 750

    static func hostFrame(on screen: NSScreen, hasCameraHousing: Bool) -> CGRect {
        frame(
            for: CGSize(width: screen.frame.width, height: min(hostHeight, screen.frame.height)),
            on: screen,
            hasCameraHousing: hasCameraHousing
        )
    }

    static func frame(for size: CGSize, on screen: NSScreen, hasCameraHousing: Bool) -> CGRect {
        let top = hasCameraHousing ? screen.frame.maxY : screen.visibleFrame.maxY - 6
        let cameraCenter: CGFloat?
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            cameraCenter = (leftArea.maxX + rightArea.minX) / 2
        } else {
            cameraCenter = nil
        }
        let x = (cameraCenter ?? screen.frame.midX) - size.width / 2
        let proposed = CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
        return screen.backingAlignedRect(proposed, options: [.alignAllEdgesNearest])
    }
}

@MainActor
final class SettingsWindowCoordinator: NSObject, NSWindowDelegate {
    private let model: ApplicationModel
    private var window: NSWindow?

    init(model: ApplicationModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 680, height: 480),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Chimlo"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.minSize = NSSize(width: 640, height: 440)
            window.tabbingMode = .disallowed
            window.setFrameAutosaveName("ChimloSettingsWindow")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: ChimloSettingsView(model: model))
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

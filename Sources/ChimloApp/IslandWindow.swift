import AppKit
import ChimloCore
import Combine
import QuartzCore
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The camera housing is inside AppKit's protected safe area. Chimlo is
        // intentionally anchored there, so the normal menu-bar constraint must
        // not push this borderless panel below the hardware.
        frameRect
    }
}

private final class FullBleedHostingView<Content: View>: NSHostingView<Content> {
    var pointerPresenceChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // .inVisibleRect follows every animated resize. Replacing this area on
        // each frame can strand AppKit's entered/exited state after collapse,
        // causing the next hover to be ignored.
        guard hoverTrackingArea == nil else { return }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect,
                .enabledDuringMouseDrag,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        pointerPresenceChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        pointerPresenceChanged?(false)
    }
}

@MainActor
final class IslandWindowCoordinator {
    private let model: ApplicationModel
    private let openSettings: () -> Void
    private let panel: IslandPanel
    private var cancellables: Set<AnyCancellable> = []

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
        updateFrame(animated: false)
    }

    func show() {
        updateFrame(animated: false)
        panel.orderFrontRegardless()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Keep Chimlo above WindowServer's menu-bar layer so the visible wings
        // receive real pointer events. isFloatingPanel would reset this to 3.
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
        let hostingView = FullBleedHostingView(
            rootView: IslandRootView(model: model, openSettings: openSettings)
        )
        // SwiftUI's intrinsic-size bridge otherwise resizes the NSPanel while
        // preserving its old origin. The coordinator owns both size and center.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.pointerPresenceChanged = { [weak model] inside in
            model?.pointerPresenceChanged(inside)
        }
        panel.contentView = hostingView
    }

    private func observeChanges() {
        model.$panelMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame(animated: true) }
            .store(in: &cancellables)

        model.$sessions
            .map(\.count)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame(animated: true) }
            .store(in: &cancellables)

        model.$pendingDecision
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame(animated: true) }
            .store(in: &cancellables)

        model.$islandLayout
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame(animated: false) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame(animated: false) }
            .store(in: &cancellables)
    }

    private func updateFrame(animated: Bool) {
        guard let screen = targetScreen else { return }
        refreshLayout(for: screen)
        let target = IslandGeometry.frame(
            for: model.panelSize,
            on: screen,
            hasCameraHousing: model.islandLayout.hasCameraHousing
        )
        guard panel.frame != target else { return }

        if animated && !model.accessibility.reduceMotion {
            let isExpanding = target.width * target.height > panel.frame.width * panel.frame.height
            NSAnimationContext.runAnimationGroup { context in
                // Hover expansion needs enough travel to read as a physical
                // resize. Collapse is shorter because the user is already
                // leaving. Both remain below the 300 ms UI-motion ceiling.
                context.duration = isExpanding ? 0.24 : 0.18
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.32,
                    0.72,
                    0,
                    1
                )
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
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

import AppKit
import SwiftUI

@main
struct ChimloApplication: App {
    @NSApplicationDelegateAdaptor(ChimloAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            ChimloSettingsView(model: appDelegate.model)
                .frame(minWidth: 640, minHeight: 440)
        }
    }
}

@MainActor
final class ChimloAppDelegate: NSObject, NSApplicationDelegate {
    let model = ApplicationModel()
    private var islandCoordinator: IslandWindowCoordinator?
    private var settingsCoordinator: SettingsWindowCoordinator?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsCoordinator = SettingsWindowCoordinator(model: model)
        let islandCoordinator = IslandWindowCoordinator(
            model: model,
            openSettings: { [weak settingsCoordinator] in settingsCoordinator?.show() }
        )
        self.islandCoordinator = islandCoordinator
        self.settingsCoordinator = settingsCoordinator

        model.start()
        islandCoordinator.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        islandCoordinator?.stop()
        model.stop()
        islandCoordinator = nil
        settingsCoordinator = nil
    }
}

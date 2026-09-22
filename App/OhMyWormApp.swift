import AppKit
import SwiftUI

/// Agent app: no dock icon, no main window. The worm lives on a small
/// transparent overlay panel; controls live in the status bar menu.
@main
struct OhMyWormApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PetController?
    private var statusItem: NSStatusItem?
    private let menuDelegate = PetMenuDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let controller = PetController(screen: screen)

        menuDelegate.controller = controller
        let menu = PetMenu.make(controller: controller, delegate: menuDelegate)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🐛"
        statusItem.menu = menu
        self.statusItem = statusItem

        controller.start()
        self.controller = controller

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenChanged() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first,
              let controller else { return }
        controller.refit(screen: screen)
    }
}

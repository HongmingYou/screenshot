import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Strong reference — status bar item disappears if this is deallocated.
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Remove from Dock in case LSUIElement wasn't picked up yet.
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController()

        Task { @MainActor in
            await CaptureManager.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            await CaptureManager.shared.stop()
        }
    }
}

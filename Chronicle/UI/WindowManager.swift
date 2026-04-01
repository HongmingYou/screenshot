import AppKit
import SwiftUI

/// Opens and manages the main Chronicle window and Settings window.
final class WindowManager {
    static let shared = WindowManager()
    private init() {}

    private weak var mainWindow: NSWindow?
    private weak var settingsWindow: NSWindow?

    @MainActor func openMainWindow() {
        if let w = mainWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = MainWindowView()
            .environmentObject(CaptureManager.shared)
            .environmentObject(AppSettings.shared)

        let window = makeWindow(
            title: "Chronicle",
            size: NSRect(x: 0, y: 0, width: 960, height: 640),
            autosaveName: "ChronicleMain",
            rootView: AnyView(rootView)
        )
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsView()
            .environmentObject(AppSettings.shared)

        let window = makeWindow(
            title: "Chronicle 设置",
            size: NSRect(x: 0, y: 0, width: 440, height: 300),
            autosaveName: "ChronicleSettings",
            rootView: AnyView(rootView)
        )
        window.styleMask.remove(.resizable)
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Helpers

    private func makeWindow(title: String, size: NSRect, autosaveName: String, rootView: AnyView) -> NSWindow {
        let hosting = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: size,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = hosting
        window.center()
        window.setFrameAutosaveName(autosaveName)
        window.isReleasedWhenClosed = false
        return window
    }
}

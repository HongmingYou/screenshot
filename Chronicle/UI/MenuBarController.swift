import AppKit
import SwiftUI

/// Owns the NSStatusItem and the NSPopover it controls.
@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var eventMonitor: Any?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()

        configureStatusItem()
        configurePopover()
        installClickOutsideMonitor()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Setup

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let icon = NSImage(systemSymbolName: "eye.circle.fill", accessibilityDescription: "Chronicle")
        icon?.isTemplate = true   // Adapts to light/dark menu bar automatically
        button.image = icon
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func configurePopover() {
        popover.contentSize = NSSize(width: 320, height: 460)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StatusMenuView()
                .environmentObject(CaptureManager.shared)
        )
    }

    private func installClickOutsideMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    // MARK: - Toggle

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}

import AppKit
import Foundation
import ScreenCaptureKit

/// Drives the periodic screenshot → OCR → storage pipeline.
/// Lives on MainActor so @Published properties can be observed by SwiftUI.
@MainActor
final class CaptureManager: ObservableObject {
    static let shared = CaptureManager()

    @Published var isRunning = false
    @Published var captureCount = 0
    @Published var lastCaptureTime: Date?
    @Published var lastError: String?

    /// Seconds between capture attempts. Change before calling start().
    var captureInterval: TimeInterval = 5.0

    private var captureTask: Task<Void, Never>?
    private let ocrProcessor = OCRProcessor()
    private let textDiff = TextDiffProcessor()
    private let activityProcessor = ActivityProcessor()
    private var lastOCRText = ""

    private init() {}

    // MARK: - Public control

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil

        captureTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.captureAndProcess()
                try? await Task.sleep(for: .seconds(self.captureInterval))
            }
        }
    }

    func stop() async {
        captureTask?.cancel()
        captureTask = nil
        isRunning = false
    }

    // MARK: - Pipeline

    private func captureAndProcess() async {
        do {
            guard let cgImage = try await captureScreen() else { return }

            let ocrText = await ocrProcessor.recognize(image: cgImage)
            let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Skip frames where screen content hasn't meaningfully changed.
            let similarity = textDiff.similarity(trimmed, lastOCRText)
            guard similarity < 0.95 else { return }
            lastOCRText = trimmed

            let appInfo = getFrontmostAppInfo()

            // Don't capture or store content from privacy-sensitive apps.
            guard !PrivacyFilter.shared.isBlocked(bundleID: appInfo.bundleID) else { return }

            await activityProcessor.process(
                ocrText: trimmed,
                appBundleID: appInfo.bundleID,
                windowTitle: appInfo.windowTitle
            )

            captureCount += 1
            lastCaptureTime = Date()

        } catch {
            lastError = error.localizedDescription
            print("[CaptureManager] Error: \(error)")
        }
    }

    // MARK: - Screenshot via ScreenCaptureKit (macOS 14+)

    private func captureScreen() async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else { return nil }

        // Exclude privacy-sensitive apps from pixel content entirely.
        let blockedApps = content.applications.filter {
            PrivacyFilter.shared.isBlocked(bundleID: $0.bundleIdentifier)
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: blockedApps,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.width = Int(display.frame.width)
        config.height = Int(display.frame.height)
        config.scaleFactor = 1.0   // 1× is enough for OCR; saves RAM & CPU
        config.capturesAudio = false
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    // MARK: - Active app info

    private func getFrontmostAppInfo() -> (bundleID: String, windowTitle: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return ("unknown", "Unknown")
        }
        let bundleID = app.bundleIdentifier ?? "unknown"

        // Try Accessibility for the window title; fall back to app name.
        let windowTitle = accessibilityWindowTitle(for: app) ?? app.localizedName ?? bundleID
        return (bundleID, windowTitle)
    }

    private func accessibilityWindowTitle(for app: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String, !title.isEmpty else { return nil }
        return title
    }
}

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
    /// Set to true when the user has denied screen recording permission.
    @Published var permissionDenied = false

    /// Seconds between capture attempts. Change before calling start().
    var captureInterval: TimeInterval = 5.0

    private var captureTask: Task<Void, Never>?
    private let ocrProcessor = OCRProcessor()
    private let textDiff = TextDiffProcessor()
    private let activityProcessor = ActivityProcessor()
    private var lastOCRText = ""

    // ScreenCaptureKit TCC denial error code
    private static let kTCCDeniedCode = -3801

    private init() {}

    // MARK: - Public control

    func start() async {
        guard !isRunning else { return }

        // Use CoreGraphics preflight to check TCC status without repeatedly triggering
        // the SCK picker/dialog. CGPreflightScreenCaptureAccess() reads from the TCC
        // cache synchronously and never shows a dialog on its own.
        if !CGPreflightScreenCaptureAccess() {
            permissionDenied = true
            lastError = "屏幕录制权限未授权。请前往「系统设置 → 隐私与安全性 → 屏幕录制」授权 Chronicle，然后重启应用。"
            // Show the one-time system prompt (no-op if already shown).
            CGRequestScreenCaptureAccess()
            return
        }

        // Secondary SCK-level check: catches the case where CG reports granted but SCK
        // still has a stale TCC entry (rare, but can occur after OS upgrades).
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch let error as NSError where error.code == Self.kTCCDeniedCode {
            permissionDenied = true
            lastError = "屏幕录制权限被拒绝。请前往「系统设置 → 隐私与安全性 → 屏幕录制」授权 Chronicle，然后重启应用。"
            return
        } catch {
            // Other errors (e.g. no displays) — proceed and let the loop handle them.
        }

        permissionDenied = false
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
        await VideoWriter.shared.finalize()
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

            // Save JPEG thumbnail for immediate display.
            let now = Date()
            var screenshotPath: String?
            var videoTimestamp: Double?
            screenshotPath = Self.saveJPEGThumbnail(cgImage, date: now)

            // Also append to H.265 video segment for archival (best-effort).
            if let ref = try? await VideoWriter.shared.appendFrame(cgImage, captureDate: now) {
                videoTimestamp = ref.timestamp
            }

            await activityProcessor.process(
                ocrText: trimmed,
                appBundleID: appInfo.bundleID,
                windowTitle: appInfo.windowTitle,
                screenshotPath: screenshotPath,
                videoTimestamp: videoTimestamp
            )

            captureCount += 1
            lastCaptureTime = Date()

        } catch let error as NSError where error.code == Self.kTCCDeniedCode {
            // Permission was revoked while running — stop the loop immediately.
            permissionDenied = true
            lastError = "屏幕录制权限被撤销。请前往「系统设置 → 隐私与安全性 → 屏幕录制」重新授权，然后重启应用。"
            captureTask?.cancel()
            isRunning = false
            print("[CaptureManager] Screen recording permission denied, stopping.")
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
        config.capturesAudio = false
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    // MARK: - JPEG thumbnail

    private static func saveJPEGThumbnail(_ image: CGImage, date: Date) -> String? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let dayDir = appSupport
            .appendingPathComponent("Chronicle/screenshots", isDirectory: true)
            .appendingPathComponent(fmt.string(from: date), isDirectory: true)
        try? FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HHmmss_SSS"
        timeFmt.locale = Locale(identifier: "en_US_POSIX")
        let filePath = dayDir.appendingPathComponent("\(timeFmt.string(from: date)).jpg")

        // Scale down to max 960px on longer side for thumbnails
        let maxDim = 960
        let longer = max(image.width, image.height)
        let scale = longer > maxDim ? CGFloat(maxDim) / CGFloat(longer) : 1.0
        let w = Int(CGFloat(image.width) * scale)
        let h = Int(CGFloat(image.height) * scale)

        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }

        let nsImage = NSImage(cgImage: scaled, size: NSSize(width: w, height: h))
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { return nil }

        try? jpegData.write(to: filePath)
        return filePath.path
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

import AVFoundation
import CoreImage
import CoreVideo

/// Writes captured screenshots into hourly H.265 (HEVC) video segments.
/// One MP4 file per hour: <AppSupport>/Chronicle/videos/YYYY-MM-DD/HH.mp4
/// Each video plays at 1fps (one captured frame per second of video).
actor VideoWriter {
    static let shared = VideoWriter()

    private struct Segment {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let videoPath: String
        let hourKey: String  // "yyyy-MM-dd/HH"
        var frameCount: Int64 = 0
    }

    private var current: Segment?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let videosDir: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        videosDir = appSupport.appendingPathComponent("Chronicle/videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Appends one screenshot frame. Returns (videoPath, videoTimestamp) for storage in ActivityRecord.
    func appendFrame(_ image: CGImage, captureDate: Date) async throws -> (path: String, timestamp: Double) {
        let key = hourKey(for: captureDate)

        if current?.hourKey != key {
            await finalizeCurrentSegment()
            try openNewSegment(hourKey: key, width: image.width, height: image.height)
        }

        guard var seg = current, seg.input.isReadyForMoreMediaData else {
            throw VideoError.notReady
        }

        let frameTime = CMTime(value: seg.frameCount, timescale: 1)
        let pixelBuffer = try makePixelBuffer(from: image, targetWidth: outputSize(image).width, targetHeight: outputSize(image).height)

        guard seg.adaptor.append(pixelBuffer, withPresentationTime: frameTime) else {
            throw VideoError.appendFailed
        }

        let timestamp = Double(seg.frameCount)
        seg.frameCount += 1
        current = seg

        return (seg.videoPath, timestamp)
    }

    /// Finalizes any open segment. Call on app quit.
    func finalize() async {
        await finalizeCurrentSegment()
    }

    // MARK: - Segment management

    private func finalizeCurrentSegment() async {
        guard let seg = current else { return }
        current = nil
        seg.input.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            seg.writer.finishWriting { cont.resume() }
        }
    }

    private func openNewSegment(hourKey: String, width: Int, height: Int) throws {
        let datePart = String(hourKey.prefix(10))   // "yyyy-MM-dd"
        let hourPart = String(hourKey.suffix(2))     // "HH"
        let dir = videosDir.appendingPathComponent(datePart, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("\(hourPart).mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let (w, h) = outputSize(width: width, height: height)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 800_000,  // 800kbps timelapse
                AVVideoAllowFrameReorderingKey: false
            ] as [String: Any]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let sourceAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourceAttributes
        )

        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? VideoError.startFailed
        }
        writer.startSession(atSourceTime: .zero)

        current = Segment(
            writer: writer,
            input: input,
            adaptor: adaptor,
            videoPath: url.path,
            hourKey: hourKey
        )
    }

    // MARK: - Pixel buffer conversion

    private func makePixelBuffer(from image: CGImage, targetWidth: Int, targetHeight: Int) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: targetWidth,
            kCVPixelBufferHeightKey as String: targetHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, targetWidth, targetHeight, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let pb = buffer else {
            throw VideoError.pixelBufferCreation
        }

        let ci = CIImage(cgImage: image)
        let scaleX = CGFloat(targetWidth) / CGFloat(image.width)
        let scaleY = CGFloat(targetHeight) / CGFloat(image.height)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        ciContext.render(scaled, to: pb)

        return pb
    }

    // MARK: - Helpers

    private func outputSize(_ image: CGImage) -> (width: Int, height: Int) {
        outputSize(width: image.width, height: image.height)
    }

    private func outputSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let maxDim = 1920
        let longer = max(width, height)
        if longer <= maxDim {
            return (width & ~1, height & ~1)
        }
        let scale = Double(maxDim) / Double(longer)
        return (Int(Double(width) * scale) & ~1, Int(Double(height) * scale) & ~1)
    }

    private func hourKey(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd/HH"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    enum VideoError: Error, LocalizedError {
        case notReady, pixelBufferCreation, appendFailed, startFailed

        var errorDescription: String? {
            switch self {
            case .notReady:          return "Video writer not ready"
            case .pixelBufferCreation: return "Failed to create pixel buffer"
            case .appendFailed:      return "Failed to append video frame"
            case .startFailed:       return "Failed to start video writer"
            }
        }
    }
}

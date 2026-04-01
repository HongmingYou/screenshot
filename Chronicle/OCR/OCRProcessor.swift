import CoreGraphics
import Vision

/// Wraps VNRecognizeTextRequest. Actor isolation gives it its own serial queue.
actor OCRProcessor {

    func recognize(image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: "")
                    return
                }

                let text = observations
                    .compactMap { $0.topCandidates(1).first }
                    .filter { $0.confidence > 0.3 }
                    .map { $0.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            // .accurate uses Apple Neural Engine — higher quality, still fast
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Priority list: Simplified Chinese, Traditional Chinese, English, Japanese
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja"]
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[OCRProcessor] handler.perform failed: \(error)")
                continuation.resume(returning: "")
            }
        }
    }
}

import Foundation

/// Computes similarity between OCR results with multiple strategies:
///   1. Line-level Jaccard similarity (structural)
///   2. Fuzzy line matching that ignores volatile content (timestamps, counters)
///   3. Sliding window dedup to catch A→B→A patterns
struct TextDiffProcessor {

    /// Recent OCR snapshots keyed by (appBundleID, windowTitle) for cross-frame dedup.
    /// Each entry holds the normalized line set of a recent capture.
    private struct FrameFingerprint {
        let appBundleID: String
        let windowTitle: String
        let stableLines: Set<String>   // lines with volatile parts stripped
        let timestamp: Date
    }

    private var recentFrames: [FrameFingerprint] = []
    private let maxWindowSize = 8

    // MARK: - Public API

    /// Returns a value in [0, 1]. 1.0 = identical, 0.0 = nothing in common.
    func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        guard !a.isEmpty, !b.isEmpty else { return 0.0 }

        let linesA = lineSet(from: a)
        let linesB = lineSet(from: b)

        guard !linesA.isEmpty || !linesB.isEmpty else { return 1.0 }
        guard !linesA.isEmpty, !linesB.isEmpty else { return 0.0 }

        let intersection = Double(linesA.intersection(linesB).count)
        let union        = Double(linesA.union(linesB).count)

        return union > 0 ? intersection / union : 0.0
    }

    /// Fuzzy similarity that strips volatile content (numbers, timestamps) before comparing.
    /// Better for detecting "same screen, just clock/counter changed".
    func fuzzySimilarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        guard !a.isEmpty, !b.isEmpty else { return 0.0 }

        let stableA = stableLineSet(from: a)
        let stableB = stableLineSet(from: b)

        guard !stableA.isEmpty || !stableB.isEmpty else { return 1.0 }
        guard !stableA.isEmpty, !stableB.isEmpty else { return 0.0 }

        let intersection = Double(stableA.intersection(stableB).count)
        let union        = Double(stableA.union(stableB).count)

        return union > 0 ? intersection / union : 0.0
    }

    /// Check if this frame is a duplicate of any recent frame in the sliding window.
    /// Returns true if it should be skipped.
    mutating func isDuplicateInWindow(
        ocrText: String,
        appBundleID: String,
        windowTitle: String,
        threshold: Double = 0.90
    ) -> Bool {
        let stable = stableLineSet(from: ocrText)
        let now = Date()

        // Evict frames older than 2 minutes
        recentFrames.removeAll { now.timeIntervalSince($0.timestamp) > 120 }

        // Check against recent frames from the same app
        for frame in recentFrames {
            // Same app context — use higher sensitivity
            let isSameApp = frame.appBundleID == appBundleID
            let effectiveThreshold = isSameApp ? threshold : threshold + 0.05

            let intersection = Double(stable.intersection(frame.stableLines).count)
            let union = Double(stable.union(frame.stableLines).count)
            let sim = union > 0 ? intersection / union : 0.0

            if sim >= effectiveThreshold {
                return true
            }
        }

        // Add to window
        recentFrames.append(FrameFingerprint(
            appBundleID: appBundleID,
            windowTitle: windowTitle,
            stableLines: stable,
            timestamp: now
        ))
        if recentFrames.count > maxWindowSize {
            recentFrames.removeFirst()
        }

        return false
    }

    // MARK: - Internals

    private func lineSet(from text: String) -> Set<String> {
        Set(
            text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
    }

    /// Strips volatile content: standalone numbers, time patterns (HH:MM), percentages.
    /// Keeps the structural "skeleton" of each line for stable comparison.
    private func stableLineSet(from text: String) -> Set<String> {
        Set(
            text
                .components(separatedBy: .newlines)
                .map { stabilizeLine($0.trimmingCharacters(in: .whitespaces)) }
                .filter { !$0.isEmpty }
        )
    }

    /// Replace volatile tokens in a line with a placeholder so similar lines match.
    private func stabilizeLine(_ line: String) -> String {
        var result = line
        // Time patterns: 12:34, 12:34:56, 02:50
        result = result.replacingOccurrences(
            of: #"\b\d{1,2}:\d{2}(:\d{2})?\b"#,
            with: "•T",
            options: .regularExpression
        )
        // Dates: 2026-04-02, 4月2日, 04/02
        result = result.replacingOccurrences(
            of: #"\b\d{1,4}[/\-年月日.]\d{1,2}[/\-月日.]?\d{0,4}日?\b"#,
            with: "•D",
            options: .regularExpression
        )
        // Percentages: 85%, 12.5%
        result = result.replacingOccurrences(
            of: #"\d+\.?\d*%"#,
            with: "•P",
            options: .regularExpression
        )
        // Standalone numbers (counters, badge counts): "  42  " but not inside words
        result = result.replacingOccurrences(
            of: #"(?<=\s|^)\d+(?=\s|$)"#,
            with: "•N",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespaces)
    }
}

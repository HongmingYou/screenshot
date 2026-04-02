import Foundation

/// Converts raw capture events into ActivityRecords with session merging.
/// Consecutive captures of the same app + similar content are merged into
/// a single record, reducing noise and giving meaningful duration tracking.
actor ActivityProcessor {

    private var currentSession: Session?
    private let maxGap: TimeInterval = 300       // cap idle gaps at 5 min
    private let mergeThreshold: Double = 0.70    // fuzzy text similarity to merge
    private let maxSessionDuration: TimeInterval = 1800  // force-save after 30 min
    private let textDiff = TextDiffProcessor()

    private struct Session {
        var record: ActivityRecord
        var startTime: Date
        var lastUpdateTime: Date
        var frameCount: Int
    }

    func process(
        ocrText: String,
        appBundleID: String,
        windowTitle: String,
        screenshotPath: String? = nil,
        videoTimestamp: Double? = nil
    ) async {
        let now = Date()

        // Try to merge into current session
        if var session = currentSession {
            let gap = now.timeIntervalSince(session.lastUpdateTime)
            let sameApp = session.record.appBundleID == appBundleID
            let sessionAge = now.timeIntervalSince(session.startTime)

            if sameApp && gap < maxGap && sessionAge < maxSessionDuration {
                let similarity = textDiff.fuzzySimilarity(ocrText, session.record.ocrText)

                if similarity >= mergeThreshold {
                    // Merge: update duration, keep latest OCR text, update screenshot
                    session.record.duration = now.timeIntervalSince(session.startTime)
                    session.record.ocrText = ocrText
                    session.record.windowTitle = windowTitle
                    if let path = screenshotPath {
                        session.record.screenshotPath = path
                    }
                    if let ts = videoTimestamp {
                        session.record.videoTimestamp = ts
                    }
                    session.lastUpdateTime = now
                    session.frameCount += 1
                    currentSession = session

                    // Periodically persist the session (every 5 frames)
                    if session.frameCount % 5 == 0 {
                        await saveRecord(session.record)
                    }
                    return
                }
            }

            // Context changed — finalize current session and start new one
            session.record.duration = session.lastUpdateTime.timeIntervalSince(session.startTime)
            await saveRecord(session.record)
        }

        // Start new session
        let record = ActivityRecord(
            timestamp: now,
            appBundleID: appBundleID,
            windowTitle: windowTitle,
            ocrText: ocrText,
            duration: 0,
            screenshotPath: screenshotPath,
            videoTimestamp: videoTimestamp
        )
        currentSession = Session(
            record: record,
            startTime: now,
            lastUpdateTime: now,
            frameCount: 1
        )
    }

    /// Call on app quit / capture stop to flush the current session.
    func flush() async {
        guard var session = currentSession else { return }
        session.record.duration = session.lastUpdateTime.timeIntervalSince(session.startTime)
        await saveRecord(session.record)
        currentSession = nil
    }

    private func saveRecord(_ record: ActivityRecord) async {
        do {
            try await AppDatabase.shared.saveRecord(record)
        } catch {
            print("[ActivityProcessor] Save failed: \(error)")
        }
    }
}

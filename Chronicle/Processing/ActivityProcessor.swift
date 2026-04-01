import Foundation

/// Converts raw capture events into ActivityRecords with duration tracking.
/// Actor isolation serialises state mutations without explicit locking.
actor ActivityProcessor {

    private var lastTimestamp: Date = .distantPast
    private let maxDuration: TimeInterval = 300  // cap gaps at 5 min to avoid huge durations

    func process(ocrText: String, appBundleID: String, windowTitle: String) async {
        let now = Date()
        let duration = min(now.timeIntervalSince(lastTimestamp), maxDuration)
        lastTimestamp = now

        let record = ActivityRecord(
            timestamp: now,
            appBundleID: appBundleID,
            windowTitle: windowTitle,
            ocrText: ocrText,
            duration: duration
        )

        do {
            try await AppDatabase.shared.saveRecord(record)
        } catch {
            print("[ActivityProcessor] Save failed: \(error)")
        }
    }
}

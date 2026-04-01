import Foundation
import GRDB

struct ActivityRecord: Codable, Identifiable {
    var id: String          // UUID string
    var timestamp: Date
    var appBundleID: String
    var windowTitle: String
    var ocrText: String
    var duration: Double    // seconds spent in this context
    var screenshotPath: String?   // path to H.265 hourly video segment
    var videoTimestamp: Double?   // seconds offset within that video file

    init(
        id: UUID = .init(),
        timestamp: Date = .init(),
        appBundleID: String,
        windowTitle: String,
        ocrText: String,
        duration: Double = 0,
        screenshotPath: String? = nil,
        videoTimestamp: Double? = nil
    ) {
        self.id = id.uuidString
        self.timestamp = timestamp
        self.appBundleID = appBundleID
        self.windowTitle = windowTitle
        self.ocrText = ocrText
        self.duration = duration
        self.screenshotPath = screenshotPath
        self.videoTimestamp = videoTimestamp
    }
}

extension ActivityRecord: Hashable {
    static func == (lhs: ActivityRecord, rhs: ActivityRecord) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension ActivityRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "activity_records" }
}

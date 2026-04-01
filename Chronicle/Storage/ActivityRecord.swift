import Foundation
import GRDB

struct ActivityRecord: Codable, Identifiable {
    var id: String          // UUID string
    var timestamp: Date
    var appBundleID: String
    var windowTitle: String
    var ocrText: String
    var duration: Double    // seconds spent in this context

    init(
        id: UUID = .init(),
        timestamp: Date = .init(),
        appBundleID: String,
        windowTitle: String,
        ocrText: String,
        duration: Double = 0
    ) {
        self.id = id.uuidString
        self.timestamp = timestamp
        self.appBundleID = appBundleID
        self.windowTitle = windowTitle
        self.ocrText = ocrText
        self.duration = duration
    }
}

extension ActivityRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "activity_records" }
}

import Foundation
import GRDB

struct DailySummary: Codable, Identifiable {
    var id: String
    var date: Date
    var summaryText: String
    var keyActivities: String   // JSON-encoded [String]
    var productiveHours: Double

    init(
        id: UUID = .init(),
        date: Date,
        summaryText: String,
        keyActivities: [String] = [],
        productiveHours: Double = 0
    ) {
        self.id = id.uuidString
        self.date = date
        self.summaryText = summaryText
        self.keyActivities = (try? String(data: JSONEncoder().encode(keyActivities), encoding: .utf8)) ?? "[]"
        self.productiveHours = productiveHours
    }

    var keyActivitiesArray: [String] {
        guard let data = keyActivities.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return array
    }
}

extension DailySummary: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "daily_summaries" }
}

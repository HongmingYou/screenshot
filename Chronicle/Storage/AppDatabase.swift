import Foundation
import GRDB

final class AppDatabase {

    static let shared: AppDatabase = {
        do {
            return try AppDatabase()
        } catch {
            fatalError("[AppDatabase] Initialization failed: \(error)")
        }
    }()

    private let dbPool: DatabasePool

    private init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Chronicle", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dbPath = dir.appendingPathComponent("chronicle.sqlite").path

        var config = Configuration()
        config.prepareDatabase { db in
            // WAL mode: readers never block writers; writers never block readers.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        dbPool = try DatabasePool(path: dbPath, configuration: config)
        try applyMigrations()
    }

    // MARK: - Migrations

    private func applyMigrations() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            // Activity records
            try db.create(table: "activity_records") { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("appBundleID", .text).notNull()
                t.column("windowTitle", .text).notNull()
                t.column("ocrText", .text).notNull()
                t.column("duration", .double).notNull().defaults(to: 0)
            }
            try db.create(
                index: "idx_activity_timestamp",
                on: "activity_records",
                columns: ["timestamp"]
            )
            try db.create(
                index: "idx_activity_app",
                on: "activity_records",
                columns: ["appBundleID"]
            )

            // FTS5 virtual table — synchronized with activity_records via triggers.
            // unicode61 tokenizer handles CJK characters correctly.
            try db.create(virtualTable: "activity_records_fts", using: FTS5()) { t in
                t.synchronize(withTable: "activity_records")
                t.tokenizer = .unicode61()
                t.column("ocrText")
                t.column("windowTitle")
                t.column("appBundleID")
            }

            // Daily summaries (populated by AI Summary layer in Phase 2+)
            try db.create(table: "daily_summaries") { t in
                t.column("id", .text).primaryKey()
                t.column("date", .date).notNull().unique()
                t.column("summaryText", .text).notNull()
                t.column("keyActivities", .text).notNull().defaults(to: "[]")
                t.column("productiveHours", .double).notNull().defaults(to: 0)
            }
        }

        try migrator.migrate(dbPool)
    }

    // MARK: - Writes

    func saveRecord(_ record: ActivityRecord) async throws {
        try await dbPool.write { db in
            try record.insert(db)
        }
    }

    func saveSummary(_ summary: DailySummary) async throws {
        try await dbPool.write { db in
            try summary.upsert(db)
        }
    }

    // MARK: - Reads

    func recentRecords(limit: Int = 20) async throws -> [ActivityRecord] {
        try await dbPool.read { db in
            try ActivityRecord
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func records(for date: Date) async throws -> [ActivityRecord] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end   = calendar.date(byAdding: .day, value: 1, to: start)!

        return try await dbPool.read { db in
            try ActivityRecord
                .filter(Column("timestamp") >= start && Column("timestamp") < end)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    /// Full-text search via FTS5 with prefix matching, falls back to LIKE on empty query.
    func search(query: String, limit: Int = 50) async throws -> [ActivityRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return try await recentRecords(limit: limit) }

        return try await dbPool.read { db in
            // Use FTS5 MATCH with prefix wildcard for responsive as-you-type search.
            try ActivityRecord.fetchAll(db, sql: """
                SELECT ar.*
                FROM   activity_records ar
                WHERE  ar.rowid IN (
                    SELECT rowid FROM activity_records_fts
                    WHERE  activity_records_fts MATCH ?
                )
                ORDER  BY ar.timestamp DESC
                LIMIT  ?
                """, arguments: ["\(q)*", limit])
        }
    }

    func todayStats() async throws -> TodayStats {
        let records = try await self.records(for: Date())

        var appDurations: [String: Double] = [:]
        var totalDuration: Double = 0
        for record in records {
            appDurations[record.appBundleID, default: 0] += record.duration
            totalDuration += record.duration
        }

        let topApps = appDurations
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { TodayStats.AppUsage(bundleID: $0.key, duration: $0.value) }

        return TodayStats(
            recordCount: records.count,
            totalDuration: totalDuration,
            topApps: topApps
        )
    }
}

// MARK: - Supporting types

struct TodayStats {
    struct AppUsage {
        let bundleID: String
        let duration: Double  // seconds
    }
    let recordCount: Int
    let totalDuration: Double
    let topApps: [AppUsage]

    static let empty = TodayStats(recordCount: 0, totalDuration: 0, topApps: [])
}

import Foundation

/// Generates AI-powered daily summaries using OpenRouter.
final class SummaryGenerator {
    static let shared = SummaryGenerator()
    private init() {}

    /// Generates (or regenerates) a DailySummary for the given date, saves it, and returns it.
    func generate(for date: Date) async throws -> DailySummary {
        let settings = AppSettings.shared
        guard !settings.openRouterAPIKey.isEmpty else {
            throw SummaryError.noAPIKey
        }

        let records = try await AppDatabase.shared.records(for: date)
        guard !records.isEmpty else {
            throw SummaryError.noData
        }

        let client = OpenRouterClient(apiKey: settings.openRouterAPIKey, model: settings.openRouterModel)

        let prompt = buildPrompt(from: records, date: date)
        let response = try await client.complete(
            systemPrompt: systemPrompt,
            userMessage: prompt
        )

        // Parse the structured response
        let (summaryText, keyActivities, productiveHours) = parseResponse(response, records: records)

        let summary = DailySummary(
            date: Calendar.current.startOfDay(for: date),
            summaryText: summaryText,
            keyActivities: keyActivities,
            productiveHours: productiveHours
        )

        try await AppDatabase.shared.saveSummary(summary)
        return summary
    }

    // MARK: - Prompt construction

    private var systemPrompt: String {
        """
        你是一个工作效率分析助手。用户会给你提供某天的屏幕活动记录，包括使用的应用程序、窗口标题和OCR识别的文字内容。
        请用中文生成一份简洁的每日工作总结，包括：
        1. 当天主要做了什么（2-4句话）
        2. 重点活动列表（3-6条，每条15字以内）
        3. 大致有效工作时长（小时）

        严格按照以下JSON格式输出，不要有额外内容：
        {
          "summary": "总结文字",
          "keyActivities": ["活动1", "活动2", "活动3"],
          "productiveHours": 6.5
        }
        """
    }

    private func buildPrompt(from records: [ActivityRecord], date: Date) -> String {
        let dateStr = DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)

        // Aggregate by app
        var appUsage: [String: (duration: Double, titles: Set<String>)] = [:]
        for r in records {
            let app = r.appBundleID.components(separatedBy: ".").last?.capitalized ?? r.appBundleID
            var entry = appUsage[app] ?? (0, [])
            entry.duration += r.duration
            entry.titles.insert(r.windowTitle)
            appUsage[app] = entry
        }

        var lines = ["日期: \(dateStr)", "总捕获次数: \(records.count)", ""]
        lines.append("应用使用情况:")
        for (app, usage) in appUsage.sorted(by: { $0.value.duration > $1.value.duration }) {
            let mins = Int(usage.duration / 60)
            let titles = usage.titles.prefix(3).joined(separator: "、")
            lines.append("  - \(app): \(mins)分钟，窗口: \(titles)")
        }

        // Sample OCR text (recent 20 records, truncated)
        lines.append("")
        lines.append("部分屏幕内容样本:")
        for r in records.prefix(20) {
            let snippet = r.ocrText.prefix(100).replacingOccurrences(of: "\n", with: " ")
            lines.append("  [\(r.appBundleID.components(separatedBy: ".").last ?? "")] \(snippet)")
        }

        return lines.joined(separator: "\n")
    }

    private func parseResponse(_ response: String, records: [ActivityRecord]) -> (String, [String], Double) {
        // Try to parse JSON from the response
        let text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        // Find JSON block
        if let start = text.range(of: "{"),
           let end = text.range(of: "}", options: .backwards),
           start.lowerBound <= end.lowerBound {
            let jsonStr = String(text[start.lowerBound...end.upperBound])
            if let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let summary = json["summary"] as? String ?? text
                let activities = json["keyActivities"] as? [String] ?? []
                let hours = json["productiveHours"] as? Double ?? defaultHours(from: records)
                return (summary, activities, hours)
            }
        }
        // Fallback
        return (text, [], defaultHours(from: records))
    }

    private func defaultHours(from records: [ActivityRecord]) -> Double {
        let total = records.reduce(0.0) { $0 + $1.duration }
        return (total / 3600).rounded(toPlaces: 1)
    }

    enum SummaryError: Error, LocalizedError {
        case noAPIKey, noData

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "请先在设置中填写 OpenRouter API Key"
            case .noData:   return "当天没有活动记录可供总结"
            }
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

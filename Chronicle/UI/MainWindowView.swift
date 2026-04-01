import SwiftUI
import AVFoundation

// MARK: - Sidebar item

private enum SidebarItem: Hashable {
    case date(Date)
    case summary(Date)
}

// MARK: - Main window

struct MainWindowView: View {
    @EnvironmentObject var captureManager: CaptureManager
    @State private var sidebarSelection: SidebarItem?
    @State private var selectedRecord: ActivityRecord?
    @State private var dates: [Date] = Self.recentDates()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationTitle("Chronicle")
        .toolbar { toolbarContent }
        .task { await selectLatestDateWithData() }
    }

    /// Auto-select the most recent date that has records, falling back to today.
    private func selectLatestDateWithData() async {
        for date in dates {
            let records = (try? await AppDatabase.shared.records(for: date)) ?? []
            if !records.isEmpty {
                sidebarSelection = .date(date)
                return
            }
        }
        sidebarSelection = .date(Calendar.current.startOfDay(for: Date()))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            ForEach(dates, id: \.self) { date in
                Section {
                    DateRow(date: date)
                        .tag(SidebarItem.date(date))
                    Label("每日总结", systemImage: "sparkles")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .tag(SidebarItem.summary(date))
                } header: {
                    Text(sectionTitle(for: date))
                        .textCase(nil)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    // MARK: - Detail pane routing

    @ViewBuilder
    private var detailPane: some View {
        switch sidebarSelection {
        case .date(let date):
            RecordsListView(date: date, selectedRecord: $selectedRecord)
        case .summary(let date):
            DailySummaryView(date: date)
        case nil:
            ContentUnavailableView("选择日期", systemImage: "calendar", description: Text("从左侧选择一个日期查看活动记录"))
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await captureManager.start() }
            } label: {
                Label("恢复录制", systemImage: "record.circle")
            }
            .disabled(captureManager.isRunning)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await captureManager.stop() }
            } label: {
                Label("暂停录制", systemImage: "pause.circle")
            }
            .disabled(!captureManager.isRunning)
        }
    }

    // MARK: - Helpers

    private static func recentDates() -> [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<14).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    private func sectionTitle(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日"
        return fmt.string(from: date)
    }
}

// MARK: - Date row (sidebar)

private struct DateRow: View {
    let date: Date
    @State private var count: Int = 0

    var body: some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundStyle(.tint)
                .frame(width: 20)
            Text(label)
                .font(.callout)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .task { await loadCount() }
    }

    private var label: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "M月d日"
        return fmt.string(from: date)
    }

    private func loadCount() async {
        let records = (try? await AppDatabase.shared.records(for: date)) ?? []
        count = records.count
    }
}

// MARK: - Records list view

struct RecordsListView: View {
    let date: Date
    @Binding var selectedRecord: ActivityRecord?

    @State private var records: [ActivityRecord] = []
    @State private var searchQuery = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isLoading = false

    var body: some View {
        HSplitView {
            // Left: search + list
            VStack(spacing: 0) {
                searchBar
                Divider()
                recordList
            }
            .frame(minWidth: 280, maxWidth: 400)

            // Right: detail
            if let record = selectedRecord {
                RecordDetailView(record: record)
            } else {
                ContentUnavailableView("选择记录", systemImage: "doc.text.magnifyingglass", description: Text("点击左侧记录查看详情"))
                    .frame(minWidth: 320)
            }
        }
        .task { await reload() }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索...", text: $searchQuery)
                .textFieldStyle(.plain)
                .onChange(of: searchQuery) { _, newValue in
                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        if newValue.isEmpty { await reload() } else { await performSearch() }
                    }
                }
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var recordList: some View {
        List(records, id: \.id, selection: $selectedRecord) { record in
            RecordListRow(record: record)
                .tag(record)
        }
        .listStyle(.plain)
        .overlay {
            if isLoading {
                ProgressView()
            } else if records.isEmpty {
                ContentUnavailableView(
                    searchQuery.isEmpty ? "暂无记录" : "无搜索结果",
                    systemImage: searchQuery.isEmpty ? "tray" : "magnifyingglass",
                    description: Text(searchQuery.isEmpty ? "当天没有活动记录" : "未找到 \"\(searchQuery)\"")
                )
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        records = (try? await AppDatabase.shared.records(for: date)) ?? []
    }

    private func performSearch() async {
        isLoading = true
        defer { isLoading = false }
        records = (try? await AppDatabase.shared.search(query: searchQuery, limit: 100)) ?? []
    }
}

// MARK: - Record list row

private struct RecordListRow: View {
    let record: ActivityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(appName)
                    .font(.callout.bold())
                    .lineLimit(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(record.windowTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(record.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(record.ocrText.prefix(120).replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var appName: String {
        record.appBundleID.components(separatedBy: ".").last?.capitalized ?? record.appBundleID
    }
}

// MARK: - Record detail view

struct RecordDetailView: View {
    let record: ActivityRecord
    @State private var frameImage: NSImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appName)
                            .font(.title2.bold())
                        Text(record.windowTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.timestamp, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(record.timestamp, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if record.duration > 0 {
                            Text(durationText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Divider()

                // Video frame preview (if available)
                if let img = frameImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                } else if record.screenshotPath != nil {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(height: 200)
                        .overlay(ProgressView())
                        .task { await loadFrame() }
                }

                // OCR Text
                GroupBox("识别文字") {
                    Text(record.ocrText)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 320)
    }

    private var appName: String {
        record.appBundleID.components(separatedBy: ".").last?.capitalized ?? record.appBundleID
    }

    private var durationText: String {
        let d = record.duration
        if d < 60 { return "\(Int(d))秒" }
        return "\(Int(d/60))分\(Int(d.truncatingRemainder(dividingBy: 60)))秒"
    }

    private func loadFrame() async {
        guard let path = record.screenshotPath else { return }
        // Try loading as JPEG thumbnail first
        if let img = NSImage(contentsOfFile: path) {
            frameImage = img
            return
        }
        // Fallback: extract frame from video file
        guard let ts = record.videoTimestamp else { return }
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter  = CMTime(seconds: 0.5, preferredTimescale: 600)
        let time = CMTime(seconds: ts, preferredTimescale: 1)
        if let cgImg = try? await gen.image(at: time).image {
            frameImage = NSImage(cgImage: cgImg, size: .zero)
        }
    }
}

// MARK: - Daily summary view

struct DailySummaryView: View {
    let date: Date

    @State private var summary: DailySummary?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("每日总结")
                            .font(.title2.bold())
                        Text(date, style: .date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    generateButton
                }

                if isGenerating {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在生成总结...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                }

                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                if let s = summary {
                    summaryContent(s)
                } else if !isGenerating {
                    ContentUnavailableView(
                        "暂无总结",
                        systemImage: "sparkles",
                        description: Text("点击「生成总结」使用 AI 分析今天的活动")
                    )
                }
            }
            .padding(24)
        }
        .frame(minWidth: 360)
        .task { await loadExistingSummary() }
    }

    @ViewBuilder
    private var generateButton: some View {
        Button {
            Task { await generateSummary() }
        } label: {
            Label(summary == nil ? "生成总结" : "重新生成", systemImage: "sparkles")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isGenerating)
    }

    @ViewBuilder
    private func summaryContent(_ s: DailySummary) -> some View {
        GroupBox("今日概览") {
            Text(s.summaryText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        }

        if !s.keyActivitiesArray.isEmpty {
            GroupBox("重点活动") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(s.keyActivitiesArray, id: \.self) { activity in
                        Label(activity, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
        }

        HStack(spacing: 4) {
            Image(systemName: "clock.fill").foregroundStyle(.tint)
            Text("有效工作时长: ")
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f 小时", s.productiveHours))
                .bold()
        }
        .font(.callout)
    }

    private func loadExistingSummary() async {
        summary = try? await AppDatabase.shared.summary(for: date)
    }

    private func generateSummary() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            summary = try await SummaryGenerator.shared.generate(for: date)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

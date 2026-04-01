import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject var captureManager: CaptureManager
    @State private var searchQuery = ""
    @State private var records: [ActivityRecord] = []
    @State private var stats: TodayStats = .empty
    @State private var isLoadingSearch = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            searchSection
            Divider()
            recordsSection
            Divider()
            footerSection
        }
        .frame(width: 320)
        .task { await reload() }
        // Refresh stats whenever capture count ticks up
        .onChange(of: captureManager.captureCount) { _ in
            Task { await reload() }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Chronicle")
                    .font(.headline)
                statusIndicator
            }
            Spacer()
            statsBlock
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var statusIndicator: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(captureManager.isRunning ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(captureManager.isRunning ? "Recording" : "Paused")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statsBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(stats.recordCount)")
                .font(.title2.monospacedDigit().bold())
            Text("captures today")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search

    private var searchSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            TextField("Search history…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { Task { await performSearch() } }
            if !searchQuery.isEmpty {
                Button { searchQuery = ""; Task { await reload() } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Records list

    private var recordsSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if records.isEmpty {
                    Text(searchQuery.isEmpty ? "No captures yet — recording will start shortly." : "No results for "\(searchQuery)"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(20)
                } else {
                    ForEach(records) { record in
                        RecordRow(record: record)
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
        .frame(maxHeight: 270)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button(captureManager.isRunning ? "Pause" : "Resume") {
                Task {
                    if captureManager.isRunning { await captureManager.stop() }
                    else { await captureManager.start() }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.accent)

            Spacer()

            if let err = captureManager.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(err)
            }

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Data loading

    private func reload() async {
        async let recordsTask = (try? await AppDatabase.shared.recentRecords(limit: 25)) ?? []
        async let statsTask   = (try? await AppDatabase.shared.todayStats()) ?? .empty
        let (r, s) = await (recordsTask, statsTask)
        records = r
        stats   = s
    }

    private func performSearch() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            await reload(); return
        }
        isLoadingSearch = true
        defer { isLoadingSearch = false }
        records = (try? await AppDatabase.shared.search(query: searchQuery, limit: 40)) ?? []
    }
}

// MARK: - Record row

struct RecordRow: View {
    let record: ActivityRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(shortAppName(record.appBundleID))
                        .font(.caption.bold())
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(record.windowTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(record.ocrText.prefix(120).replacingOccurrences(of: "\n", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(record.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func shortAppName(_ bundleID: String) -> String {
        bundleID.components(separatedBy: ".").last?.capitalized ?? bundleID
    }
}

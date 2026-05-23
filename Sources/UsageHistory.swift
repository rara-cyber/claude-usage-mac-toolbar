import Foundation

struct UsageSnapshot: Codable {
    let timestamp: Date
    let sessionPct: Double
    let sessionResetTimestamp: Date?
    let weeklyPct: Double
    let weeklyResetTimestamp: Date?
}

class UsageHistory {
    private var snapshots: [UsageSnapshot] = []
    private let fileURL: URL
    private let maxAge: TimeInterval = 7 * 24 * 3600

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClaudeUsageBar")
        fileURL = appDir.appendingPathComponent("usage_history.json")

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Public

    /// Last persisted snapshot, converted back to UsageData. Used to render
    /// the menu bar instantly on cold start while the first poll is in flight.
    func cachedUsage() -> UsageData? {
        guard let last = snapshots.last else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return UsageData(
            fiveHourPct: last.sessionPct,
            fiveHourReset: last.sessionResetTimestamp.map { iso.string(from: $0) },
            sevenDayPct: last.weeklyPct,
            sevenDayReset: last.weeklyResetTimestamp.map { iso.string(from: $0) }
        )
    }

    func record(_ usage: UsageData) {
        let snapshot = UsageSnapshot(
            timestamp: Date(),
            sessionPct: usage.fiveHourPct,
            sessionResetTimestamp: parseISO8601(usage.fiveHourReset),
            weeklyPct: usage.sevenDayPct,
            weeklyResetTimestamp: parseISO8601(usage.sevenDayReset)
        )
        snapshots.append(snapshot)
        pruneOldEntries()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshots = (try? decoder.decode([UsageSnapshot].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func pruneOldEntries() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        snapshots.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Helpers

    private func parseISO8601(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

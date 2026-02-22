import Foundation

struct UsageSnapshot: Codable {
    let timestamp: Date
    let sessionPct: Double
    let sessionResetTimestamp: Date?
    let weeklyPct: Double
    let weeklyResetTimestamp: Date?
}

enum PaceLevel {
    case green, yellow, red, unknown
}

struct Forecast {
    let projectedPctAtReset: Double?
    let pace: PaceLevel
}

enum ForecastWindow {
    case session   // 5-hour
    case weekly    // 7-day
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

    func forecast(for window: ForecastWindow) -> Forecast {
        let cycle = currentCycleSnapshots(for: window)
        guard cycle.count >= 2 else {
            return Forecast(projectedPctAtReset: nil, pace: .unknown)
        }

        let latest = cycle.last!
        let latestPct = pct(latest, window)

        if latestPct >= 95 {
            return Forecast(projectedPctAtReset: 100, pace: .red)
        }

        guard let resetDate = resetDate(latest, window) else {
            return Forecast(projectedPctAtReset: nil, pace: .unknown)
        }

        let hoursUntilReset = resetDate.timeIntervalSinceNow / 3600
        if hoursUntilReset <= 0 {
            return Forecast(projectedPctAtReset: nil, pace: .green)
        }

        // Recent data window: 1h for session (5h cycle), 3h for weekly
        let recentHours: Double = window == .session ? 1 : 3
        let recentCutoff = Date().addingTimeInterval(-recentHours * 3600)
        let recentCycle = cycle.filter { $0.timestamp >= recentCutoff }
        let workingSet = recentCycle.count >= 2 ? recentCycle : cycle

        // Need at least 5 min span for session, 10 min for weekly
        let minSpanMinutes: Double = window == .session ? 5 : 10
        let earliest = workingSet.first!
        let spanHours = workingSet.last!.timestamp.timeIntervalSince(earliest.timestamp) / 3600
        if spanHours < minSpanMinutes / 60.0 {
            return Forecast(projectedPctAtReset: nil, pace: .unknown)
        }

        let slope = (pct(workingSet.last!, window) - pct(earliest, window)) / spanHours

        if slope <= 0 {
            let pace: PaceLevel = latestPct < 80 ? .green : .yellow
            return Forecast(projectedPctAtReset: latestPct, pace: pace)
        }

        let projected = min(100, max(0, latestPct + slope * hoursUntilReset))

        let pace: PaceLevel
        if projected >= 95 {
            pace = .red
        } else if projected >= 80 {
            pace = .yellow
        } else {
            pace = .green
        }

        return Forecast(projectedPctAtReset: projected, pace: pace)
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

    private func pct(_ snapshot: UsageSnapshot, _ window: ForecastWindow) -> Double {
        window == .session ? snapshot.sessionPct : snapshot.weeklyPct
    }

    private func resetDate(_ snapshot: UsageSnapshot, _ window: ForecastWindow) -> Date? {
        window == .session ? snapshot.sessionResetTimestamp : snapshot.weeklyResetTimestamp
    }

    private func currentCycleSnapshots(for window: ForecastWindow) -> [UsageSnapshot] {
        guard let last = snapshots.last,
              let lastReset = resetDate(last, window) else {
            return snapshots
        }

        var cycle = snapshots.filter { resetDate($0, window) == lastReset }

        // Detect sudden drops (reset mid-data) and discard pre-drop data
        var cleanStart = 0
        for i in 1..<cycle.count {
            if pct(cycle[i], window) < pct(cycle[i - 1], window) - 20 {
                cleanStart = i
            }
        }
        if cleanStart > 0 {
            cycle = Array(cycle[cleanStart...])
        }

        return cycle
    }

    private func parseISO8601(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

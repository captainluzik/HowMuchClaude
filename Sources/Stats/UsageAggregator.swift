import Foundation
import os

// MARK: - Usage Aggregator

struct UsageAggregator {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "UsageAggregator"
    )

    private var costCalculator: CostCalculator

    init(costCalculator: CostCalculator = CostCalculator()) {
        self.costCalculator = costCalculator
    }

    // MARK: - Public API

    mutating func aggregate(_ entries: [UsageEntry], now: Date = Date()) -> AggregatedStats {
        guard !entries.isEmpty else {
            Self.logger.debug("No entries to aggregate")
            return .empty
        }

        let calendar = Calendar.current

        let startOfToday = calendar.startOfDay(for: now)
        let oneHourAgo = calendar.date(byAdding: .hour, value: -1, to: now) ?? now
        let fiveHoursAgo = calendar.date(byAdding: .hour, value: -5, to: now) ?? now
        let twentyFourHoursAgo = calendar.date(byAdding: .hour, value: -24, to: now) ?? now
        let startOfWeek = Self.startOfCurrentWeek(now: now, calendar: calendar)
        let startOfMonth = Self.startOfCurrentMonth(now: now, calendar: calendar)

        var today = PeriodStats()
        var thisHour = PeriodStats()
        var last5h = PeriodStats()
        var last24h = PeriodStats()
        var thisWeek = PeriodStats()
        var thisMonth = PeriodStats()
        var allTime = PeriodStats()

        var todaySessionIds = Set<String>()
        var thisHourSessionIds = Set<String>()
        var last5hSessionIds = Set<String>()
        var last24hSessionIds = Set<String>()
        var thisWeekSessionIds = Set<String>()
        var thisMonthSessionIds = Set<String>()
        var allTimeSessionIds = Set<String>()

        var modelBuckets: [String: (stats: PeriodStats, sessionIds: Set<String>)] = [:]

        let futureThreshold = now.addingTimeInterval(60)

        for entry in entries {
            let ts = min(entry.timestamp, futureThreshold)
            let modelKey = entry.modelShortName

            costCalculator.addCost(to: &allTime, entry: entry)
            allTimeSessionIds.insert(entry.sessionId)

            if ts >= startOfToday {
                costCalculator.addCost(to: &today, entry: entry)
                todaySessionIds.insert(entry.sessionId)
            }
            if ts >= oneHourAgo {
                costCalculator.addCost(to: &thisHour, entry: entry)
                thisHourSessionIds.insert(entry.sessionId)
            }
            if ts >= fiveHoursAgo {
                costCalculator.addCost(to: &last5h, entry: entry)
                last5hSessionIds.insert(entry.sessionId)
            }
            if ts >= twentyFourHoursAgo {
                costCalculator.addCost(to: &last24h, entry: entry)
                last24hSessionIds.insert(entry.sessionId)
            }
            if ts >= startOfWeek {
                costCalculator.addCost(to: &thisWeek, entry: entry)
                thisWeekSessionIds.insert(entry.sessionId)
            }
            if ts >= startOfMonth {
                costCalculator.addCost(to: &thisMonth, entry: entry)
                thisMonthSessionIds.insert(entry.sessionId)
            }

            var bucket = modelBuckets[modelKey] ?? (stats: PeriodStats(), sessionIds: Set<String>())
            costCalculator.addCost(to: &bucket.stats, entry: entry)
            bucket.sessionIds.insert(entry.sessionId)
            modelBuckets[modelKey] = bucket
        }

        today.sessionCount = todaySessionIds.count
        thisHour.sessionCount = thisHourSessionIds.count
        last5h.sessionCount = last5hSessionIds.count
        last24h.sessionCount = last24hSessionIds.count
        thisWeek.sessionCount = thisWeekSessionIds.count
        thisMonth.sessionCount = thisMonthSessionIds.count
        allTime.sessionCount = allTimeSessionIds.count

        var byModel: [String: PeriodStats] = [:]
        for (modelKey, bucket) in modelBuckets {
            var stats = bucket.stats
            stats.sessionCount = bucket.sessionIds.count
            byModel[modelKey] = stats
        }

        let currentSession = Self.buildCurrentSession(
            from: entries,
            costCalculator: costCalculator
        )

        Self.logger.debug(
            "Aggregated \(entries.count) entries — allTime cost: $\(String(format: "%.4f", allTime.estimatedCostUSD))"
        )

        return AggregatedStats(
            today: today,
            thisHour: thisHour,
            last5h: last5h,
            last24h: last24h,
            thisWeek: thisWeek,
            thisMonth: thisMonth,
            allTime: allTime,
            currentSession: currentSession,
            byModel: byModel,
            apiQuotas: .empty
        )
    }

    // MARK: - Private Helpers

    private static func startOfCurrentWeek(now: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return cal.date(from: components) ?? cal.startOfDay(for: now)
    }

    private static func startOfCurrentMonth(now: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: components) ?? calendar.startOfDay(for: now)
    }

    /// Find the session with the latest entry and build SessionStats for it.
    private static func buildCurrentSession(
        from entries: [UsageEntry],
        costCalculator: CostCalculator
    ) -> SessionStats? {
        guard let latestEntry = entries.max(by: { $0.timestamp < $1.timestamp }) else {
            return nil
        }

        let sessionId = latestEntry.sessionId
        let sessionEntries = entries.filter { $0.sessionId == sessionId }

        guard let earliest = sessionEntries.min(by: { $0.timestamp < $1.timestamp }),
              let latest = sessionEntries.max(by: { $0.timestamp < $1.timestamp })
        else {
            return nil
        }

        let totalTokens = sessionEntries.reduce(0) { $0 + $1.totalTokens }
        let totalCost = sessionEntries.reduce(0.0) { $0 + costCalculator.cost(for: $1) }
        let duration = latest.timestamp.timeIntervalSince(earliest.timestamp)

        return SessionStats(
            sessionId: sessionId,
            startTime: earliest.timestamp,
            duration: duration,
            totalTokens: totalTokens,
            estimatedCostUSD: totalCost,
            model: latestEntry.modelShortName,
            messageCount: sessionEntries.count
        )
    }
}

import Foundation

// MARK: - Aggregated Stats

struct AggregatedStats: Sendable {

    let today: PeriodStats
    let thisHour: PeriodStats
    let last5h: PeriodStats
    let last24h: PeriodStats
    let thisWeek: PeriodStats
    let thisMonth: PeriodStats
    let allTime: PeriodStats
    let currentSession: SessionStats?
    let byModel: [String: PeriodStats]
    let apiQuotas: APIQuotas

    static let empty = AggregatedStats(
        today: .zero,
        thisHour: .zero,
        last5h: .zero,
        last24h: .zero,
        thisWeek: .zero,
        thisMonth: .zero,
        allTime: .zero,
        currentSession: nil,
        byModel: [:],
        apiQuotas: .empty
    )
}

// MARK: - Period Stats

struct PeriodStats: Sendable {

    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var estimatedCostUSD: Double = 0.0
    var messageCount: Int = 0
    var sessionCount: Int = 0

    var totalTokens: Int { inputTokens + outputTokens }

    static let zero = PeriodStats()
}

// MARK: - Session Stats

struct SessionStats: Sendable {

    let sessionId: String
    let startTime: Date
    let duration: TimeInterval
    let totalTokens: Int
    let estimatedCostUSD: Double
    let model: String
    let messageCount: Int
}

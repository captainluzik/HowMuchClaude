import Foundation

// MARK: - Cost Calculator

struct CostCalculator {

    private let pricingConfig: PricingConfig

    init(pricingConfig: PricingConfig = .default) {
        self.pricingConfig = pricingConfig
    }

    // MARK: - Public API

    func cost(for entry: UsageEntry) -> Double {
        let pricing = pricingConfig.pricing(for: entry.model)

        let inputCost = Double(max(0, entry.inputTokens)) * pricing.inputPerMillion / 1_000_000
        let outputCost = Double(max(0, entry.outputTokens)) * pricing.outputPerMillion / 1_000_000
        let cacheWriteCost = Double(max(0, entry.cacheCreationTokens)) * pricing.cacheWritePerMillion / 1_000_000
        let cacheReadCost = Double(max(0, entry.cacheReadTokens)) * pricing.cacheReadPerMillion / 1_000_000

        return inputCost + outputCost + cacheWriteCost + cacheReadCost
    }

    mutating func addCost(to stats: inout PeriodStats, entry: UsageEntry) {
        stats.inputTokens += max(0, entry.inputTokens)
        stats.outputTokens += max(0, entry.outputTokens)
        stats.cacheReadTokens += max(0, entry.cacheReadTokens)
        stats.cacheCreationTokens += max(0, entry.cacheCreationTokens)
        stats.messageCount += 1
        stats.estimatedCostUSD += cost(for: entry)
    }
}

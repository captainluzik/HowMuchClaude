import Foundation

// MARK: - Model Pricing

struct ModelPricing: Sendable {

    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheWritePerMillion: Double
    let cacheReadPerMillion: Double

    func cost(
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let scale = 1_000_000.0
        return Double(inputTokens) * inputPerMillion / scale
            + Double(outputTokens) * outputPerMillion / scale
            + Double(cacheCreationTokens) * cacheWritePerMillion / scale
            + Double(cacheReadTokens) * cacheReadPerMillion / scale
    }
}

// MARK: - Pricing Config

struct PricingConfig: Sendable {

    static let `default` = PricingConfig()

    private let sonnetPricing = ModelPricing(
        inputPerMillion: 3.0,
        outputPerMillion: 15.0,
        cacheWritePerMillion: 3.75,
        cacheReadPerMillion: 0.30
    )

    private let opusPricing = ModelPricing(
        inputPerMillion: 15.0,
        outputPerMillion: 75.0,
        cacheWritePerMillion: 18.75,
        cacheReadPerMillion: 1.50
    )

    func pricing(for model: String) -> ModelPricing {
        let lowercased = model.lowercased()

        if lowercased.contains("opus") {
            return opusPricing
        }

        return sonnetPricing
    }
}

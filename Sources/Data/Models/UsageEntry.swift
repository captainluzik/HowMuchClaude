import Foundation

// MARK: - Usage Entry

struct UsageEntry: Identifiable, Hashable, Sendable {

    let id: String
    let timestamp: Date
    let sessionId: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - Model Short Name

extension UsageEntry {

    /// Parse "claude-sonnet-4-5-20250929" → "sonnet-4.5", "claude-opus-4-5-20250929" → "opus-4.5".
    var modelShortName: String {
        let lowercased = model.lowercased()
        let families = ["opus", "sonnet", "haiku"]

        for family in families {
            guard let familyRange = lowercased.range(of: family) else { continue }

            let afterFamily = lowercased[familyRange.upperBound...]
            let segments = afterFamily.split(separator: "-", omittingEmptySubsequences: true)

            var versionParts: [String] = []
            for segment in segments {
                if segment.allSatisfy(\.isNumber), segment.count <= 2 {
                    versionParts.append(String(segment))
                } else {
                    break
                }
            }

            if versionParts.isEmpty {
                return family
            }

            return "\(family)-\(versionParts.joined(separator: "."))"
        }

        var name = model
        if name.lowercased().hasPrefix("claude-") {
            name = String(name.dropFirst("claude-".count))
        }

        if let lastDash = name.lastIndex(of: "-") {
            let suffix = name[name.index(after: lastDash)...]
            if suffix.count >= 8, suffix.allSatisfy(\.isNumber) {
                name = String(name[..<lastDash])
            }
        }

        return name
    }
}

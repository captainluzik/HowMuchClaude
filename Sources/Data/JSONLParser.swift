import Foundation
import os

// MARK: - JSONL Parser

struct JSONLParser {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "JSONLParser"
    )

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        return formatter
    }()

    private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func parse(line: String) -> UsageEntry? {
        parseLine(line)
    }

    func parseLine(_ line: String) -> UsageEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let type = json["type"] as? String, type == "assistant" else {
            return nil
        }

        guard let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }

        guard let model = message["model"] as? String, model != "<synthetic>" else {
            return nil
        }

        let messageId = message["id"] as? String ?? ""
        let requestId = json["requestId"] as? String ?? ""
        let sessionId = json["sessionId"] as? String ?? ""

        let dedupId = "\(messageId):\(requestId)"

        let timestamp = parseTimestamp(json["timestamp"])

        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0

        if inputTokens == 0, outputTokens == 0,
           cacheCreationTokens == 0, cacheReadTokens == 0 {
            return nil
        }

        return UsageEntry(
            id: dedupId,
            timestamp: timestamp,
            sessionId: sessionId,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreationTokens,
            cacheReadTokens: cacheReadTokens
        )
    }

    func parseLines(_ lines: [String]) -> [UsageEntry] {
        lines.compactMap { parseLine($0) }
    }

    private func parseTimestamp(_ value: Any?) -> Date {
        guard let raw = value as? String else { return Date() }

        if let date = Self.iso8601Formatter.date(from: raw) {
            return date
        }

        if let date = Self.iso8601FallbackFormatter.date(from: raw) {
            return date
        }

        Self.logger.warning("Unparseable timestamp: \(raw)")
        return Date()
    }
}

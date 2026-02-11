import Foundation
import os

// MARK: - Stats Manager

@MainActor
final class StatsManager: ObservableObject {

    private nonisolated static let logger = Logger(
        subsystem: "com.howmuchclaude.app",
        category: "StatsManager"
    )

    // MARK: - Published State

    @Published var stats: AggregatedStats = .empty
    @Published var isLoading: Bool = false
    @Published var lastUpdateTime: Date?
    @Published var error: String?

    private var allEntries: [UsageEntry] = []
    private var loadTask: Task<Void, Never>?
    private var isInitialLoadComplete = false

    private let pathDiscovery = ClaudePathDiscovery()
    private let parser = JSONLParser()
    private var aggregator = UsageAggregator()
    private let apiClient = ClaudeAPIClient()

    // MARK: - Public API

    func performInitialLoad() {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        loadTask = Task.detached { [pathDiscovery, parser, apiClient] in
            do {
                let jsonlFiles = pathDiscovery.findAllJSONLFiles()
                Self.logger.info("Found \(jsonlFiles.count) JSONL files to process")

                var parsed: [UsageEntry] = []

                for file in jsonlFiles {
                    try Task.checkCancellation()
                    guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                        continue
                    }
                    let lines = content.components(separatedBy: "\n")
                    let entries = lines.compactMap { parser.parse(line: $0) }
                    parsed.append(contentsOf: entries)
                }

                try Task.checkCancellation()

                let deduplicated = Self.deduplicate(parsed)
                Self.logger.info("Parsed \(deduplicated.count) unique entries")

                let quotas = await apiClient.fetchQuotas()

                try Task.checkCancellation()
                await MainActor.run { [deduplicated, quotas] in
                    self.allEntries = deduplicated
                    var aggregated = self.aggregator.aggregate(deduplicated)
                    aggregated = Self.withQuotas(aggregated, quotas)
                    self.stats = aggregated
                    self.lastUpdateTime = Date()
                    self.isLoading = false
                    self.isInitialLoadComplete = true
                }
            } catch is CancellationError {
                Self.logger.debug("Load cancelled")
            } catch {
                Self.logger.error("Load failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func refresh() {
        guard isInitialLoadComplete, !isLoading else { return }

        loadTask = Task.detached { [pathDiscovery, parser, apiClient] in
            do {
                let jsonlFiles = pathDiscovery.findAllJSONLFiles()

                var parsed: [UsageEntry] = []

                for file in jsonlFiles {
                    try Task.checkCancellation()
                    guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                        continue
                    }
                    let lines = content.components(separatedBy: "\n")
                    let entries = lines.compactMap { parser.parse(line: $0) }
                    parsed.append(contentsOf: entries)
                }

                try Task.checkCancellation()

                let deduplicated = Self.deduplicate(parsed)

                let quotas = await apiClient.fetchQuotas()

                try Task.checkCancellation()
                await MainActor.run { [deduplicated, quotas] in
                    self.allEntries = deduplicated
                    var aggregated = self.aggregator.aggregate(deduplicated)
                    aggregated = Self.withQuotas(aggregated, quotas)
                    self.stats = aggregated
                    self.lastUpdateTime = Date()
                }
            } catch is CancellationError {
                Self.logger.debug("Refresh cancelled")
            } catch {
                Self.logger.error("Refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func reload() {
        Self.logger.info("Full reload requested")
        loadTask?.cancel()
        isInitialLoadComplete = false
        performInitialLoad()
    }

    // MARK: - Private Helpers

    private static func withQuotas(_ stats: AggregatedStats, _ quotas: APIQuotas) -> AggregatedStats {
        AggregatedStats(
            today: stats.today,
            thisHour: stats.thisHour,
            last5h: stats.last5h,
            last24h: stats.last24h,
            thisWeek: stats.thisWeek,
            thisMonth: stats.thisMonth,
            allTime: stats.allTime,
            currentSession: stats.currentSession,
            byModel: stats.byModel,
            apiQuotas: quotas
        )
    }

    private nonisolated static func deduplicate(_ entries: [UsageEntry]) -> [UsageEntry] {
        var seen = Set<String>()
        var unique: [UsageEntry] = []
        unique.reserveCapacity(entries.count)

        for entry in entries {
            if seen.insert(entry.id).inserted {
                unique.append(entry)
            }
        }

        return unique
    }
}

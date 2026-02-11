import Foundation
import os

// MARK: - Deduplication Store

actor DeduplicationStore {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "DeduplicationStore"
    )

    private var processedIds: Set<String> = []

    var count: Int { processedIds.count }

    func isDuplicate(_ entry: UsageEntry) -> Bool {
        processedIds.contains(entry.id)
    }

    func markProcessed(_ entry: UsageEntry) {
        processedIds.insert(entry.id)
    }

    func markProcessed(_ entries: [UsageEntry]) {
        for entry in entries {
            processedIds.insert(entry.id)
        }
    }

    func filterNew(_ entries: [UsageEntry]) -> [UsageEntry] {
        var result: [UsageEntry] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            if !processedIds.contains(entry.id) {
                processedIds.insert(entry.id)
                result.append(entry)
            }
        }
        return result
    }

    func reset() {
        let previousCount = processedIds.count
        processedIds.removeAll()
        Self.logger.info("Reset deduplication store (cleared \(previousCount) entries)")
    }
}

import Foundation
import os

// MARK: - Incremental File Reader

actor IncrementalFileReader {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "IncrementalFileReader"
    )

    private var offsets: [URL: UInt64] = [:]

    func readNewLines(from fileURL: URL) -> [String] {
        let storedOffset = offsets[fileURL] ?? 0

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Self.logger.warning("File does not exist: \(fileURL.path)")
            return []
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            Self.logger.warning("Cannot open file: \(fileURL.path)")
            return []
        }

        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: storedOffset)
        } catch {
            Self.logger.warning("Seek failed for \(fileURL.path): \(error.localizedDescription)")
            return []
        }

        guard let data = try? handle.readToEnd(), !data.isEmpty else {
            return []
        }

        let newOffset = storedOffset + UInt64(data.count)
        offsets[fileURL] = newOffset

        guard let chunk = String(data: data, encoding: .utf8) else {
            Self.logger.warning("UTF-8 decode failed for chunk in \(fileURL.path)")
            return []
        }

        let lines = chunk
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        Self.logger.debug("Read \(lines.count) new lines from \(fileURL.lastPathComponent)")
        return lines
    }

    func resetOffset(for fileURL: URL) {
        offsets[fileURL] = 0
    }

    func resetAllOffsets() {
        offsets.removeAll()
    }

    func currentOffset(for fileURL: URL) -> UInt64 {
        offsets[fileURL] ?? 0
    }
}

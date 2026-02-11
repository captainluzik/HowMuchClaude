import Foundation
import os

// MARK: - Claude Path Discovery

struct ClaudePathDiscovery {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "ClaudePathDiscovery"
    )

    func discoverProjectDirectories() -> [URL] {
        var candidates: [URL] = []

        if let envPaths = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            for rawPath in envPaths.split(separator: ",") {
                let trimmed = rawPath.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let url = URL(fileURLWithPath: trimmed, isDirectory: true)
                candidates.append(url)
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser

        candidates.append(home.appendingPathComponent(".config/claude/projects", isDirectory: true))
        candidates.append(home.appendingPathComponent(".claude/projects", isDirectory: true))

        let validDirs = candidates.filter { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else {
                return false
            }
            return containsJSONLFiles(in: url)
        }

        Self.logger.info("Discovered \(validDirs.count) Claude project directories")
        return validDirs
    }

    func findAllJSONLFiles() -> [URL] {
        findAllJSONLFiles(in: discoverProjectDirectories())
    }

    func findAllJSONLFiles(in directories: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default

        for directory in directories {
            guard let enumerator = fm.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                Self.logger.warning("Cannot enumerate directory: \(directory.path)")
                continue
            }

            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension.lowercased() == "jsonl" {
                    result.append(fileURL)
                }
            }
        }

        Self.logger.info("Found \(result.count) JSONL files")
        return result
    }

    private func containsJSONLFiles(in directory: URL) -> Bool {
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "jsonl" {
                return true
            }
        }

        return false
    }
}

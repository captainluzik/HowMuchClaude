import Foundation
import os

final class FileWatcher {

    enum Event {
        case fileModified(URL)
        case fileCreated(URL)
    }

    typealias EventHandler = ([Event]) -> Void

    private let logger = Logger(subsystem: "com.howmuchclaude.app", category: "FileWatcher")
    private var streams: [FSEventStreamRef] = []
    private var watchedDirectories: [URL] = []
    private var knownFiles: Set<String> = []
    private var eventHandler: EventHandler?
    private let debounceInterval: TimeInterval
    private var debounceWorkItem: DispatchWorkItem?
    private var pendingEvents: [Event] = []
    private let eventQueue = DispatchQueue(label: "com.howmuchclaude.filewatcher", qos: .utility)

    init(debounceInterval: TimeInterval = 0.3) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stopWatching()
    }

    // MARK: - Public API

    func startWatching(directories: [URL], handler: @escaping EventHandler) {
        stopWatching()

        self.eventHandler = handler
        self.watchedDirectories = directories

        for directory in directories {
            catalogExistingFiles(in: directory)
        }

        for directory in directories {
            createStream(for: directory)
        }

        logger.info("Started watching \(directories.count) directories for JSONL changes")
    }

    func stopWatching() {
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
        watchedDirectories.removeAll()
        knownFiles.removeAll()
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingEvents.removeAll()
        eventHandler = nil
        logger.info("Stopped watching directories")
    }

    // MARK: - Private

    private func catalogExistingFiles(in directory: URL) {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "jsonl" {
                knownFiles.insert(fileURL.path)
            }
        }
    }

    private func createStream(for directory: URL) {
        let pathsToWatch = [directory.path] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            logger.error("Failed to create FSEvent stream for \(directory.path)")
            return
        }

        FSEventStreamSetDispatchQueue(stream, eventQueue)
        FSEventStreamStart(stream)
        streams.append(stream)
    }

    fileprivate func handleFSEvent(paths: [String], flags: [FSEventStreamEventFlags]) {
        var newEvents: [Event] = []

        for (index, path) in paths.enumerated() {
            guard path.hasSuffix(".jsonl") else { continue }

            let url = URL(fileURLWithPath: path)
            let eventFlags = flags[index]

            let isCreated = (eventFlags & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
            let isModified = (eventFlags & UInt32(kFSEventStreamEventFlagItemModified)) != 0
            let isRenamed = (eventFlags & UInt32(kFSEventStreamEventFlagItemRenamed)) != 0

            if isCreated || (isRenamed && !knownFiles.contains(path)) {
                knownFiles.insert(path)
                newEvents.append(.fileCreated(url))
                logger.debug("New JSONL file detected: \(url.lastPathComponent)")
            } else if isModified {
                newEvents.append(.fileModified(url))
                logger.debug("JSONL file modified: \(url.lastPathComponent)")
            }
        }

        guard !newEvents.isEmpty else { return }

        pendingEvents.append(contentsOf: newEvents)

        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let events = self.pendingEvents
            self.pendingEvents.removeAll()

            guard !events.isEmpty else { return }

            var seen: [String: Event] = [:]
            for event in events {
                switch event {
                case .fileModified(let url), .fileCreated(let url):
                    seen[url.path] = event
                }
            }

            let dedupedEvents = Array(seen.values)
            self.logger.info("Dispatching \(dedupedEvents.count) file events")

            DispatchQueue.main.async { [weak self] in
                self?.eventHandler?(dedupedEvents)
            }
        }
        debounceWorkItem = workItem
        eventQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}

// MARK: - FSEvent C Callback

private func fsEventCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }

    let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

    let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    var paths: [String] = []
    var flags: [FSEventStreamEventFlags] = []

    for i in 0..<numEvents {
        if let cfPath = CFArrayGetValueAtIndex(cfArray, i) {
            let path = Unmanaged<CFString>.fromOpaque(cfPath).takeUnretainedValue() as String
            paths.append(path)
            flags.append(eventFlags[i])
        }
    }

    watcher.handleFSEvent(paths: paths, flags: flags)
}

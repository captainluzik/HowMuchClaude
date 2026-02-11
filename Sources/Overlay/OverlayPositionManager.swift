import AppKit
import os

@MainActor
final class OverlayPositionManager {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "OverlayPositionManager"
    )

    private static let edgeMargin: CGFloat = 16

    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Self.logger.info("Screen parameters changed, repositioning needed")
                self?.onScreenChange?()
            }
        }
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var onScreenChange: (() -> Void)?

    func position(_ window: NSWindow, at corner: OverlayPosition) {
        guard let screen = NSScreen.main else {
            Self.logger.warning("No main screen available for positioning")
            return
        }

        let visibleFrame = screen.visibleFrame
        let windowSize = window.frame.size
        let margin = Self.edgeMargin

        let origin: NSPoint
        switch corner {
        case .topLeft:
            origin = NSPoint(
                x: visibleFrame.minX + margin,
                y: visibleFrame.maxY - windowSize.height - margin
            )
        case .topRight:
            origin = NSPoint(
                x: visibleFrame.maxX - windowSize.width - margin,
                y: visibleFrame.maxY - windowSize.height - margin
            )
        case .bottomLeft:
            origin = NSPoint(
                x: visibleFrame.minX + margin,
                y: visibleFrame.minY + margin
            )
        case .bottomRight:
            origin = NSPoint(
                x: visibleFrame.maxX - windowSize.width - margin,
                y: visibleFrame.minY + margin
            )
        case .custom:
            return
        }

        window.setFrameOrigin(origin)
        Self.logger.debug("Positioned overlay at \(corner.rawValue)")
    }
}

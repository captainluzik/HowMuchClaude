import AppKit
import os

final class OverlayPanel: NSPanel {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "OverlayPanel"
    )

    var onDragEnd: ((NSPoint) -> Void)?
    var dragEnabled: Bool = false {
        didSet {
            Self.logger.info("Drag enabled: \(self.dragEnabled)")
        }
    }

    private var isDragging = false
    private var initialLocation: NSPoint = .zero

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        Self.logger.debug("Overlay panel initialized")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateBehavior(alwaysOnTop: Bool, clickThrough: Bool) {
        level = alwaysOnTop ? .floating : .normal
        ignoresMouseEvents = clickThrough
        Self.logger.info("Behavior updated - alwaysOnTop: \(alwaysOnTop), clickThrough: \(clickThrough)")
    }

    override func mouseDown(with event: NSEvent) {
        guard dragEnabled else {
            super.mouseDown(with: event)
            return
        }
        isDragging = true
        initialLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragEnabled, isDragging else {
            super.mouseDragged(with: event)
            return
        }

        let screenLocation = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: screenLocation.x - initialLocation.x,
            y: screenLocation.y - initialLocation.y
        )

        setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragEnabled else {
            super.mouseUp(with: event)
            return
        }
        guard isDragging else { return }
        isDragging = false

        onDragEnd?(frame.origin)
        Self.logger.info("Overlay dragged to: (\(self.frame.origin.x), \(self.frame.origin.y))")
    }
}

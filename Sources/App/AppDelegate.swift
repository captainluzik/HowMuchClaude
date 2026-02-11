import AppKit
import Combine
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "AppDelegate"
    )

    private let settings = SettingsStore()
    private let statsManager = StatsManager()
    private let positionManager = OverlayPositionManager()

    private var overlayPanel: OverlayPanel?
    private var statusBarController: StatusBarController?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var isSettingsOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupOverlayPanel()
        setupStatusBar()
        setupRefreshTimer()
        observeSettings()

        statsManager.performInitialLoad()

        Self.logger.info("HowMuchClaude launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        Self.logger.info("HowMuchClaude terminating")
    }

    private func setupOverlayPanel() {
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 200))

        let hostingView = NSHostingView(rootView: overlayContentView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        panel.onDragEnd = { [weak self] origin in
            self?.settings.customOverlayOrigin = origin
            self?.settings.overlayPosition = .custom
        }

        panel.updateBehavior(
            alwaysOnTop: settings.overlayAlwaysOnTop,
            clickThrough: settings.overlayClickThrough
        )

        if let customOrigin = settings.customOverlayOrigin {
            panel.setFrameOrigin(customOrigin)
        } else {
            positionManager.position(panel, at: settings.overlayPosition)
        }
        panel.orderFrontRegardless()

        if !settings.isOverlayVisible {
            panel.orderOut(nil)
        }

        positionManager.onScreenChange = { [weak self] in
            guard let self, let panel = self.overlayPanel else { return }
            if self.settings.overlayPosition != .custom {
                self.positionManager.position(panel, at: self.settings.overlayPosition)
            }
        }

        self.overlayPanel = panel

        DispatchQueue.main.async { [weak self] in
            self?.resizePanelToFit()
        }
    }

    private func resizePanelToFit() {
        guard let panel = overlayPanel, let hostingView = panel.contentView else { return }
        hostingView.invalidateIntrinsicContentSize()
        let fitting = hostingView.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }

        var frame = panel.frame
        let oldMaxY = frame.maxY
        frame.size = fitting
        frame.origin.y = oldMaxY - fitting.height
        panel.setFrame(frame, display: true, animate: false)
    }

    private func overlayContentView() -> some View {
        OverlayRootView(
            statsManager: statsManager,
            settings: settings
        )
    }

    private func setupStatusBar() {
        statusBarController = StatusBarController(
            statsManager: statsManager,
            settings: settings,
            onRefresh: { [weak self] in
                self?.statsManager.reload()
            },
            onSettingsOpen: { [weak self] in
                self?.isSettingsOpen = true
                self?.overlayPanel?.dragEnabled = true
                // Disable click-through while settings open so drag works
                self?.overlayPanel?.updateBehavior(
                    alwaysOnTop: self?.settings.overlayAlwaysOnTop ?? true,
                    clickThrough: false
                )
            },
            onSettingsClose: { [weak self] in
                self?.isSettingsOpen = false
                self?.overlayPanel?.dragEnabled = false
                // Restore click-through setting
                self?.overlayPanel?.updateBehavior(
                    alwaysOnTop: self?.settings.overlayAlwaysOnTop ?? true,
                    clickThrough: self?.settings.overlayClickThrough ?? true
                )
            }
        )
    }

    private func setupRefreshTimer() {
        scheduleTimer(interval: TimeInterval(settings.refreshInterval))
    }

    private func scheduleTimer(interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: max(interval, 1),
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.statsManager.refresh()
            }
        }
    }

    private func observeSettings() {
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let panel = self.overlayPanel else { return }

                let effectiveClickThrough = self.isSettingsOpen
                    ? false
                    : self.settings.overlayClickThrough
                panel.updateBehavior(
                    alwaysOnTop: self.settings.overlayAlwaysOnTop,
                    clickThrough: effectiveClickThrough
                )
                panel.dragEnabled = self.isSettingsOpen

                if self.settings.overlayPosition != .custom {
                    self.positionManager.position(panel, at: self.settings.overlayPosition)
                }

                if self.settings.isOverlayVisible {
                    panel.orderFrontRegardless()
                } else {
                    panel.orderOut(nil)
                }

                self.scheduleTimer(interval: TimeInterval(self.settings.refreshInterval))

                DispatchQueue.main.async {
                    self.resizePanelToFit()
                }
            }
            .store(in: &cancellables)
    }
}

private struct OverlayRootView: View {

    @ObservedObject var statsManager: StatsManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Group {
            if settings.isExpandedMode {
                ExpandedOverlayView(
                    statsManager: statsManager,
                    settings: settings
                )
            } else {
                CompactOverlayView(
                    statsManager: statsManager,
                    settings: settings
                )
            }
        }
    }
}

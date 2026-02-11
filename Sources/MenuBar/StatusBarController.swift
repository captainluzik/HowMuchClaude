import AppKit
import Combine
import os
import SwiftUI

@MainActor
final class StatusBarController: NSObject {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.howmuchclaude.app",
        category: "StatusBarController"
    )

    private let statusItem: NSStatusItem
    private let statsManager: StatsManager
    private let settings: SettingsStore
    private let onRefresh: (() -> Void)?
    private let onSettingsOpen: (() -> Void)?
    private let onSettingsClose: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    init(
        statsManager: StatsManager,
        settings: SettingsStore,
        onRefresh: @escaping () -> Void,
        onSettingsOpen: @escaping () -> Void,
        onSettingsClose: @escaping () -> Void
    ) {
        self.statsManager = statsManager
        self.settings = settings
        self.onRefresh = onRefresh
        self.onSettingsOpen = onSettingsOpen
        self.onSettingsClose = onSettingsClose
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        configureButton()
        observeChanges()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "cloud.fill",
            accessibilityDescription: "HowMuchClaude"
        )
        button.image?.size = NSSize(width: 18, height: 18)
        button.imagePosition = .imageLeading
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateStatusBarTitle()
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            showSettings()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let quotas = statsManager.stats.apiQuotas
        if let fiveHour = quotas.fiveHour {
            let resetPart = fiveHour.resetsInText.map { " · ↻ \($0)" } ?? ""
            let item = NSMenuItem(
                title: "5h: \(Int(fiveHour.percentUsed))%\(resetPart)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }
        if let sevenDay = quotas.sevenDay {
            let resetPart = sevenDay.resetsInText.map { " · ↻ \($0)" } ?? ""
            let item = NSMenuItem(
                title: "Week: \(Int(sevenDay.percentUsed))%\(resetPart)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let overlayToggle = NSMenuItem(
            title: settings.isOverlayVisible ? "Hide Overlay" : "Show Overlay",
            action: #selector(toggleOverlay),
            keyEquivalent: ""
        )
        overlayToggle.target = self
        menu.addItem(overlayToggle)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "HowMuchClaude"
            window.center()
            window.isReleasedWhenClosed = false

            let settingsView = SettingsView(settings: settings)
            window.contentView = NSHostingView(rootView: settingsView)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsWindowWillClose),
                name: NSWindow.willCloseNotification,
                object: window
            )

            settingsWindow = window
        }

        onSettingsOpen?()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func settingsWindowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow == settingsWindow else { return }
        onSettingsClose?()
    }

    private func observeChanges() {
        statsManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarTitle()
            }
            .store(in: &cancellables)
    }

    private func updateStatusBarTitle() {
        guard let button = statusItem.button else { return }
        let quotas = statsManager.stats.apiQuotas

        if let fiveHour = quotas.fiveHour {
            let pct = Int(fiveHour.percentUsed)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            ]
            button.attributedTitle = NSAttributedString(string: " \(pct)%", attributes: attrs)
        } else {
            button.title = ""
        }

        var tooltip = "HowMuchClaude"
        if let fiveHour = quotas.fiveHour {
            tooltip += "\n5h: \(Int(fiveHour.percentUsed))% used"
        }
        if let sevenDay = quotas.sevenDay {
            tooltip += "\nWeek: \(Int(sevenDay.percentUsed))% used"
        }
        button.toolTip = tooltip
    }

    @objc private func toggleOverlay() {
        settings.isOverlayVisible.toggle()
        Self.logger.info("Overlay visibility: \(self.settings.isOverlayVisible)")
    }

    @objc private func refreshNow() {
        Self.logger.info("Manual refresh")
        onRefresh?()
    }

    @objc private func quitApp() {
        Self.logger.info("Quit")
        NSApplication.shared.terminate(nil)
    }
}

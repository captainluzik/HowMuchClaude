import Combine
import Foundation
import os
import ServiceManagement
import SwiftUI

enum OverlayPosition: String, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .custom: return "Custom (Drag)"
        }
    }
}

enum OverlaySizePreset: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case wide = "Wide"

    var id: String { rawValue }

    var width: CGFloat {
        switch self {
        case .compact: return 160
        case .small: return 180
        case .medium: return 220
        case .large: return 280
        case .wide: return 340
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {

    private static let defaults = UserDefaults.standard

    @Published var overlayPosition: OverlayPosition {
        didSet { Self.defaults.set(overlayPosition.rawValue, forKey: "overlayPosition") }
    }

    @Published var overlaySizePreset: OverlaySizePreset {
        didSet { Self.defaults.set(overlaySizePreset.rawValue, forKey: "overlaySizePreset") }
    }

    @Published var overlayOpacity: Double {
        didSet { Self.defaults.set(overlayOpacity, forKey: "overlayOpacity") }
    }

    @Published var overlayBackgroundColorHex: String {
        didSet { Self.defaults.set(overlayBackgroundColorHex, forKey: "overlayBackgroundColorHex") }
    }

    @Published var overlayTextColorHex: String {
        didSet { Self.defaults.set(overlayTextColorHex, forKey: "overlayTextColorHex") }
    }

    var overlayBackgroundColor: Color {
        get { Color(hex: overlayBackgroundColorHex) ?? .black }
        set {
            overlayBackgroundColorHex = newValue.toHex() ?? "000000"
        }
    }

    var overlayTextColor: Color {
        get { Color(hex: overlayTextColorHex) ?? .white }
        set {
            overlayTextColorHex = newValue.toHex() ?? "FFFFFF"
        }
    }

    @Published var overlayAlwaysOnTop: Bool {
        didSet { Self.defaults.set(overlayAlwaysOnTop, forKey: "overlayAlwaysOnTop") }
    }

    @Published var overlayClickThrough: Bool {
        didSet { Self.defaults.set(overlayClickThrough, forKey: "overlayClickThrough") }
    }

    @Published var isOverlayVisible: Bool {
        didSet { Self.defaults.set(isOverlayVisible, forKey: "isOverlayVisible") }
    }

    @Published var showLimitBars: Bool {
        didSet { Self.defaults.set(showLimitBars, forKey: "showLimitBars") }
    }

    @Published var refreshInterval: Int {
        didSet { Self.defaults.set(refreshInterval, forKey: "refreshInterval") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            Self.defaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLaunchAtLogin()
        }
    }

    @Published var isExpandedMode: Bool {
        didSet { Self.defaults.set(isExpandedMode, forKey: "isExpandedMode") }
    }

    @Published var customOverlayOriginX: Double {
        didSet { Self.defaults.set(customOverlayOriginX, forKey: "customOverlayOriginX") }
    }

    @Published var customOverlayOriginY: Double {
        didSet { Self.defaults.set(customOverlayOriginY, forKey: "customOverlayOriginY") }
    }

    var customOverlayOrigin: NSPoint? {
        get {
            guard overlayPosition == .custom else { return nil }
            return NSPoint(x: customOverlayOriginX, y: customOverlayOriginY)
        }
        set {
            if let origin = newValue {
                customOverlayOriginX = Double(origin.x)
                customOverlayOriginY = Double(origin.y)
            }
        }
    }

    init() {
        let positionRaw = Self.defaults.string(forKey: "overlayPosition") ?? ""
        let sizeRaw = Self.defaults.string(forKey: "overlaySizePreset") ?? ""
        var opacity = Self.defaults.double(forKey: "overlayOpacity")
        if opacity == 0 { opacity = 0.35 }
        var interval = Self.defaults.integer(forKey: "refreshInterval")
        if interval == 0 { interval = 60 }

        overlayPosition = OverlayPosition(rawValue: positionRaw) ?? .topLeft
        overlaySizePreset = OverlaySizePreset(rawValue: sizeRaw) ?? .medium
        overlayOpacity = opacity
        overlayBackgroundColorHex = Self.defaults.string(forKey: "overlayBackgroundColorHex") ?? "000000"
        overlayTextColorHex = Self.defaults.string(forKey: "overlayTextColorHex") ?? "FFFFFF"
        overlayAlwaysOnTop = Self.defaults.object(forKey: "overlayAlwaysOnTop") as? Bool ?? true
        overlayClickThrough = Self.defaults.object(forKey: "overlayClickThrough") as? Bool ?? true
        isOverlayVisible = Self.defaults.object(forKey: "isOverlayVisible") as? Bool ?? true
        showLimitBars = Self.defaults.object(forKey: "showLimitBars") as? Bool ?? true
        refreshInterval = interval
        launchAtLogin = Self.defaults.bool(forKey: "launchAtLogin")
        isExpandedMode = Self.defaults.bool(forKey: "isExpandedMode")
        customOverlayOriginX = Self.defaults.double(forKey: "customOverlayOriginX")
        customOverlayOriginY = Self.defaults.double(forKey: "customOverlayOriginY")
    }

    func clampValues() {
        overlayOpacity = max(0.0, min(1.0, overlayOpacity))
        refreshInterval = max(30, min(300, refreshInterval))
    }

    private func updateLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            Logger(subsystem: "com.howmuchclaude.app", category: "LaunchAtLogin")
                .error("Failed to update launch at login: \(error.localizedDescription)")
        }
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String? {
        let uiColor = NSColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

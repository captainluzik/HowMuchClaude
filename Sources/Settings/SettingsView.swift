import SwiftUI

struct ColorPreset: Identifiable {
    let id = UUID()
    let name: String
    let background: Color
    let text: Color

    static let allPresets: [ColorPreset] = [
        ColorPreset(name: "Dark", background: .black, text: .white),
        ColorPreset(name: "Light", background: .white, text: .black),
        ColorPreset(name: "Navy", background: Color(red: 0.1, green: 0.15, blue: 0.3), text: .white),
        ColorPreset(name: "Forest", background: Color(red: 0.1, green: 0.25, blue: 0.15), text: .white),
        ColorPreset(name: "Maroon", background: Color(red: 0.3, green: 0.1, blue: 0.15), text: .white),
        ColorPreset(name: "Slate", background: Color(red: 0.2, green: 0.22, blue: 0.25), text: .white),
        ColorPreset(name: "Amber", background: Color(red: 0.25, green: 0.2, blue: 0.1), text: .white),
    ]
}

struct SettingsView: View {

    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView {
            appearanceTab
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            positionTab
                .tabItem {
                    Label("Position", systemImage: "arrow.up.left.and.arrow.down.right")
                }

            displayTab
                .tabItem {
                    Label("Display", systemImage: "eye")
                }
        }
        .frame(width: 420, height: 400)
        .padding()
    }

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sizePresetsSection

                Divider()

                colorPresetsSection

                Divider()

                opacitySection
            }
            .padding()
        }
    }

    private var sizePresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Size Preset")
                .font(.headline)

            Picker("Size", selection: $settings.overlaySizePreset) {
                ForEach(OverlaySizePreset.allCases) { preset in
                    Text("\(preset.rawValue) (\(Int(preset.width))px)")
                        .tag(preset)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var colorPresetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Color Theme")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                ForEach(ColorPreset.allPresets) { preset in
                    ColorPresetButton(
                        preset: preset,
                        isSelected: isColorPresetSelected(preset),
                        action: {
                            settings.overlayBackgroundColor = preset.background
                            settings.overlayTextColor = preset.text
                        }
                    )
                }
            }
        }
    }

    private var opacitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Opacity")
                    .font(.headline)
                Spacer()
                Text("\(Int(settings.overlayOpacity * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(value: $settings.overlayOpacity, in: 0.0...1.0, step: 0.05)

            HStack {
                Text("Transparent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Solid")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var positionTab: some View {
        Form {
            Section("Position") {
                Picker("Corner", selection: $settings.overlayPosition) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Behavior") {
                Toggle("Always on Top", isOn: $settings.overlayAlwaysOnTop)
                Toggle("Click Through", isOn: $settings.overlayClickThrough)
            }
        }
        .formStyle(.grouped)
    }

    private var displayTab: some View {
        Form {
            Section("Quotas") {
                Toggle("Show Quota Bars", isOn: $settings.showLimitBars)
            }

            Section("Refresh") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Interval:")
                        Spacer()
                        Text("\(settings.refreshInterval)s")
                            .font(.system(.body, design: .monospaced))
                    }
                    Slider(value: Binding(
                        get: { Double(settings.refreshInterval) },
                        set: { settings.refreshInterval = Int($0) }
                    ), in: 30...300, step: 30)
                }
            }

            Section("Startup") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    private func isColorPresetSelected(_ preset: ColorPreset) -> Bool {
        let bgHex = preset.background.toHex() ?? ""
        let textHex = preset.text.toHex() ?? ""
        let currentBg = settings.overlayBackgroundColor.toHex() ?? ""
        let currentText = settings.overlayTextColor.toHex() ?? ""
        return bgHex == currentBg && textHex == currentText
    }
}

struct ColorPresetButton: View {
    let preset: ColorPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(preset.background)
                    )
                    .frame(width: 60, height: 40)
                    .overlay(
                        Text("Aa")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(preset.text)
                    )

                Text(preset.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

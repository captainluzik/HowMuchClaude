import SwiftUI

struct CompactOverlayView: View {

    @ObservedObject var statsManager: StatsManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            if settings.showLimitBars {
                limitBarsRow
            }
        }
        .padding(12)
        .frame(width: settings.overlaySizePreset.width, alignment: .leading)
        .background(overlayBackground)
        .animation(.easeInOut(duration: 0.3), value: statsManager.stats.apiQuotas.fiveHour?.percentUsed ?? 0)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(settings.overlayTextColor.opacity(0.7))

            Text("Claude")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(settings.overlayTextColor.opacity(0.9))

            Spacer()

            if let fiveHour = statsManager.stats.apiQuotas.fiveHour {
                Text("\(Int(fiveHour.percentUsed))%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(quotaColor(percent: fiveHour.percentUsed))
                    .contentTransition(.numericText(countsDown: false))
            }
        }
    }

    private var limitBarsRow: some View {
        let quotas = statsManager.stats.apiQuotas

        return VStack(alignment: .leading, spacing: 4) {
            if let fiveHour = quotas.fiveHour {
                quotaBar(
                    label: "5h",
                    percentUsed: fiveHour.percentUsed,
                    resetText: fiveHour.resetsInText
                )
            }
            if let sevenDay = quotas.sevenDay {
                quotaBar(
                    label: "Week",
                    percentUsed: sevenDay.percentUsed,
                    resetText: sevenDay.resetsInText
                )
            }
            if !quotas.isValid {
                Text("No quota data")
                    .font(.system(size: 10))
                    .foregroundStyle(settings.overlayTextColor.opacity(0.35))
            }
        }
    }

    private func quotaBar(label: String, percentUsed: Double, resetText: String?) -> some View {
        let fraction = min(percentUsed / 100.0, 1.0)
        let percent = Int(percentUsed)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(settings.overlayTextColor.opacity(0.5))
                    .frame(width: 32, alignment: .leading)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(settings.overlayTextColor.opacity(0.1))

                        RoundedRectangle(cornerRadius: 2)
                            .fill(quotaColor(percent: percentUsed))
                            .frame(width: geometry.size.width * fraction)
                    }
                }
                .frame(height: 6)

                Text("\(percent)%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(settings.overlayTextColor.opacity(0.65))
                    .frame(width: 32, alignment: .trailing)
            }

            if let resetText {
                Text("↻ \(resetText)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(settings.overlayTextColor.opacity(0.35))
                    .padding(.leading, 38)
            }
        }
    }

    private func quotaColor(percent: Double) -> Color {
        if percent < 50 {
            return Color(red: 0.4, green: 0.9, blue: 0.5)
        } else if percent < 80 {
            return Color(red: 0.95, green: 0.75, blue: 0.3)
        } else {
            return Color(red: 0.95, green: 0.4, blue: 0.35)
        }
    }

    private var overlayBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(settings.overlayBackgroundColor.opacity(settings.overlayOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(settings.overlayTextColor.opacity(0.1), lineWidth: 0.5)
            )
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = Int(interval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
        return "\(minutes)m"
    }
    return "<1m"
}

import SwiftUI

struct ExpandedOverlayView: View {

    @ObservedObject var statsManager: StatsManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if settings.showLimitBars {
                divider
                limitsSection
            }
        }
        .padding(14)
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
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(quotaColor(percent: fiveHour.percentUsed))
                    .contentTransition(.numericText(countsDown: false))
            }
        }
        .padding(.bottom, 8)
    }

    private var limitsSection: some View {
        let quotas = statsManager.stats.apiQuotas

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quotas")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.overlayTextColor.opacity(0.7))

                Spacer()

                if let sub = quotas.subscriptionType {
                    Text(sub.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(settings.overlayTextColor.opacity(0.4))
                }
            }

            if let fiveHour = quotas.fiveHour {
                expandedQuotaBar(
                    label: "5h Session",
                    percentUsed: fiveHour.percentUsed,
                    resetText: fiveHour.resetsInText
                )
            }
            if let sevenDay = quotas.sevenDay {
                expandedQuotaBar(
                    label: "Weekly",
                    percentUsed: sevenDay.percentUsed,
                    resetText: sevenDay.resetsInText
                )
            }
            if let opus = quotas.sevenDayOpus {
                expandedQuotaBar(
                    label: "Opus (7d)",
                    percentUsed: opus.percentUsed,
                    resetText: opus.resetsInText
                )
            }
            if let sonnet = quotas.sevenDaySonnet {
                expandedQuotaBar(
                    label: "Sonnet (7d)",
                    percentUsed: sonnet.percentUsed,
                    resetText: sonnet.resetsInText
                )
            }
            if !quotas.isValid {
                Text("No quota data")
                    .font(.system(size: 10))
                    .foregroundStyle(settings.overlayTextColor.opacity(0.35))
            }
        }
    }

    private func expandedQuotaBar(label: String, percentUsed: Double, resetText: String?) -> some View {
        let fraction = min(percentUsed / 100.0, 1.0)
        let percent = Int(percentUsed)

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(settings.overlayTextColor.opacity(0.55))

                Spacer()

                if let resetText {
                    Text("↻ \(resetText)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(settings.overlayTextColor.opacity(0.4))
                }

                Text("\(percent)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(settings.overlayTextColor.opacity(0.75))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(settings.overlayTextColor.opacity(0.1))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(quotaColor(percent: percentUsed))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
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

    private var divider: some View {
        Rectangle()
            .fill(settings.overlayTextColor.opacity(0.08))
            .frame(height: 0.5)
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

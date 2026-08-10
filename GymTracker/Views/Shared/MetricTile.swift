import SwiftUI

struct MetricTile: View {
    @Environment(\.appTheme) private var appTheme

    let label: String
    let value: String
    let caption: String?
    let systemImage: String?

    init(
        label: String,
        value: String,
        caption: String? = nil,
        systemImage: String? = nil
    ) {
        self.label = label
        self.value = value
        self.caption = caption
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.accent)
                }

                Text(label)
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.mutedText)
                    .textCase(.uppercase)
            }

            Text(value)
                .font(AppTypography.largeMetric)
                .foregroundStyle(appTheme.colors.textPrimary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.mutedText)
                    .lineLimit(2)
            }
        }
        .padding(appTheme.metrics.compactCardPadding)
        .frame(maxWidth: .infinity, minHeight: appTheme.metrics.metricTileMinHeight, alignment: .topLeading)
        .background(appTheme.cardBackground, in: RoundedRectangle(cornerRadius: appTheme.metrics.compactCardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: appTheme.metrics.compactCardRadius, style: .continuous)
                .stroke(appTheme.cardBorder.opacity(0.48), lineWidth: 0.75)
        }
    }
}

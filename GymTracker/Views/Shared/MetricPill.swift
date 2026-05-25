import SwiftUI

struct MetricPill: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
            Text(value)
                .font(AppTypography.compactCardTitle)
                .foregroundStyle(appTheme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(appTheme.metrics.spacing12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: appTheme.metrics.radius12, style: .continuous)
                .stroke(appTheme.colors.cardBorder.opacity(0.45), lineWidth: 1)
        }
    }
}

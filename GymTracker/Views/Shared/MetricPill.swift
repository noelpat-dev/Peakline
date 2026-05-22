import SwiftUI

struct MetricPill: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(appTheme.colors.textSecondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(appTheme.colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

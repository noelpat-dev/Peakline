import SwiftUI

struct FitnessScreenHeader: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String?
    let systemImage: String?

    init(title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let systemImage {
                FitnessIconBadge(systemImage: systemImage, size: 38)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AppTypography.screenTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTypography.screenSubtitle)
                        .foregroundStyle(appTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

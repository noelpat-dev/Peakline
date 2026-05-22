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
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 34, height: 34)
                    .background(appTheme.colors.accentSurface, in: Circle())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
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

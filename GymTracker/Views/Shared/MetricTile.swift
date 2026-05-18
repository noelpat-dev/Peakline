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
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.accent)
                }

                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appTheme.mutedText)
                    .textCase(.uppercase)
            }

            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(appTheme.mutedText)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(appTheme.elevatedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

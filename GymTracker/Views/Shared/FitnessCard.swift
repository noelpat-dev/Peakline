import SwiftUI

struct FitnessCard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(appTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(appTheme.cardBorder, lineWidth: 1)
            }
    }
}

struct FitnessScreen<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String?
    let subtitle: String?
    let systemImage: String?
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let title {
                    FitnessScreenHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                }

                content
            }
            .padding()
        }
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
    }
}

struct PrimaryFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity)
            .background(appTheme.colors.accent.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

struct SecondaryFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(appTheme.colors.accent)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity)
            .background(appTheme.colors.accentSurface.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

struct NeutralFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(appTheme.colors.textPrimary)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .frame(maxWidth: .infinity)
            .background(appTheme.elevatedCardBackground.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

struct FilterChip: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? appTheme.colors.accent : appTheme.colors.textSecondary)
            .background(isSelected ? appTheme.colors.accentSurfaceStrong : appTheme.elevatedCardBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? appTheme.colors.accent.opacity(0.32) : appTheme.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

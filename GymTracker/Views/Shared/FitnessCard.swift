import SwiftUI

private struct FitnessCardShadowsEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var fitnessCardShadowsEnabled: Bool {
        get { self[FitnessCardShadowsEnabledKey.self] }
        set { self[FitnessCardShadowsEnabledKey.self] = newValue }
    }
}

enum FitnessCardStyle {
    case standard
    case compact
    case hero

    func padding(using metrics: AppThemeMetrics) -> CGFloat {
        switch self {
        case .standard:
            return metrics.standardCardPadding
        case .compact:
            return metrics.compactCardPadding
        case .hero:
            return metrics.heroCardPadding
        }
    }

    func cornerRadius(using metrics: AppThemeMetrics) -> CGFloat {
        switch self {
        case .standard:
            return metrics.standardCardRadius
        case .compact:
            return metrics.compactCardRadius
        case .hero:
            return metrics.heroCardRadius
        }
    }
}

struct FitnessCard<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.fitnessCardShadowsEnabled) private var shadowsEnabled

    private let style: FitnessCardStyle
    private let customPadding: CGFloat?
    private let content: Content

    init(
        style: FitnessCardStyle = .standard,
        padding: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.customPadding = padding
        self.content = content()
    }

    var body: some View {
        let metrics = appTheme.metrics
        let radius = style.cornerRadius(using: metrics)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .padding(customPadding ?? style.padding(using: metrics))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: shape)
            .overlay {
                shape
                    .stroke(appTheme.cardBorder.opacity(borderOpacity), lineWidth: borderWidth)
            }
            .shadow(
                color: shadowsEnabled ? shadowColor : .clear,
                radius: shadowsEnabled ? shadowRadius : 0,
                x: 0,
                y: shadowsEnabled ? shadowYOffset : 0
            )
            .contentShape(shape)
    }

    private var borderOpacity: Double {
        switch style {
        case .hero:
            return 0.80
        case .standard:
            return 0.58
        case .compact:
            return 0.44
        }
    }

    private var borderWidth: CGFloat {
        style == .hero ? 1 : 0.75
    }

    private var cardBackground: Color {
        appTheme.cardBackground
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.14 : 0.045)
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .hero:
            return 12
        case .standard:
            return 3
        case .compact:
            return 0
        }
    }

    private var shadowYOffset: CGFloat {
        switch style {
        case .hero:
            return 7
        case .standard:
            return 2
        case .compact:
            return 0
        }
    }
}

struct SwipeRevealRow<ID: Hashable, Content: View, Action: View>: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let id: ID
    @Binding var activeID: ID?
    let isEnabled: Bool
    private let content: Content
    private let action: Action

    @State private var horizontalOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var isHorizontalDrag = false

    init(
        id: ID,
        activeID: Binding<ID?>,
        isEnabled: Bool = true,
        @ViewBuilder content: () -> Content,
        @ViewBuilder action: () -> Action
    ) {
        self.id = id
        _activeID = activeID
        self.isEnabled = isEnabled
        self.content = content()
        self.action = action()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if isEnabled {
                action
                    .padding(.trailing, appTheme.metrics.swipeRevealActionTrailingPadding)
                    .opacity(revealProgress)
            }

            content
                .offset(x: isEnabled ? horizontalOffset : 0)
                .simultaneousGesture(swipeGesture, including: isEnabled ? .all : .none)
                .onTapGesture {
                    guard horizontalOffset != 0 else { return }
                    close()
                }
        }
        .onChange(of: activeID) { _, newValue in
            guard newValue != id, horizontalOffset != 0 else { return }
            close(updateActiveID: false)
        }
    }

    private var revealWidth: CGFloat { appTheme.metrics.swipeRevealWidth }

    private var revealProgress: CGFloat {
        min(1, abs(horizontalOffset) / revealWidth)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if !isHorizontalDrag {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    isHorizontalDrag = true
                    dragStartOffset = horizontalOffset
                    if activeID != id {
                        activeID = id
                    }
                }

                guard isHorizontalDrag else { return }
                horizontalOffset = clamped(dragStartOffset + value.translation.width)
            }
            .onEnded { value in
                defer {
                    isHorizontalDrag = false
                    dragStartOffset = horizontalOffset
                }

                guard abs(value.translation.width) > abs(value.translation.height) else {
                    close()
                    return
                }
                let projectedOffset = dragStartOffset + value.predictedEndTranslation.width
                let shouldOpen = projectedOffset < -(revealWidth * 0.45) || value.translation.width < -36

                withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
                    horizontalOffset = shouldOpen ? -revealWidth : 0
                }
                activeID = shouldOpen ? id : nil
                PerformanceTracer.mark(
                    .swipeRevealInteraction,
                    shouldOpen ? "settled=open" : "settled=closed"
                )
            }
    }

    private func clamped(_ offset: CGFloat) -> CGFloat {
        min(0, max(-revealWidth, offset))
    }

    private func close(updateActiveID: Bool = true) {
        withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
            horizontalOffset = 0
        }
        if updateActiveID, activeID == id {
            activeID = nil
        }
    }
}

enum FitnessScreenContentLayout {
    case lazy
    case eager
}

struct FitnessScreen<Content: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String?
    let subtitle: String?
    let systemImage: String?
    let showsHeader: Bool
    let contentLayout: FitnessScreenContentLayout
    let locksHorizontalScrolling: Bool
    let content: Content

    init(
        title: String? = nil,
        subtitle: String? = nil,
        systemImage: String? = nil,
        showsHeader: Bool = false,
        contentLayout: FitnessScreenContentLayout = .lazy,
        locksHorizontalScrolling: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.showsHeader = showsHeader
        self.contentLayout = contentLayout
        self.locksHorizontalScrolling = locksHorizontalScrolling
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if locksHorizontalScrolling {
            GeometryReader { geometry in
                fitnessScrollView(contentWidth: geometry.size.width)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
        } else {
            fitnessScrollView(contentWidth: nil)
        }
    }

    private func fitnessScrollView(contentWidth: CGFloat?) -> some View {
        ScrollView(.vertical) {
            constrainedScreenContent(contentWidth: contentWidth)
        }
        .scrollDismissesKeyboard(.interactively)
        .submitLabel(.done)
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
    }

    @ViewBuilder
    private func constrainedScreenContent(contentWidth: CGFloat?) -> some View {
        if let contentWidth {
            screenContent
                .frame(
                    width: max(0, contentWidth - (appTheme.metrics.screenPadding * 2)),
                    alignment: .leading
                )
                .clipped()
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, appTheme.metrics.screenBottomPadding)
        } else {
            screenContent
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, appTheme.metrics.screenBottomPadding)
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch contentLayout {
        case .lazy:
            LazyVStack(alignment: .leading, spacing: appTheme.metrics.screenContentSpacing) {
                screenElements
            }
        case .eager:
            VStack(alignment: .leading, spacing: appTheme.metrics.screenContentSpacing) {
                screenElements
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var screenElements: some View {
        if showsHeader, let title {
            FitnessScreenHeader(title: title, subtitle: subtitle, systemImage: systemImage)
        }

        content
    }
}

extension View {
    func peaklineKeyboardDismissal() -> some View {
        scrollDismissesKeyboard(.interactively)
            .submitLabel(.done)
    }
}

struct FitnessInformationalActionCard<Information: View, Action: View>: View {
    private let style: FitnessCardStyle
    private let minimumContentHeight: CGFloat?
    private let information: Information
    private let action: Action

    init(
        style: FitnessCardStyle = .standard,
        minimumContentHeight: CGFloat? = nil,
        @ViewBuilder information: () -> Information,
        @ViewBuilder action: () -> Action
    ) {
        self.style = style
        self.minimumContentHeight = minimumContentHeight
        self.information = information()
        self.action = action()
    }

    var body: some View {
        FitnessCard(style: style) {
            VStack(alignment: .leading, spacing: 14) {
                information

                if let minimumContentHeight {
                    Spacer(minLength: minimumContentHeight)
                }

                action
            }
        }
    }
}

struct PrimaryFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(appTheme.colors.accentForeground)
            .padding(.horizontal, 16)
            .frame(minHeight: appTheme.metrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .background(appTheme.colors.accent, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(appTheme.colors.accentHighlight.opacity(0.24), lineWidth: 0.75)
            }
            .navigationPressFeedback(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion,
                pressedOpacity: 0.88
            )
    }
}

struct SecondaryFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(appTheme.colors.accent)
            .padding(.horizontal, 16)
            .frame(minHeight: appTheme.metrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .background(appTheme.colors.accentSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(appTheme.colors.accent.opacity(0.24), lineWidth: 0.75)
            }
            .navigationPressFeedback(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion,
                pressedOpacity: 0.90
            )
    }
}

struct NeutralFitnessButtonStyle: ButtonStyle {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(appTheme.colors.textPrimary)
            .padding(.horizontal, 16)
            .frame(minHeight: appTheme.metrics.buttonHeight)
            .frame(maxWidth: .infinity)
            .background(appTheme.elevatedCardBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(appTheme.cardBorder.opacity(0.72), lineWidth: 0.75)
            }
            .navigationPressFeedback(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion,
                pressedOpacity: 0.90
            )
    }
}

struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .navigationPressFeedback(
                isPressed: configuration.isPressed,
                reduceMotion: reduceMotion
            )
    }
}

struct FitnessIconBadge: View {
    @Environment(\.appTheme) private var appTheme

    let systemImage: String
    var size: CGFloat = 42
    var tint: Color?
    var background: Color?

    var body: some View {
        let foreground = tint ?? appTheme.colors.accent
        let shape = RoundedRectangle(cornerRadius: max(12, size * 0.30), style: .continuous)

        Image(systemName: systemImage)
            .font(AppTypography.rounded(size: max(17, size * 0.42), weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background ?? badgeBackground(for: foreground), in: shape)
            .overlay {
                shape
                    .stroke(foreground.opacity(0.12), lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }

    private func badgeBackground(for foreground: Color) -> Color {
        tint == nil ? appTheme.colors.accentSurface : foreground.opacity(0.14)
    }
}

enum DashboardActionTileLayout: Equatable {
    case vertical
    case horizontal
}

struct DashboardActionTile: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String
    var status: String?
    var isEnabled = true
    var layout: DashboardActionTileLayout = .vertical
    var showsChevron = true
    var width: CGFloat?
    var minHeight: CGFloat = 128
    var iconSize: CGFloat?

    var body: some View {
        FitnessCard(style: .compact) {
            content
        }
        .frame(width: width)
        .opacity(isEnabled ? 1 : 0.62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(subtitle)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .vertical:
            verticalContent
        case .horizontal:
            horizontalContent
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FitnessIconBadge(
                    systemImage: systemImage,
                    size: iconSize ?? appTheme.metrics.rowIconSize,
                    tint: iconTint,
                    background: iconBackground
                )

                Spacer(minLength: 8)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appTheme.colors.textTertiary)
                }
            }

            titleBlock(titleFont: AppTypography.compactCardTitle, subtitleFont: AppTypography.metadata)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: max(0, minHeight - appTheme.metrics.compactCardPadding * 2),
            alignment: .topLeading
        )
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: 12) {
            FitnessIconBadge(
                systemImage: systemImage,
                size: iconSize ?? 44,
                tint: iconTint,
                background: iconBackground
            )

            titleBlock(titleFont: AppTypography.sectionTitle, subtitleFont: AppTypography.body)

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: isEnabled ? "chevron.right" : "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titleBlock(titleFont: Font, subtitleFont: Font) -> some View {
        VStack(alignment: .leading, spacing: layout == .vertical ? 4 : 5) {
            HStack(spacing: 8) {
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(isEnabled ? appTheme.colors.textPrimary : appTheme.colors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let status {
                    Text(status)
                        .font(AppTypography.badge)
                        .foregroundStyle(isEnabled ? appTheme.colors.accent : appTheme.colors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(statusBackground, in: Capsule())
                        .lineLimit(1)
                }
            }

            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var iconTint: Color {
        isEnabled ? appTheme.colors.accent : appTheme.colors.textTertiary
    }

    private var iconBackground: Color {
        isEnabled ? appTheme.colors.accentSurface : appTheme.colors.cardBackgroundElevated
    }

    private var statusBackground: Color {
        isEnabled ? appTheme.colors.accentSurface : appTheme.colors.cardBackgroundElevated
    }

    private var accessibilityLabel: String {
        if let status, !status.isEmpty {
            return "\(title), \(status)"
        }

        return title
    }
}

extension View {
    func peaklineGroupedContent() -> some View {
        modifier(PeaklineGroupedContentModifier())
    }

    func destructiveSwipeAction(
        _ title: String = "Delete",
        allowsFullSwipe: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
            Button(role: .destructive) {
                AppHaptics.warning()
                action()
            } label: {
                Label(title, systemImage: "trash")
            }
        }
    }
}

private struct PeaklineGroupedContentModifier: ViewModifier {
    @Environment(\.appTheme) private var appTheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(appTheme.colors.backgroundPrimary)
    }
}

struct FilterChip: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        Button {
            AppHaptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.metadataEmphasis)
                }
                Text(title)
                    .font(AppTypography.bodyEmphasis)
            }
            .padding(.horizontal, appTheme.metrics.chipHorizontalPadding)
            .padding(.vertical, appTheme.metrics.chipVerticalPadding)
            .frame(minHeight: appTheme.metrics.minimumHitTarget)
            .foregroundStyle(isSelected ? appTheme.colors.accent : appTheme.colors.textSecondary)
            .background(isSelected ? appTheme.colors.accentSurface : appTheme.cardBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? appTheme.colors.accent.opacity(0.38) : appTheme.cardBorder.opacity(0.72), lineWidth: 0.75)
            }
            .peaklineSelectionMotion(isSelected: isSelected, reduceMotion: reduceMotion, scale: 1.01)
        }
        .buttonStyle(.plain)
    }
}

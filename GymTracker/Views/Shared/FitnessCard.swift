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
    @State private var dragIntent = SwipeDragIntent.undecided

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
            // The action is only mounted once the row has moved, so a closed row
            // cannot expose or hit-test a destructive control.
            if isEnabled, horizontalOffset != 0 {
                action
                    .padding(.trailing, appTheme.metrics.swipeRevealActionTrailingPadding)
                    .opacity(revealProgress)
                    .allowsHitTesting(revealProgress > 0.05)
                    .accessibilityHidden(revealProgress <= 0.05)
                    .transition(.opacity)
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
        .onChange(of: isEnabled) { _, enabled in
            if !enabled { close() }
        }
    }

    private var revealWidth: CGFloat { appTheme.metrics.swipeRevealWidth }

    private var revealProgress: CGFloat {
        min(1, abs(horizontalOffset) / revealWidth)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: SwipeRevealGesturePolicy.minimumTranslation, coordinateSpace: .local)
            .onChanged { value in
                if dragIntent == .undecided {
                    let resolvedIntent = SwipeRevealGesturePolicy.intent(for: value.translation)
                    guard resolvedIntent != .undecided else { return }
                    dragIntent = resolvedIntent
                    guard resolvedIntent == .horizontal else { return }
                    dragStartOffset = horizontalOffset
                    if activeID != id {
                        activeID = id
                    }
                }

                guard dragIntent == .horizontal else { return }
                horizontalOffset = SwipeRevealGesturePolicy.clampedOffset(
                    dragStartOffset + value.translation.width,
                    revealWidth: revealWidth
                )
            }
            .onEnded { value in
                defer {
                    dragIntent = .undecided
                    dragStartOffset = horizontalOffset
                }

                guard dragIntent == .horizontal else { return }
                let shouldOpen = SwipeRevealGesturePolicy.shouldOpen(
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation,
                    dragStartOffset: dragStartOffset,
                    revealWidth: revealWidth
                )

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

    private func close(updateActiveID: Bool = true) {
        withAnimation(AppMotion.swipeRevealSnap(reduceMotion: reduceMotion)) {
            horizontalOffset = 0
        }
        if updateActiveID, activeID == id {
            activeID = nil
        }
    }
}

enum SwipeDragIntent {
    case undecided
    case horizontal
    case vertical
}

/// Deterministic gesture decisions for `SwipeRevealRow`.
///
/// The row keeps one direct offset and commits to a single direction as soon as
/// intent is established, so a diagonal scroll cannot half-open a row and a
/// reverse swipe settles back to the closed state.
enum SwipeRevealGesturePolicy {
    /// Movement below this distance keeps the intent undecided, so a tap or a
    /// scroll start cannot claim the row.
    static let minimumTranslation: CGFloat = 12
    /// Horizontal dominance required before the row claims the gesture, so a
    /// near-diagonal drag stays with the scrolling list instead of half-opening
    /// the row while the list scrolls underneath it.
    static let horizontalDominanceRatio: CGFloat = 1.25
    /// Finger travel that opens the row even without much release velocity.
    static let openDistance: CGFloat = 36
    /// Fraction of the reveal width the projected offset must pass to open.
    static let openProjectedFraction: CGFloat = 0.45

    static func intent(for translation: CGSize) -> SwipeDragIntent {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= minimumTranslation else { return .undecided }
        return horizontal > vertical * horizontalDominanceRatio ? .horizontal : .vertical
    }

    static func clampedOffset(_ offset: CGFloat, revealWidth: CGFloat) -> CGFloat {
        min(0, max(-revealWidth, offset))
    }

    static func shouldOpen(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        dragStartOffset: CGFloat,
        revealWidth: CGFloat
    ) -> Bool {
        let projectedOffset = dragStartOffset + predictedEndTranslation.width
        return projectedOffset < -(revealWidth * openProjectedFraction)
            || translation.width < -openDistance
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
            .foregroundStyle(appTheme.colors.textAccent)
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
                        .font(AppTypography.eyebrow)
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
                    .font(AppTypography.eyebrow)
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
    enum Style {
        case standard
        case prominent
    }

    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let systemImage: String?
    let isSelected: Bool
    let style: Style
    let expandsToFill: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        style: Style = .standard,
        expandsToFill: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.style = style
        self.expandsToFill = expandsToFill
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: style == .prominent
                ? appTheme.metrics.radius12
                : appTheme.metrics.minimumHitTarget / 2,
            style: .continuous
        )

        Button {
            AppHaptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppTypography.metadataEmphasis)
                        .accessibilityHidden(true)
                }
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppTypography.metadataEmphasis)
                }
                Text(title)
                    .font(AppTypography.bodyEmphasis)
            }
            .padding(.horizontal, appTheme.metrics.chipHorizontalPadding)
            .padding(.vertical, appTheme.metrics.chipVerticalPadding)
            .frame(maxWidth: expandsToFill ? .infinity : nil, minHeight: appTheme.metrics.minimumHitTarget)
            .foregroundStyle(selectedForeground)
            .background(selectedBackground, in: shape)
            .overlay {
                shape
                    .stroke(isSelected ? appTheme.colors.accent.opacity(0.38) : appTheme.cardBorder.opacity(0.72), lineWidth: 0.75)
            }
            .peaklineSelectionMotion(isSelected: isSelected, reduceMotion: reduceMotion, scale: 1.01)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedForeground: Color {
        guard isSelected else { return appTheme.colors.textSecondary }
        return style == .prominent ? appTheme.colors.accentForeground : appTheme.colors.accent
    }

    private var selectedBackground: Color {
        guard isSelected else { return appTheme.cardBackground }
        return style == .prominent ? appTheme.colors.accent : appTheme.colors.accentSurface
    }
}

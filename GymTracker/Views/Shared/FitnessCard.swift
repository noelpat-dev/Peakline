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

// MARK: - Summit trail

// These local styles let the Summit trail compile before F1 adds the shared
// AppThemeColors.alpenglow and AppTypography instrument/waypoint tokens.
fileprivate enum SummitTrailPlaceholderTokens {
    static func alpenglow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.612, blue: 0.478)
            : Color(red: 0.824, green: 0.376, blue: 0.243)
    }

    static func instrumentFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight)
            .width(.condensed)
            .monospacedDigit()
    }

    static func waypointFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight)
    }
}

private struct SummitTrailDashLine: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 24, y: 0))
                path.addLine(to: CGPoint(x: 24, y: geometry.size.height))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TrailPage<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SummitTrailDashLine(color: appTheme.colors.textTertiary)
            }
    }
}

struct TrailSection<Content: View>: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12

    let index: Int
    let label: String
    private let content: Content

    init(index: Int, label: String, @ViewBuilder content: () -> Content) {
        self.index = index
        self.label = label
        self.content = content()
    }

    var body: some View {
        let sectionNumber = String(format: "%02d", max(index, 0))

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                Text(sectionNumber)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .monospacedDigit()
                Text(" · \(label.uppercased())")
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
            .font(SummitTrailPlaceholderTokens.waypointFont(size: labelSize))
            .tracking(1.7)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Section \(sectionNumber) · \(label)")
            .accessibilityAddTraits(.isHeader)

            content
        }
        .padding(.leading, 48)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(appTheme.colors.backgroundPrimary)
                .overlay {
                    Circle().stroke(appTheme.colors.textPrimary, lineWidth: 1.6)
                }
                .frame(width: 13, height: 13)
                .offset(x: 17.5, y: 22 + max(0, (labelSize - 13) / 2))
                .accessibilityHidden(true)
        }
    }
}

struct TrailStop<Trailing: View>: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12.5

    let title: String
    let detail: String?
    let done: Bool
    private let trailing: Trailing

    init(
        title: String,
        detail: String? = nil,
        done: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.done = done
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundStyle(done ? appTheme.colors.textTertiary : appTheme.colors.textPrimary)
                    .strikethrough(done, pattern: .solid, color: appTheme.colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: detailSize, weight: .regular))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Circle()
                .fill(done ? appTheme.colors.textPrimary : appTheme.colors.backgroundPrimary)
                .overlay {
                    if !done {
                        Circle().stroke(appTheme.colors.textSecondary, lineWidth: 1.3)
                    }
                }
                .frame(width: 7, height: 7)
                .offset(x: -27.5)
                .accessibilityHidden(true)
        }
    }
}

extension TrailStop where Trailing == EmptyView {
    init(title: String, detail: String? = nil, done: Bool = false) {
        self.init(title: title, detail: detail, done: done) {
            EmptyView()
        }
    }
}

private struct SummitTrailSignShape: Shape {
    func path(in rect: CGRect) -> Path {
        let top: CGFloat = 2
        let bottom = max(top, rect.height - 2)
        let shoulder = max(1, rect.width - 13)
        let tip = max(shoulder, rect.width - 4)
        let middle = rect.midY

        var path = Path()
        path.move(to: CGPoint(x: 1, y: top))
        path.addLine(to: CGPoint(x: shoulder, y: top))
        path.addLine(to: CGPoint(x: tip, y: middle))
        path.addLine(to: CGPoint(x: shoulder, y: bottom))
        path.addLine(to: CGPoint(x: 1, y: bottom))
        path.closeSubpath()
        return path
    }
}

struct TrailSignTag: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .caption) private var textSize: CGFloat = 11.5

    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(SummitTrailPlaceholderTokens.instrumentFont(size: textSize))
            .tracking(0.9)
            .foregroundStyle(appTheme.colors.textPrimary)
            .lineLimit(1)
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .frame(minHeight: 22)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                SummitTrailSignShape()
                    .stroke(appTheme.colors.textPrimary, lineWidth: 1.2)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.uppercased())
    }
}

struct InstrumentGauge: View {
    @Environment(\.appTheme) private var appTheme
    let value: Int

    private var clampedValue: Int { min(max(value, 0), 100) }

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for index in 0..<40 {
                    let height: CGFloat = index.isMultiple(of: 5) ? 16 : 10
                    let x = CGFloat(index) * 6.8 + 0.7
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 16 - height))
                    tick.addLine(to: CGPoint(x: x, y: 16))

                    let isBelowValue = Double(index) * 100 / 40 < Double(clampedValue)
                    context.stroke(
                        tick,
                        with: .color(appTheme.colors.textPrimary.opacity(isBelowValue ? 0.95 : 0.18)),
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
                    )
                }
            }
            .accessibilityHidden(true)
        }
        .frame(width: 266.6, height: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Instrument gauge")
        .accessibilityValue("\(clampedValue) of 100")
    }
}

typealias SummitMilestone = (name: String, metres: Int)

private actor SummitAltimeterIntroGate {
    static let shared = SummitAltimeterIntroGate()
    private var hasPlayed = false

    func claim() -> Bool {
        guard !hasPlayed else { return false }
        hasPlayed = true
        return true
    }
}

private struct SummitTapeTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private func summitTickBase(_ value: Int) -> Int {
    value - value % 100
}

private func summitSaturatingAdd(_ value: Int, _ offset: Int) -> Int {
    let (sum, overflow) = value.addingReportingOverflow(offset)
    guard overflow else { return sum }
    return offset < 0 ? Int.min : Int.max
}

private struct SummitAltitudeTape: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 11

    let reading: Int
    let nextMilestone: SummitMilestone?
    let passedMilestones: [SummitMilestone]

    private let tapeWidth: CGFloat = 266.6
    private let tapeHeight: CGFloat = 66

    private var tickValues: [Int] {
        var seen = Set<Int>()
        return (-8...8).compactMap { offset in
            let value = summitSaturatingAdd(summitTickBase(reading), offset * 100)
            let distance = abs(Double(value) - Double(reading))
            guard distance <= 700, seen.insert(value).inserted else { return nil }
            return value
        }
    }

    private var visibleMilestones: [SummitMilestone] {
        let candidates = passedMilestones + (nextMilestone.map { [$0] } ?? [])
        return candidates.filter { abs(Double($0.metres) - Double(reading)) <= 700 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                for tickValue in tickValues {
                    let delta = Double(tickValue) - Double(reading)
                    let x = size.width / 2 + CGFloat(delta * 0.19)
                    let height: CGFloat = tickValue.isMultiple(of: 500) ? 20 : 10
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 15))
                    tick.addLine(to: CGPoint(x: x, y: 15 + height))
                    context.stroke(
                        tick,
                        with: .color(appTheme.colors.textTertiary.opacity(tickValue <= reading ? 0.9 : 0.3)),
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                }
            }
            .accessibilityHidden(true)

            ForEach(Array(tickValues.enumerated()), id: \.offset) { element in
                let tickValue = element.element
                if tickValue.isMultiple(of: 500) {
                    Text(tickValue.formatted())
                        .font(SummitTrailPlaceholderTokens.instrumentFont(size: labelSize, weight: .medium))
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(width: 58)
                        .position(
                            x: clampedLabelPosition(for: tickValue),
                            y: 55
                        )
                        .accessibilityHidden(true)
                }
            }

            ForEach(Array(visibleMilestones.enumerated()), id: \.offset) { element in
                let milestone = element.element
                let isPassed = passedMilestones.contains {
                    $0.name == milestone.name && $0.metres == milestone.metres
                }
                SummitTapeTriangle()
                    .fill(isPassed ? SummitTrailPlaceholderTokens.alpenglow(for: colorScheme) : .clear)
                    .overlay {
                        SummitTapeTriangle()
                            .stroke(
                                isPassed ? SummitTrailPlaceholderTokens.alpenglow(for: colorScheme) : appTheme.colors.textSecondary,
                                lineWidth: 1
                            )
                    }
                    .frame(width: 7, height: 6)
                    .position(x: markerPosition(for: milestone.metres), y: 43)
                    .accessibilityHidden(true)
            }

            SummitTapeTriangle()
                .fill(appTheme.colors.textPrimary)
                .frame(width: 10, height: 7)
                .rotationEffect(.degrees(180))
                .position(x: tapeWidth / 2, y: 4)
                .accessibilityHidden(true)
        }
        .frame(width: tapeWidth, height: tapeHeight)
        .clipped()
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func markerPosition(for metres: Int) -> CGFloat {
        tapeWidth / 2 + CGFloat((Double(metres) - Double(reading)) * 0.19)
    }

    private func clampedLabelPosition(for metres: Int) -> CGFloat {
        min(max(markerPosition(for: metres), 30), tapeWidth - 30)
    }
}

struct AltimeterView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var unitSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var gainSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 10.5

    let metres: Int
    let gainedToday: Int?
    let nextMilestone: SummitMilestone?
    let passedMilestones: [SummitMilestone]
    let animatesIntro: Bool

    @State private var displayedMetres: Int

    init(
        metres: Int,
        gainedToday: Int?,
        nextMilestone: SummitMilestone?,
        passedMilestones: [SummitMilestone],
        animatesIntro: Bool
    ) {
        self.metres = metres
        self.gainedToday = gainedToday
        self.nextMilestone = nextMilestone
        self.passedMilestones = passedMilestones
        self.animatesIntro = animatesIntro
        _displayedMetres = State(initialValue: metres)
    }

    private var animationKey: String {
        "\(metres)-\(animatesIntro)-\(reduceMotion)"
    }

    private var caption: String {
        guard let nextMilestone else { return "CURRENT ALTITUDE" }
        return "NEXT · \(nextMilestone.name.uppercased()) · \(nextMilestone.metres.formatted()) M"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayedMetres.formatted())
                        .font(SummitTrailPlaceholderTokens.instrumentFont(size: heroSize))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)

                    Text("M")
                        .font(SummitTrailPlaceholderTokens.instrumentFont(size: unitSize))
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                if let gainedToday {
                    HStack(spacing: 4) {
                        SummitTapeTriangle()
                            .fill(SummitTrailPlaceholderTokens.alpenglow(for: colorScheme))
                            .frame(width: 7, height: 6)
                            .accessibilityHidden(true)
                        Text("+\(max(0, gainedToday).formatted()) TODAY")
                            .font(SummitTrailPlaceholderTokens.instrumentFont(size: gainSize))
                            .tracking(0.8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                    }
                    .foregroundStyle(SummitTrailPlaceholderTokens.alpenglow(for: colorScheme))
                    .accessibilityLabel("Plus \(max(0, gainedToday).formatted()) metres today")
                }
            }

            SummitAltitudeTape(
                reading: displayedMetres,
                nextMilestone: nextMilestone,
                passedMilestones: passedMilestones
            )

            Text(caption)
                .font(SummitTrailPlaceholderTokens.waypointFont(size: captionSize))
                .tracking(0.9)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .task(id: animationKey) {
            guard animatesIntro else {
                displayedMetres = metres
                return
            }

            let ownsIntroAnimation = await SummitAltimeterIntroGate.shared.claim()
            guard ownsIntroAnimation else {
                displayedMetres = metres
                return
            }
            guard !reduceMotion else {
                displayedMetres = metres
                return
            }
            guard !Task.isCancelled else { return }

            displayedMetres = 0
            let start = 0

            do {
                try await Task.sleep(nanoseconds: 1_300_000_000)
            } catch {
                return
            }

            let stepCount = 28
            for step in 1...stepCount {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                let progress = Double(step) / Double(stepCount)
                let easedProgress = 1 - pow(1 - progress, 3)
                displayedMetres = interpolatedAltitude(from: start, to: metres, progress: easedProgress)
            }
        }
    }

    private func interpolatedAltitude(from start: Int, to end: Int, progress: Double) -> Int {
        let interpolated = Double(start) + (Double(end) - Double(start)) * progress
        if interpolated >= Double(Int.max) { return Int.max }
        if interpolated <= Double(Int.min) { return Int.min }
        return Int(interpolated.rounded())
    }
}

struct CairnView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.colorScheme) private var colorScheme

    let stones: Int
    let newestIsFresh: Bool

    private var displayedStoneCount: Int { min(max(stones, 0), 8) }

    var body: some View {
        ZStack {
            Canvas { context, _ in
                if displayedStoneCount == 0 {
                    let placeholder = Path(ellipseIn: CGRect(x: 15, y: 42, width: 30, height: 8))
                    context.stroke(
                        placeholder,
                        with: .color(appTheme.colors.textTertiary),
                        style: StrokeStyle(lineWidth: 1.3, dash: [3, 3])
                    )
                } else {
                    let verticalAdjustment = CGFloat(max(0, displayedStoneCount - 7) * 7)
                    for index in 0..<displayedStoneCount {
                        let width = max(3, 30 - 3.6 * CGFloat(index))
                        let centerY = 46 - 7 * CGFloat(index) + verticalAdjustment
                        let stone = Path(ellipseIn: CGRect(x: 30 - width / 2, y: centerY - 4, width: width, height: 8))
                        let isNewest = index == displayedStoneCount - 1
                        let color = isNewest && newestIsFresh
                            ? SummitTrailPlaceholderTokens.alpenglow(for: colorScheme)
                            : appTheme.colors.textPrimary
                        context.stroke(stone, with: .color(color), lineWidth: 1.3)
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .frame(width: 60, height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            stones <= 0
                ? "Cairn, no stones"
                : "Cairn, \(stones.formatted()) stones\(newestIsFresh ? ", newest stone is fresh" : "")"
        )
    }
}

struct SummitPrimaryButton: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.system(.body, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(appTheme.colors.backgroundPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(appTheme.colors.textPrimary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CampSuppliesRow: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .body) private var valueSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 10.5
    @ScaledMetric(relativeTo: .caption) private var logSize: CGFloat = 11

    let items: [(symbol: String, caption: String, value: String?)]
    let onTap: (Int) -> Void

    init(
        items: [(symbol: String, caption: String, value: String?)],
        onTap: @escaping (Int) -> Void = { _ in }
    ) {
        self.items = items
        self.onTap = onTap
    }

    var body: some View {
        if items.isEmpty {
            Text("NO SUPPLIES LOGGED")
                .font(SummitTrailPlaceholderTokens.waypointFont(size: captionSize))
                .tracking(0.9)
                .foregroundStyle(appTheme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { element in
                    let index = element.offset
                    let item = element.element
                    if index > 0 {
                        Rectangle()
                            .fill(appTheme.colors.textTertiary.opacity(0.72))
                            .frame(width: 0.5, height: 44)
                            .accessibilityHidden(true)
                    }

                    Button {
                        onTap(index)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 20, weight: .regular))
                                .accessibilityHidden(true)

                            if let value = item.value, !value.isEmpty {
                                Text(value)
                                    .font(SummitTrailPlaceholderTokens.instrumentFont(size: valueSize))
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            } else {
                                Text("+ LOG")
                                    .font(SummitTrailPlaceholderTokens.instrumentFont(size: logSize))
                                    .tracking(0.6)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .lineLimit(1)
                            }

                            Text(item.caption.uppercased())
                                .font(SummitTrailPlaceholderTokens.waypointFont(size: captionSize))
                                .tracking(0.9)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        item.value.flatMap { $0.isEmpty ? nil : $0 }.map { "\(item.caption), \($0)" }
                            ?? "\(item.caption), no log"
                    )
                    .accessibilityHint(item.value?.isEmpty != false ? "Add a log" : "")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SummitTrailPreviewHost<Content: View>: View {
    let colorScheme: ColorScheme
    let dynamicTypeSize: DynamicTypeSize
    private let content: Content

    init(
        colorScheme: ColorScheme = .light,
        dynamicTypeSize: DynamicTypeSize = .large,
        @ViewBuilder content: () -> Content
    ) {
        self.colorScheme = colorScheme
        self.dynamicTypeSize = dynamicTypeSize
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.black.colors.backgroundPrimary.ignoresSafeArea())
            .environment(\.appTheme, .black)
            .environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
    }
}

#Preview("TrailPage · Light") {
    SummitTrailPreviewHost {
        TrailPage {
            VStack(alignment: .leading, spacing: 0) {
                TrailSection(index: 1, label: "Approach") {
                    TrailStop(title: "Warm up", detail: "Easy pace along the ridge", done: true)
                    TrailStop(title: "Hill repeats", detail: "Six climbs at a steady effort") {
                        TrailSignTag(text: "PR attempt")
                    }
                }
                TrailSection(index: 2, label: "Camp") {
                    TrailStop(title: "Refill water", detail: "Before the final ascent")
                }
            }
        }
    }
}

#Preview("TrailPage · Dark · Empty") {
    SummitTrailPreviewHost(colorScheme: .dark) {
        TrailPage { Color.clear.frame(height: 180) }
    }
}

#Preview("TrailPage · Accessibility") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) {
        TrailPage {
            VStack(alignment: .leading, spacing: 0) {
                TrailSection(index: 98, label: "A long approach through exposed terrain") {
                    TrailStop(title: "Follow the marked route to the upper camp", detail: "Keep a steady pace and take water before the final climb.")
                }
                TrailSection(index: 99, label: "High camp") {
                    TrailStop(title: "Prepare for the summit")
                }
            }
        }
    }
}

#Preview("TrailSection · Light") {
    SummitTrailPreviewHost {
        TrailSection(index: 2, label: "Today's route") {
            TrailStop(title: "Warm up", detail: "A steady approach")
            TrailStop(title: "Main climb", detail: "Five rounds", done: true)
        }
    }
}

#Preview("TrailSection · Dark · Empty") {
    SummitTrailPreviewHost(colorScheme: .dark) {
        TrailSection(index: 0, label: "No route") { EmptyView() }
    }
}

#Preview("TrailSection · Accessibility") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) {
        TrailSection(index: 100, label: "A very long waypoint label that wraps across multiple lines") {
            TrailStop(title: "No stops have been added yet")
        }
    }
}

#Preview("TrailStop · Light") {
    SummitTrailPreviewHost {
        TrailPage {
            TrailSection(index: 1, label: "Route") {
                VStack(alignment: .leading, spacing: 4) {
                    TrailStop(title: "Warm up", detail: "Easy pace", done: true)
                    TrailStop(title: "Heavy carries", detail: "Three trips") {
                        TrailSignTag(text: "Deload")
                    }
                }
            }
        }
    }
}

#Preview("TrailStop · Dark · Empty") {
    SummitTrailPreviewHost(colorScheme: .dark) {
        TrailPage {
            TrailSection(index: 1, label: "No stops") {
                TrailStop(title: "", detail: nil)
            }
        }
    }
}

#Preview("TrailStop · Accessibility · Extreme") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) {
        TrailPage {
            TrailSection(index: 99, label: "High camp") {
                TrailStop(
                    title: "Complete the longest possible route to the highest marked camp before the weather changes",
                    detail: "This detail is intentionally long to verify wrapping and Dynamic Type behavior across the entire row."
                )
            }
        }
    }
}

#Preview("TrailSignTag · Light · Empty") {
    SummitTrailPreviewHost { TrailSignTag(text: "") }
}

#Preview("TrailSignTag · Dark · Extreme") {
    SummitTrailPreviewHost(colorScheme: .dark) {
        TrailSignTag(text: "REST AFTER THE FINAL SUMMIT ATTEMPT")
    }
}

#Preview("TrailSignTag · Accessibility") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) {
        TrailSignTag(text: "PR attempt")
    }
}

#Preview("InstrumentGauge · Light · Empty") {
    SummitTrailPreviewHost { InstrumentGauge(value: 0) }
}

#Preview("InstrumentGauge · Dark · Extreme") {
    SummitTrailPreviewHost(colorScheme: .dark) { InstrumentGauge(value: 100) }
}

#Preview("InstrumentGauge · Accessibility · Clamped") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) { InstrumentGauge(value: 120) }
}

#Preview("AltimeterView · Light · Empty") {
    SummitTrailPreviewHost {
        AltimeterView(
            metres: 0,
            gainedToday: nil,
            nextMilestone: nil,
            passedMilestones: [],
            animatesIntro: false
        )
    }
}

#Preview("AltimeterView · Dark · Extreme") {
    SummitTrailPreviewHost(colorScheme: .dark) {
        AltimeterView(
            metres: Int.max,
            gainedToday: Int.max,
            nextMilestone: ("Beyond the map", Int.max),
            passedMilestones: [("Sea level", Int.min), ("Upper ridge", Int.max - 10)],
            animatesIntro: true
        )
    }
}

#Preview("AltimeterView · Accessibility") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) {
        AltimeterView(
            metres: 8_848,
            gainedToday: 1_200,
            nextMilestone: ("High camp", 9_000),
            passedMilestones: [("Base camp", 5_364), ("South col", 7_906)],
            animatesIntro: false
        )
    }
}

#Preview("CairnView · Light · Empty") {
    SummitTrailPreviewHost { CairnView(stones: 0, newestIsFresh: false) }
}

#Preview("CairnView · Dark · Extreme") {
    SummitTrailPreviewHost(colorScheme: .dark) { CairnView(stones: Int.max, newestIsFresh: true) }
}

#Preview("CairnView · Accessibility") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) { CairnView(stones: 8, newestIsFresh: true) }
}

#Preview("SummitPrimaryButton · Light · Empty") {
    SummitTrailPreviewHost { SummitPrimaryButton(title: "") {} }
}

#Preview("SummitPrimaryButton · Dark · Extreme") {
    SummitTrailPreviewHost(colorScheme: .dark) {
        SummitPrimaryButton(title: "Continue along the exposed upper ridge to the highest camp") {}
    }
}

#Preview("SummitPrimaryButton · Accessibility") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) {
        SummitPrimaryButton(title: "Start workout") {}
    }
}

#Preview("CampSuppliesRow · Light · Empty") {
    SummitTrailPreviewHost { CampSuppliesRow(items: []) }
}

#Preview("CampSuppliesRow · Dark · Extreme") {
    SummitTrailPreviewHost(colorScheme: .dark) {
        CampSuppliesRow(items: [
            ("tent", "Sleep", "24 h"),
            ("waterbottle", "Water for the entire expedition", nil),
            ("flame", "Fuel", "999,999 kcal")
        ]) { _ in }
    }
}

#Preview("CampSuppliesRow · Accessibility") {
    SummitTrailPreviewHost(dynamicTypeSize: .accessibility3) {
        CampSuppliesRow(items: [
            ("tent", "Sleep", nil),
            ("waterbottle", "Water", "2 L"),
            ("flame", "Fuel", "3 meals")
        ]) { _ in }
    }
}

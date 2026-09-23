import SwiftUI

struct ProgressArcView: View {
    @Environment(\.appTheme) private var appTheme

    let value: Double
    let label: String
    let caption: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(appTheme.elevatedCardBackground, lineWidth: 12)

            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(appTheme.colors.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(AppTypography.cardTitle)
                Text(label)
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(appTheme.mutedText)
                if let caption {
                    Text(caption)
                        .font(AppTypography.badge)
                        .foregroundStyle(appTheme.mutedText)
                }
            }
        }
        .frame(width: 118, height: 118)
        .accessibilityElement(children: .combine)
    }
}

struct AttendanceRingView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double
    let label: String
    let caption: String?
    let generation: String
    @Binding var revealedGeneration: String?

    @State private var animatedValue = 0.0
    @State private var revealTask: Task<Void, Never>?

    init(
        value: Double,
        label: String,
        caption: String?,
        generation: String,
        revealedGeneration: Binding<String?>
    ) {
        self.value = value
        self.label = label
        self.caption = caption
        self.generation = generation
        _revealedGeneration = revealedGeneration
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(appTheme.elevatedCardBackground, lineWidth: 10)

            Circle()
                .trim(from: 0, to: displayedArcValue)
                .stroke(appTheme.colors.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(Int((min(max(value, 0), 1) * 100).rounded()))%")
                    .font(AppTypography.cardTitle.monospacedDigit())
                Text(label)
                    .font(AppTypography.badge)
                    .foregroundStyle(appTheme.mutedText)
                if let caption {
                    Text(caption)
                        .font(AppTypography.badge)
                        .foregroundStyle(appTheme.mutedText)
                }
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .onAppear {
            revealIfNeeded()
        }
        .onChange(of: generation) { _, _ in
            revealIfNeeded()
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private var displayedArcValue: Double {
        let finalValue = min(max(value, 0), 1)
        return reduceMotion || revealedGeneration == generation ? finalValue : min(max(animatedValue, 0), 1)
    }

    private var accessibilityValue: String {
        let percentage = Int((min(max(value, 0), 1) * 100).rounded())
        if let caption, !caption.isEmpty {
            return "\(percentage) percent, \(caption)"
        }
        return "\(percentage) percent"
    }

    private func revealIfNeeded() {
        guard revealedGeneration != generation else { return }
        let finalValue = min(max(value, 0), 1)
        guard !reduceMotion else { return }

        revealTask?.cancel()
        animatedValue = 0
        revealTask = Task { @MainActor in
            // Let the root tab's stable-frame turn complete before the chart
            // starts drawing. This keeps motion from owning route readiness.
            await Task.yield()
            await Task.yield()
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.attendanceRing(reduceMotion: false)) {
                revealedGeneration = generation
                animatedValue = finalValue
            }
            revealTask = nil
        }
    }
}

// MARK: - Summit horizon

fileprivate let summitAlpenglow = Color(red: 1, green: 0.61, blue: 0.48)

enum SummitCondition: CaseIterable, Hashable {
    case clear
    case changeable
    case storm

    var accessibilityName: String {
        switch self {
        case .clear: "clear skies"
        case .changeable: "changeable skies"
        case .storm: "stormy skies"
        }
    }
}

enum SummitTimeOfDay: CaseIterable, Hashable {
    case dawn
    case day
    case night

    init(date: Date) {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5...8: self = .dawn
        case 9...18: self = .day
        default: self = .night
        }
    }

    var accessibilityName: String {
        switch self {
        case .dawn: "dawn"
        case .day: "day"
        case .night: "night"
        }
    }
}

struct SummitHorizonView: View {
    private static let canvasWidth: CGFloat = 332
    private static let canvasHeight: CGFloat = 268
    private static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    private static let backRidgePoints: [CGPoint] = [
        CGPoint(x: 0, y: 168), CGPoint(x: 30, y: 150), CGPoint(x: 65, y: 158),
        CGPoint(x: 100, y: 128), CGPoint(x: 135, y: 142), CGPoint(x: 170, y: 118),
        CGPoint(x: 205, y: 134), CGPoint(x: 240, y: 112), CGPoint(x: 275, y: 126),
        CGPoint(x: 305, y: 110), CGPoint(x: 332, y: 122)
    ]
    private static let middleRidgePoints: [CGPoint] = [
        CGPoint(x: 0, y: 196), CGPoint(x: 40, y: 178), CGPoint(x: 70, y: 186),
        CGPoint(x: 110, y: 158), CGPoint(x: 150, y: 172), CGPoint(x: 190, y: 150),
        CGPoint(x: 215, y: 160), CGPoint(x: 250, y: 138), CGPoint(x: 285, y: 158),
        CGPoint(x: 332, y: 146)
    ]
    private static let nightStars: [SummitStar] = {
        var state: UInt64 = 11
        func nextValue() -> Double {
            state = (state * 16_807) % 2_147_483_647
            return Double(state) / 2_147_483_647
        }

        return (0..<26).map { _ in
            let x = nextValue() * 332
            let y = 14 + nextValue() * 120
            let brightness = nextValue()
            return SummitStar(
                point: CGPoint(x: x, y: y),
                radius: brightness > 0.8 ? 1.3 : 0.8,
                opacity: 0.25 + brightness * 0.5
            )
        }
    }()

    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let week: [Double]
    let todayIndex: Int
    let prDayIndex: Int?
    let condition: SummitCondition
    let timeOfDay: SummitTimeOfDay
    let isEmpty: Bool
    let animatesIntro: Bool

    @State private var backRidgeProgress = 0.0
    @State private var middleRidgeProgress = 0.0
    @State private var frontRidgeProgress = 0.0
    @State private var skyOpacity = 0.0
    @State private var prFlagScale = 0.0
    @State private var introConfigured = false

    var body: some View {
        ZStack {
            Canvas { context, size in
                var drawingContext = context
                drawingContext.scaleBy(
                    x: size.width / Self.canvasWidth,
                    y: size.height / Self.canvasHeight
                )

                let bounds = Path(CGRect(x: 0, y: 0, width: Self.canvasWidth, height: Self.canvasHeight))
                drawingContext.fill(bounds, with: .color(appTheme.colors.backgroundPrimary))

                Self.drawSky(
                    in: drawingContext,
                    condition: condition,
                    timeOfDay: timeOfDay,
                    background: appTheme.colors.backgroundPrimary,
                    foreground: appTheme.colors.textPrimary,
                    opacity: displayedSkyOpacity
                )

                Self.drawRidge(
                    points: Self.backRidgePoints,
                    progress: displayedBackRidgeProgress,
                    lineWidth: 1,
                    color: appTheme.colors.textPrimary.opacity(0.22),
                    background: appTheme.colors.backgroundPrimary,
                    in: drawingContext
                )
                Self.drawRidge(
                    points: Self.middleRidgePoints,
                    progress: displayedMiddleRidgeProgress,
                    lineWidth: 1.2,
                    color: appTheme.colors.textPrimary.opacity(0.45),
                    background: appTheme.colors.backgroundPrimary,
                    in: drawingContext
                )

                let frontPoints = Self.frontRidgePoints(for: normalizedWeek)
                Self.drawRidge(
                    points: frontPoints,
                    progress: displayedFrontRidgeProgress,
                    lineWidth: 2,
                    color: isEmpty ? appTheme.colors.textTertiary : appTheme.colors.textPrimary,
                    background: appTheme.colors.backgroundPrimary,
                    in: drawingContext
                )
                Self.drawWeekLabels(
                    in: drawingContext,
                    todayIndex: clampedTodayIndex,
                    textPrimary: appTheme.colors.textPrimary,
                    textTertiary: appTheme.colors.textTertiary
                )

                if !isEmpty, let prDayIndex, (0..<7).contains(prDayIndex) {
                    let flagContext = Self.context(
                        drawingContext,
                        scaledFrom: CGPoint(x: Self.columnCenter(prDayIndex), y: Self.peakY(for: normalizedWeek[prDayIndex])),
                        scale: displayedPRFlagScale
                    )
                    Self.drawFlag(
                        in: flagContext,
                        peak: CGPoint(x: Self.columnCenter(prDayIndex), y: Self.peakY(for: normalizedWeek[prDayIndex]))
                    )
                }
            }
            .accessibilityHidden(true)
        }
        .aspectRatio(Self.canvasWidth / Self.canvasHeight, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .onAppear(perform: configureIntro)
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled {
                finishIntroWithoutAnimation()
            }
        }
    }

    private var normalizedWeek: [Double] {
        let values = week.prefix(7).map { value in
            value.isFinite ? min(max(value, 0), 1) : 0
        }
        return values + Array(repeating: 0, count: max(0, 7 - values.count))
    }

    private var clampedTodayIndex: Int {
        min(max(todayIndex, 0), 6)
    }

    private var displayedBackRidgeProgress: Double {
        animatesIntro && !reduceMotion ? backRidgeProgress : 1
    }

    private var displayedMiddleRidgeProgress: Double {
        animatesIntro && !reduceMotion ? middleRidgeProgress : 1
    }

    private var displayedFrontRidgeProgress: Double {
        animatesIntro && !reduceMotion ? frontRidgeProgress : 1
    }

    private var displayedSkyOpacity: Double {
        animatesIntro && !reduceMotion ? skyOpacity : 1
    }

    private var displayedPRFlagScale: CGFloat {
        animatesIntro && !reduceMotion ? CGFloat(prFlagScale) : 1
    }

    private var accessibilitySummary: String {
        let loads = zip(Self.dayLetters, normalizedWeek).enumerated().map { index, item in
            let day = index == clampedTodayIndex ? "today, \(item.0)" : item.0
            return "\(day) \(Int((item.1 * 100).rounded())) percent"
        }.joined(separator: ", ")
        let training = isEmpty ? "no training recorded this week" : "weekly training load, \(loads)"
        let record: String
        if !isEmpty, let prDayIndex, (0..<7).contains(prDayIndex) {
            record = ", personal record on \(Self.dayLetters[prDayIndex])"
        } else {
            record = ""
        }
        return "Summit conditions, \(condition.accessibilityName), \(timeOfDay.accessibilityName), \(training)\(record)"
    }

    @MainActor
    private func configureIntro() {
        guard !introConfigured else { return }
        introConfigured = true

        guard animatesIntro, SummitHorizonIntroPlayback.claimFirstPresentation(), !reduceMotion else {
            finishIntroWithoutAnimation()
            return
        }

        withAnimation(.easeInOut(duration: 1.4).delay(0.1)) {
            backRidgeProgress = 1
        }
        withAnimation(.easeInOut(duration: 1.4).delay(0.25)) {
            middleRidgeProgress = 1
        }
        withAnimation(.easeInOut(duration: 1.4).delay(0.45)) {
            frontRidgeProgress = 1
        }
        withAnimation(.easeInOut(duration: 0.5).delay(0.45)) {
            skyOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(1.7)) {
            prFlagScale = 1
        }
    }

    @MainActor
    private func finishIntroWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            backRidgeProgress = 1
            middleRidgeProgress = 1
            frontRidgeProgress = 1
            skyOpacity = 1
            prFlagScale = 1
        }
    }

    private static func frontRidgePoints(for loads: [Double]) -> [CGPoint] {
        let baseline: CGFloat = 236
        let columnWidth = (canvasWidth - 24) / 7
        var points = [CGPoint(x: 0, y: baseline)]
        for index in 0..<7 {
            let center = columnCenter(index)
            let load = CGFloat(loads[index])
            points.append(CGPoint(x: center - 0.46 * columnWidth, y: baseline - 2 - (index.isMultiple(of: 2) ? 0 : 6 * load)))
            points.append(CGPoint(x: center - 0.12 * columnWidth, y: baseline - 38 * load))
            points.append(CGPoint(x: center, y: baseline - 52 * load))
            points.append(CGPoint(x: center + 0.16 * columnWidth, y: baseline - 40 * load))
            points.append(CGPoint(x: center + 0.46 * columnWidth, y: baseline - 4 * load))
        }
        points.append(CGPoint(x: canvasWidth, y: baseline))
        return points
    }

    private static func columnCenter(_ index: Int) -> CGFloat {
        let columnWidth = (canvasWidth - 24) / 7
        return 12 + columnWidth * CGFloat(index) + columnWidth / 2
    }

    private static func peakY(for load: Double) -> CGFloat {
        236 - 52 * CGFloat(load)
    }

    private static func drawRidge(
        points: [CGPoint],
        progress: Double,
        lineWidth: CGFloat,
        color: Color,
        background: Color,
        in context: GraphicsContext
    ) {
        guard let firstPoint = points.first, let lastPoint = points.last else { return }
        let line = polyline(points)
        var filledArea = line
        filledArea.addLine(to: CGPoint(x: lastPoint.x, y: canvasHeight))
        filledArea.addLine(to: CGPoint(x: firstPoint.x, y: canvasHeight))
        filledArea.closeSubpath()
        context.fill(filledArea, with: .color(background))

        context.stroke(
            line.trimmedPath(from: 0, to: CGFloat(progress)),
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private static func drawWeekLabels(
        in context: GraphicsContext,
        todayIndex: Int,
        textPrimary: Color,
        textTertiary: Color
    ) {
        for index in 0..<7 {
            let center = columnCenter(index)
            let color = index == todayIndex ? textPrimary : textTertiary
            if index == todayIndex {
                var tick = Path()
                tick.move(to: CGPoint(x: center, y: 241))
                tick.addLine(to: CGPoint(x: center, y: 246))
                context.stroke(tick, with: .color(textPrimary), lineWidth: 1)
            }
            context.draw(
                Text(dayLetters[index])
                    .font(AppTypography.metadataEmphasis.monospacedDigit())
                    .foregroundColor(color),
                at: CGPoint(x: center, y: 258),
                anchor: .center
            )
        }
    }

    private static func drawSky(
        in context: GraphicsContext,
        condition: SummitCondition,
        timeOfDay: SummitTimeOfDay,
        background: Color,
        foreground: Color,
        opacity: Double
    ) {
        guard opacity > 0 else { return }
        switch condition {
        case .clear:
            switch timeOfDay {
            case .day:
                drawSun(center: CGPoint(x: 262, y: 74), radius: 15, color: foreground, opacity: opacity, in: context)
            case .dawn:
                let center = CGPoint(x: 232, y: 136)
                context.stroke(
                    circle(center: center, radius: 22),
                    with: .color(summitAlpenglow.opacity(0.72 * opacity)),
                    lineWidth: 1.4
                )
                for index in 0..<3 {
                    let y = CGFloat(124 + index * 7)
                    var line = Path()
                    line.move(to: CGPoint(x: 194, y: y))
                    line.addLine(to: CGPoint(x: 209, y: y - 4))
                    context.stroke(line, with: .color(summitAlpenglow.opacity(0.36 * opacity)), lineWidth: 1)
                }
            case .night:
                drawStars(in: context, color: foreground, opacity: opacity)
                let moonCenter = CGPoint(x: 262, y: 58)
                context.fill(circle(center: moonCenter, radius: 18), with: .color(foreground.opacity(0.78 * opacity)))
                context.fill(
                    circle(center: CGPoint(x: 271, y: 52), radius: 18),
                    with: .color(background)
                )
            }
        case .changeable:
            drawCloud(origin: CGPoint(x: 214, y: 80), scale: 1.1, background: background, foreground: foreground, opacity: opacity, in: context)
            drawCloud(origin: CGPoint(x: 150, y: 110), scale: 0.8, background: background, foreground: foreground, opacity: opacity, in: context)
            if timeOfDay == .day {
                context.stroke(
                    circle(center: CGPoint(x: 276, y: 60), radius: 11),
                    with: .color(foreground.opacity(0.7 * opacity)),
                    lineWidth: 1.2
                )
            }
        case .storm:
            drawStorm(in: context, background: background, foreground: foreground, opacity: opacity)
        }
    }

    private static func drawSun(
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        opacity: Double,
        in context: GraphicsContext
    ) {
        context.stroke(circle(center: center, radius: radius), with: .color(color.opacity(opacity)), lineWidth: 1.4)
        for ray in 0..<8 {
            let angle = CGFloat(ray) * .pi / 4
            let inner = radius + 6
            let outer = radius + 12
            var path = Path()
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
            )
        }
    }

    private static func drawStars(in context: GraphicsContext, color: Color, opacity: Double) {
        for star in nightStars {
            context.fill(
                circle(center: star.point, radius: star.radius),
                with: .color(color.opacity(star.opacity * opacity))
            )
        }
    }

    private static func drawCloud(
        origin: CGPoint,
        scale: CGFloat,
        background: Color,
        foreground: Color,
        opacity: Double,
        in context: GraphicsContext
    ) {
        let cloud = cloudPath(origin: origin, scale: scale)
        context.fill(cloud, with: .color(background))
        context.stroke(cloud, with: .color(foreground.opacity(0.65 * opacity)), lineWidth: 1.3)
    }

    private static func drawStorm(
        in context: GraphicsContext,
        background: Color,
        foreground: Color,
        opacity: Double
    ) {
        for row in 0..<2 {
            let y = CGFloat(112 + row * 15)
            for index in 0..<11 {
                let x = CGFloat(150 + index * 16)
                var rain = Path()
                rain.move(to: CGPoint(x: x, y: y))
                rain.addLine(to: CGPoint(x: x - 6, y: y + 12))
                context.stroke(rain, with: .color(foreground.opacity(0.45 * opacity)), lineWidth: 1)
            }
        }

        drawCloud(origin: CGPoint(x: 170, y: 84), scale: 1.5, background: background, foreground: foreground, opacity: opacity, in: context)
        drawCloud(origin: CGPoint(x: 238, y: 70), scale: 1.2, background: background, foreground: foreground, opacity: opacity, in: context)

        var lightning = Path()
        lightning.move(to: CGPoint(x: 226, y: 96))
        lightning.addLine(to: CGPoint(x: 218, y: 112))
        lightning.addLine(to: CGPoint(x: 226, y: 112))
        lightning.addLine(to: CGPoint(x: 216, y: 130))
        context.stroke(lightning, with: .color(foreground.opacity(opacity)), lineWidth: 1.4)
    }

    private static func cloudPath(origin: CGPoint, scale: CGFloat) -> Path {
        let x = origin.x
        let y = origin.y
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: x + dx * scale, y: y + dy * scale)
        }

        var path = Path()
        path.move(to: point(2, 22))
        path.addQuadCurve(to: point(5, 9), control: point(-1, 15))
        path.addQuadCurve(to: point(17, 6), control: point(7, 1))
        path.addQuadCurve(to: point(31, 6), control: point(25, 0))
        path.addQuadCurve(to: point(45, 15), control: point(43, 4))
        path.addQuadCurve(to: point(43, 23), control: point(50, 18))
        path.addLine(to: point(2, 23))
        path.closeSubpath()
        return path
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private static func context(_ context: GraphicsContext, scaledFrom point: CGPoint, scale: CGFloat) -> GraphicsContext {
        var result = context
        result.translateBy(x: point.x, y: point.y)
        result.scaleBy(x: scale, y: scale)
        result.translateBy(x: -point.x, y: -point.y)
        return result
    }

    private static func drawFlag(in context: GraphicsContext, peak: CGPoint) {
        let top = peak.y - 16
        var pole = Path()
        pole.move(to: CGPoint(x: peak.x, y: peak.y))
        pole.addLine(to: CGPoint(x: peak.x, y: top))
        context.stroke(pole, with: .color(summitAlpenglow), lineWidth: 1.5)

        var pennant = Path()
        pennant.move(to: CGPoint(x: peak.x, y: top))
        pennant.addLine(to: CGPoint(x: peak.x + 10, y: top + 3.5))
        pennant.addLine(to: CGPoint(x: peak.x, y: top + 7))
        pennant.closeSubpath()
        context.fill(pennant, with: .color(summitAlpenglow))
    }
}

@MainActor
private enum SummitHorizonIntroPlayback {
    private static var hasPresented = false

    static func claimFirstPresentation() -> Bool {
        guard !hasPresented else { return false }
        hasPresented = true
        return true
    }
}

private struct SummitStar {
    let point: CGPoint
    let radius: CGFloat
    let opacity: Double
}

struct SummitHeaderOverlay<ProfileButton: View>: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let profileButton: ProfileButton

    init(title: String, subtitle: String, profileButton: ProfileButton) {
        self.title = title
        self.subtitle = subtitle
        self.profileButton = profileButton
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                wordmark
                Text(subtitle.uppercased())
                    .font(AppTypography.metadataEmphasis)
                    .tracking(1.4)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .accessibilityLabel(subtitle)
            }
            Spacer(minLength: 0)
            profileButton
                .padding(9)
                .frame(minWidth: 44, minHeight: 44)
                .overlay {
                    Circle()
                        .stroke(appTheme.colors.textPrimary, lineWidth: 1)
                        .accessibilityHidden(true)
                }
        }
        .padding(20)
    }

    @ViewBuilder
    private var wordmark: some View {
        if title.localizedCaseInsensitiveCompare("Peakline") == .orderedSame {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Peakl")
                ZStack(alignment: .topLeading) {
                    Text("ı")
                    SummitWordmarkFlag()
                        .offset(x: 3, y: -2)
                        .accessibilityHidden(true)
                }
                Text("ne")
            }
            .font(AppTypography.screenTitle)
            .foregroundStyle(appTheme.colors.textPrimary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
        } else {
            Text(title)
                .font(AppTypography.screenTitle)
                .foregroundStyle(appTheme.colors.textPrimary)
        }
    }
}

private struct SummitWordmarkFlag: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Canvas { context, _ in
            var pole = Path()
            pole.move(to: CGPoint(x: 2, y: 15))
            pole.addLine(to: CGPoint(x: 2, y: 1))
            context.stroke(pole, with: .color(appTheme.colors.textPrimary), lineWidth: 1.6)

            var pennant = Path()
            pennant.move(to: CGPoint(x: 2, y: 1))
            pennant.addLine(to: CGPoint(x: 10, y: 3.5))
            pennant.addLine(to: CGPoint(x: 2, y: 6))
            pennant.closeSubpath()
            context.fill(pennant, with: .color(appTheme.colors.textPrimary))
        }
        .frame(width: 12, height: 16)
        .accessibilityHidden(true)
    }
}

private struct SummitHorizonPreviewGallery: View {
    private let previewWeek = [0.34, 0.72, 0.45, 0.9, 0.58, 0.22, 0.63]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(SummitCondition.allCases, id: \.self) { condition in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(condition.accessibilityName.capitalized)
                            .font(AppTypography.sectionTitle)
                        ForEach(SummitTimeOfDay.allCases, id: \.self) { timeOfDay in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(timeOfDay.accessibilityName.capitalized)
                                    .font(AppTypography.metadataEmphasis)
                                    .foregroundStyle(.secondary)
                                HStack(alignment: .top, spacing: 8) {
                                    previewItem(condition: condition, timeOfDay: timeOfDay, isEmpty: true)
                                    previewItem(condition: condition, timeOfDay: timeOfDay, isEmpty: false)
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func previewItem(
        condition: SummitCondition,
        timeOfDay: SummitTimeOfDay,
        isEmpty: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isEmpty ? "Empty" : "Week")
                .font(AppTypography.metadata)
                .foregroundStyle(.secondary)
            SummitHorizonView(
                week: isEmpty ? Array(repeating: 0, count: 7) : previewWeek,
                todayIndex: 2,
                prDayIndex: isEmpty ? nil : 3,
                condition: condition,
                timeOfDay: timeOfDay,
                isEmpty: isEmpty,
                animatesIntro: false
            )
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Summit horizon · Light") {
    SummitHorizonPreviewGallery()
        .preferredColorScheme(.light)
}

#Preview("Summit horizon · Dark") {
    SummitHorizonPreviewGallery()
        .preferredColorScheme(.dark)
}

import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Summit reached

struct SummitReachedView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var milestoneLabelSize: CGFloat = 13
    @ScaledMetric(relativeTo: .largeTitle) private var peakNameSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var metresSize: CGFloat = 60
    @ScaledMetric(relativeTo: .title) private var metresUnitSize: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var descriptionSize: CGFloat = 15
    @ScaledMetric(relativeTo: .title2) private var statisticValueSize: CGFloat = 22

    let moment: SummitMoment
    let unitSystem: UnitSystem
    let onDone: () -> Void

    @State private var ringProgress: CGFloat = 0
    @State private var routeProgress: CGFloat = 0
    @State private var flagScale: CGFloat = 0
    @State private var displayedMetres: Int
    @State private var hapticStep = 0

    init(
        moment: SummitMoment,
        unitSystem: UnitSystem,
        onDone: @escaping () -> Void
    ) {
        self.moment = moment
        self.unitSystem = unitSystem
        self.onDone = onDone
        _displayedMetres = State(initialValue: moment.previousPeakMetres)
    }

    var body: some View {
        GeometryReader { geometry in
            let headerHeight = max(220, min(360, geometry.size.height - 560))

            ScrollView {
                VStack(spacing: 0) {
                    topographicHeader(height: headerHeight)
                    summitCopy
                    statistics

                    if !moment.prs.isEmpty {
                        personalRecords
                    }

                    if moment.next != nil {
                        SummitMomentTape(moment: moment)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }
                }
                .padding(.bottom, 22)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                footer
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
        .task {
            await playIntroIfNeeded()
        }
        .sensoryFeedback(trigger: hapticStep) { _, newValue in
            switch newValue {
            case 1...3: .impact(weight: .light)
            case 4: .impact(weight: .heavy)
            default: nil
            }
        }
    }

    private func topographicHeader(height: CGFloat) -> some View {
        GeometryReader { geometry in
            let horizontalScale = geometry.size.width / 390
            let verticalScale = geometry.size.height / 360

            ZStack(alignment: .topLeading) {
                SummitReachedRingsCanvas(progress: ringProgress)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)

                SummitTrimmedRoute(progress: routeProgress)
                    .stroke(
                        appTheme.colors.textPrimary,
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 4])
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(true)

                Circle()
                    .fill(appTheme.colors.alpenglow)
                    .frame(width: 6.4, height: 6.4)
                    .position(x: 214 * horizontalScale, y: 150 * verticalScale)
                    .accessibilityHidden(true)

                SummitReachedFlag(color: appTheme.colors.alpenglow)
                    .frame(width: 18, height: 30)
                    .scaleEffect(flagScale, anchor: .bottom)
                    .position(x: 223 * horizontalScale, y: 135 * verticalScale)
                    .accessibilityHidden(true)

                Text(moment.peak.metres.formatted())
                    .font(Font.system(size: 11, weight: .semibold).width(.condensed).monospacedDigit())
                    .tracking(1.5)
                    .foregroundStyle(appTheme.colors.alpenglow)
                    .position(x: 222 * horizontalScale, y: 164 * verticalScale)
                    .accessibilityHidden(true)

                Text(routeCaption)
                    .modifier(AppTypography.waypointLabelSmall)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 24)
                    .padding(.trailing, 18)
                    .position(x: geometry.size.width / 2, y: 340 * verticalScale)
                    .accessibilityLabel("Your route, \(moment.sessionCount.formatted()) ascents since \(SummitMomentDateFormat.dayMonth(moment.firstSessionDate))")
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(height: height)
    }

    private var routeCaption: String {
        "YOUR ROUTE · \(moment.sessionCount.formatted()) ASCENTS SINCE \(SummitMomentDateFormat.dayMonth(moment.firstSessionDate))"
    }

    private var introIdentity: String {
        "\(moment.peak.id)|\(moment.date.timeIntervalSince1970)|\(moment.sessionCount)"
    }

    private var summitCopy: some View {
        VStack(spacing: 2) {
            Text("SUMMIT REACHED")
                .font(Font.system(size: milestoneLabelSize, weight: .semibold).width(.condensed))
                .tracking(3.12)
                .foregroundStyle(appTheme.colors.alpenglow)

            Text(moment.peak.name)
                .font(.system(size: peakNameSize, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayedMetres.formatted())
                    .font(Font.system(size: metresSize, weight: .semibold).width(.condensed).monospacedDigit())
                    .tracking(1.2)
                    .contentTransition(.numericText())
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text("M")
                    .font(Font.system(size: metresUnitSize, weight: .semibold).width(.condensed))
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(moment.peak.metres.formatted()) metres")

            Text("You’ve now lifted your own body weight \(moment.peak.metres.formatted()) metres. \(moment.peak.fact)")
                .font(.system(size: descriptionSize))
                .lineSpacing(2)
                .foregroundStyle(appTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
                .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var statistics: some View {
        HStack(spacing: 0) {
            statistic(
                value: "▲ +\(max(moment.gainedMetres, 0).formatted())",
                label: "M TODAY",
                valueColor: appTheme.colors.alpenglow
            )

            statisticDivider

            statistic(
                value: moment.durationMinutes.map { $0.formatted() } ?? "—",
                label: "MIN",
                valueColor: appTheme.colors.textPrimary
            )

            statisticDivider

            statistic(
                value: moment.setCount.formatted(),
                label: "SETS",
                valueColor: appTheme.colors.textPrimary
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(appTheme.colors.textTertiary.opacity(0.38))
                .frame(height: 0.5)
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(appTheme.colors.textTertiary.opacity(0.38))
                .frame(height: 0.5)
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
        }
        // Separate the top hairline from the fact line above it.
        .padding(.top, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Altitude gained today, \(max(moment.gainedMetres, 0).formatted()) metres. " +
            "Duration, \(moment.durationMinutes.map { "\($0) minutes" } ?? "not recorded"). " +
            "Sets, \(moment.setCount.formatted())."
        )
    }

    private var statisticDivider: some View {
        Rectangle()
            .fill(appTheme.colors.textTertiary.opacity(0.38))
            .frame(width: 0.5, height: 42)
            .accessibilityHidden(true)
    }

    private func statistic(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(Font.system(size: statisticValueSize, weight: .semibold).width(.condensed).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(valueColor)

            Text(label)
                .modifier(AppTypography.waypointLabelSmall)
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var personalRecords: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(moment.prs.enumerated()), id: \.offset) { element in
                SummitMomentPRRow(record: element.element, unitSystem: unitSystem)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            SummitPostcardShareButton(moment: moment)

            SummitPrimaryButton(title: "Done", action: onDone)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea(edges: .bottom))
    }

    private func playIntroIfNeeded() async {
        guard await SummitReachedIntroGate.shared.claim(for: introIdentity) else {
            showFinalState()
            return
        }

        guard !reduceMotion else {
            showFinalState()
            hapticStep = 4
            return
        }

        withAnimation(.linear(duration: 1.72)) {
            ringProgress = 1
        }
        withAnimation(.easeInOut(duration: 0.9).delay(0.5)) {
            routeProgress = 1
        }
        withAnimation(.easeOut(duration: 0.45).delay(1.3)) {
            flagScale = 1
        }

        for step in 1...44 {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            if step >= 25 {
                displayedMetres = interpolatedMetres(step: step - 24)
            }

            switch step {
            case 6: hapticStep = 1
            case 12: hapticStep = 2
            case 18: hapticStep = 3
            case 35: hapticStep = 4
            default: break
            }
        }
    }

    private func showFinalState() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            ringProgress = 1
            routeProgress = 1
            flagScale = 1
            displayedMetres = moment.peak.metres
        }
    }

    private func interpolatedMetres(step: Int) -> Int {
        let start = Double(moment.previousPeakMetres)
        let end = Double(moment.peak.metres)
        return Int((start + (end - start) * Double(step) / 20).rounded())
    }
}

private actor SummitReachedIntroGate {
    static let shared = SummitReachedIntroGate()
    private var playedMilestones = Set<String>()

    func claim(for identity: String) -> Bool {
        playedMilestones.insert(identity).inserted
    }
}

private struct SummitMomentPRRow: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .body) private var exerciseSize: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var recordSize: CGFloat = 17

    let record: SummitPR
    let unitSystem: UnitSystem

    private var weightText: String {
        "\(SummitWeightFormatting.setLoad(record.weightKg, isBodyweight: record.isBodyweight, unitSystem: unitSystem).uppercased()) × \(record.reps.formatted())"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SummitPRFlag()
                .fill(appTheme.colors.alpenglow)
                .frame(width: 14, height: 18)
                .accessibilityHidden(true)

            (Text(record.exerciseName)
                .font(.system(size: exerciseSize))
                .foregroundColor(appTheme.colors.textPrimary)
            + Text(" \(weightText)")
                .font(Font.system(size: recordSize, weight: .semibold).width(.condensed).monospacedDigit())
                .foregroundColor(appTheme.colors.textPrimary)
            + Text(" · new best")
                .font(.system(size: exerciseSize))
                .foregroundColor(appTheme.colors.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(record.exerciseName), \(SummitWeightFormatting.accessibleSetLoad(record.weightKg, isBodyweight: record.isBodyweight, unitSystem: unitSystem)), \(record.reps.formatted()) reps, new personal record"
        )
    }
}

private struct SummitPRFlag: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let poleX = rect.minX + rect.width * 0.18
        path.move(to: CGPoint(x: poleX, y: rect.minY))
        path.addLine(to: CGPoint(x: poleX, y: rect.maxY))
        path.move(to: CGPoint(x: poleX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.23))
        path.addLine(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.48))
        path.closeSubpath()
        return path
    }
}

private struct SummitReachedFlag: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var pole = Path()
            pole.move(to: CGPoint(x: 1, y: 0))
            pole.addLine(to: CGPoint(x: 1, y: size.height))
            context.stroke(pole, with: .color(color), lineWidth: 2)

            var pennant = Path()
            pennant.move(to: CGPoint(x: 1, y: 0))
            pennant.addLine(to: CGPoint(x: size.width, y: 6))
            pennant.addLine(to: CGPoint(x: 1, y: 12))
            pennant.closeSubpath()
            context.fill(pennant, with: .color(color))
        }
    }
}

private struct SummitReachedGeometry {
    struct Ring {
        let index: Int
        let path: Path
        let opacity: Double
        let lineWidth: CGFloat
    }

    static let shared = SummitReachedGeometry()
    let rings: [Ring]
    let route: Path

    private init() {
        rings = (1...14).map { index in
            let radius = 10 + 17 * Double(index)
            let centerX = 214 - 2.2 * Double(index)
            let centerY = 150 + 3.1 * Double(index)
            var path = Path()

            for pointIndex in 0...72 {
                let angle = Double(pointIndex) / 72 * .pi * 2
                let wobble = 1
                    + 0.07 * sin(3 * angle + 0.55 * Double(index))
                    + 0.045 * sin(5 * angle - 0.35 * Double(index))
                    + 0.02 * sin(8 * angle + Double(index))
                let x = centerX + cos(angle) * radius * wobble * 1.18
                let y = centerY + sin(angle) * radius * wobble * 0.8
                let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
                if pointIndex == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()

            let opacity: Double
            let lineWidth: CGFloat
            switch index {
            case 1:
                opacity = 1
                lineWidth = 1.5
            case 2...3:
                opacity = 0.6
                lineWidth = 1.2
            case 4...8:
                opacity = 0.34
                lineWidth = 1.1
            default:
                opacity = 0.16
                lineWidth = 1
            }
            return Ring(index: index, path: path, opacity: opacity, lineWidth: lineWidth)
        }

        var route = Path()
        route.move(to: CGPoint(x: 22, y: 312))
        route.addCurve(
            to: CGPoint(x: 120, y: 250),
            control1: CGPoint(x: 70, y: 300),
            control2: CGPoint(x: 88, y: 262)
        )
        route.addCurve(
            to: CGPoint(x: 168, y: 214),
            control1: CGPoint(x: 152, y: 238),
            control2: CGPoint(x: 160, y: 236)
        )
        route.addCurve(
            to: CGPoint(x: 214, y: 150),
            control1: CGPoint(x: 176, y: 192),
            control2: CGPoint(x: 196, y: 186)
        )
        self.route = route
    }
}

private struct SummitReachedRingsCanvas: View, Animatable {
    @Environment(\.appTheme) private var appTheme
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let widthScale = size.width / 390
            let heightScale = size.height / 360
            let elapsed = Double(progress) * 1.72

            for ring in SummitReachedGeometry.shared.rings {
                let delay = Double(14 - ring.index) * 0.04
                let linearProgress = min(max((elapsed - delay) / 1.2, 0), 1)
                let easedProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)
                let scale = CGFloat(1.35 - 0.35 * easedProgress)
                let transform = CGAffineTransform(
                    a: scale * widthScale,
                    b: 0,
                    c: 0,
                    d: scale * heightScale,
                    tx: 214 * (1 - scale) * widthScale,
                    ty: 150 * (1 - scale) * heightScale
                )
                let path = ring.path.applying(transform)
                let color = ring.index == 1 ? appTheme.colors.alpenglow : appTheme.colors.textPrimary
                context.stroke(
                    path,
                    with: .color(color.opacity(ring.opacity * easedProgress)),
                    lineWidth: ring.lineWidth
                )
            }
        }
    }
}

private struct SummitTrimmedRoute: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scaled = SummitReachedGeometry.shared.route.applying(
            CGAffineTransform(scaleX: rect.width / 390, y: rect.height / 360)
        )
        return scaled.trimmedPath(from: 0, to: min(max(progress, 0), 1))
    }
}

private struct SummitMomentTape: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let moment: SummitMoment

    private var next: SummitPeak? { moment.next }

    private var nextSummitHeadline: String {
        "NEXT · \(next?.name.uppercased() ?? "SUMMIT") · \(next?.metres.formatted() ?? "—") M"
    }

    private var metresToNextLabel: String {
        "\(metresToNext.formatted()) M TO GO"
    }

    private var lowerBound: Int {
        max(0, moment.peak.metres / 1_000 * 1_000)
    }

    private var upperBound: Int {
        guard let next else { return lowerBound + 100 }
        let rounded = (next.metres + 99) / 100 * 100
        return max(rounded, lowerBound + 100)
    }

    private var metresToNext: Int {
        moment.metresToNext ?? max(0, (next?.metres ?? moment.totalMetres) - moment.totalMetres)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextSummitHeadline)
                        Text(metresToNextLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 8) {
                        Text(nextSummitHeadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(metresToNextLabel)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .modifier(AppTypography.waypointLabelSmall)
            .foregroundStyle(appTheme.colors.textSecondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)
            .accessibilityHidden(true)

            Canvas { context, size in
                let range = Double(max(upperBound - lowerBound, 100))
                let tickCount = max(0, (upperBound - lowerBound) / 100)

                for index in 0...tickCount {
                    let metres = lowerBound + index * 100
                    let fraction = min(max((Double(metres) - Double(lowerBound)) / range, 0), 1)
                    let x = 3 + CGFloat(fraction) * (size.width - 6)
                    let height: CGFloat = metres.isMultiple(of: 500) ? 16 : 9
                    let opacity = metres <= moment.totalMetres ? 0.9 : 0.28
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: 24))
                    tick.addLine(to: CGPoint(x: x, y: 24 - height))
                    context.stroke(
                        tick,
                        with: .color(appTheme.colors.textPrimary.opacity(opacity)),
                        lineWidth: 1.3
                    )
                }

                let currentFraction = min(max(
                    (Double(moment.totalMetres) - Double(lowerBound)) / range,
                    0
                ), 1)
                let currentX = 3 + CGFloat(currentFraction) * (size.width - 6)
                var pointer = Path()
                pointer.move(to: CGPoint(x: currentX, y: 2))
                pointer.addLine(to: CGPoint(x: currentX - 5, y: 2))
                pointer.addLine(to: CGPoint(x: currentX, y: 9))
                pointer.addLine(to: CGPoint(x: currentX + 5, y: 2))
                pointer.closeSubpath()
                context.fill(pointer, with: .color(appTheme.colors.textPrimary))

                let nextFraction = min(max(
                    (Double(next?.metres ?? upperBound) - Double(lowerBound)) / range,
                    0
                ), 1)
                let nextX = 3 + CGFloat(nextFraction) * (size.width - 6)
                var nextMarker = Path()
                nextMarker.move(to: CGPoint(x: nextX, y: 24))
                nextMarker.addLine(to: CGPoint(x: nextX - 5, y: 24))
                nextMarker.addLine(to: CGPoint(x: nextX, y: 16))
                nextMarker.addLine(to: CGPoint(x: nextX + 5, y: 24))
                nextMarker.closeSubpath()
                context.stroke(nextMarker, with: .color(appTheme.colors.textSecondary), lineWidth: 1.1)
            }
            .frame(height: 26)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Next summit, \(next?.name ?? "not set"), \(next?.metres.formatted() ?? "unknown altitude") metres. \(metresToNext.formatted()) metres to go."
        )
    }
}

// MARK: - Summit postcard

struct SummitPostcardView: View {
    let moment: SummitMoment

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 390, geometry.size.height / 487.5)

            ZStack(alignment: .topLeading) {
                SummitPostcardPalette.paper
                SummitPostcardArtwork(moment: moment)

                VStack(alignment: .leading, spacing: 2) {
                    Text("GREETINGS FROM")
                        .font(Font.system(size: 11, weight: .semibold).width(.condensed))
                        .tracking(2.64)
                        .foregroundStyle(SummitPostcardPalette.accent)
                    Text(moment.peak.coordinates)
                        .font(Font.system(size: 13, weight: .medium).width(.condensed))
                        .tracking(2.34)
                        .foregroundStyle(SummitPostcardPalette.ink)
                }
                .padding(.leading, 24)
                .padding(.top, 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.peak.name.uppercased())
                        .font(Font.system(size: 64, weight: .bold).width(.condensed))
                        .tracking(0.64)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(SummitPostcardPalette.ink)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(moment.peak.metres.formatted()) M")
                            .font(Font.system(size: 26, weight: .semibold).width(.condensed).monospacedDigit())
                            .foregroundStyle(SummitPostcardPalette.accent)
                        Spacer(minLength: 0)
                        Text("\(moment.sessionCount.formatted()) ASCENTS · \(SummitMomentDateFormat.dayMonth(moment.firstSessionDate)) – \(SummitMomentDateFormat.dayMonth(moment.date))")
                            .font(Font.system(size: 12, weight: .medium).width(.condensed))
                            .tracking(1.68)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(SummitPostcardPalette.ink)
                    }
                    .padding(.top, 4)

                    Rectangle()
                        .fill(SummitPostcardPalette.ink.opacity(0.8))
                        .frame(height: 1)
                        .padding(.top, 10)

                    HStack(alignment: .center) {
                        Text("Lifted, one set at a time.")
                            .font(.system(size: 13))
                            .foregroundStyle(SummitPostcardPalette.ink)
                        Spacer()
                        Text("Peakline")
                            .font(.system(size: 15, weight: .bold))
                            .tracking(-0.2)
                            .foregroundStyle(SummitPostcardPalette.ink)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
                .frame(width: 390, height: 487.5, alignment: .bottomLeading)

                Text("\(moment.peak.metres.formatted()) M")
                    .font(Font.system(size: 9, weight: .semibold).width(.condensed).monospacedDigit())
                    .tracking(1)
                    .foregroundStyle(SummitPostcardPalette.ink)
                    .position(x: 332, y: 97)
                    .accessibilityHidden(true)

                Text("PEAKLINE")
                    .font(Font.system(size: 8.5, weight: .semibold).width(.condensed))
                    .tracking(1)
                    .foregroundStyle(SummitPostcardPalette.ink.opacity(0.7))
                    .position(x: 288, y: 98)
                    .accessibilityHidden(true)

                Text(SummitMomentDateFormat.fullDate(moment.date))
                    .font(Font.system(size: 8, weight: .regular).width(.condensed))
                    .tracking(0.8)
                    .foregroundStyle(SummitPostcardPalette.ink.opacity(0.7))
                    .position(x: 288, y: 109)
                    .accessibilityHidden(true)
            }
            .frame(width: 390, height: 487.5, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Greetings from \(moment.peak.name), \(moment.peak.coordinates). \(moment.peak.metres.formatted()) metres, \(moment.sessionCount.formatted()) ascents. Lifted, one set at a time."
        )
    }
}

private enum SummitPostcardPalette {
    static let paper = Color(red: 243.0 / 255.0, green: 239.0 / 255.0, blue: 230.0 / 255.0)
    static let ink = Color(red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 21.0 / 255.0)
    static let accent = Color(red: 210.0 / 255.0, green: 96.0 / 255.0, blue: 62.0 / 255.0)
}

private struct SummitPostcardArtwork: View {
    let moment: SummitMoment

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 390
            let scaleY = size.height / 487.5
            let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            let geometry = SummitPostcardGeometry.shared

            context.drawLayer { layer in
                layer.clip(to: geometry.mountain)
                for contour in geometry.contours {
                    layer.stroke(
                        contour.applying(transform),
                        with: .color(SummitPostcardPalette.ink.opacity(0.13)),
                        lineWidth: 1
                    )
                }
            }

            context.stroke(
                geometry.profile.applying(transform),
                with: .color(SummitPostcardPalette.ink),
                style: StrokeStyle(lineWidth: 1.8, lineJoin: .round)
            )
            context.stroke(
                geometry.crest.applying(transform),
                with: .color(SummitPostcardPalette.accent),
                style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
            )

            var pole = Path()
            pole.move(to: CGPoint(x: 232, y: 186))
            pole.addLine(to: CGPoint(x: 232, y: 208))
            context.stroke(pole, with: .color(SummitPostcardPalette.accent), lineWidth: 1.6)
            var flag = Path()
            flag.move(to: CGPoint(x: 232, y: 186))
            flag.addLine(to: CGPoint(x: 244, y: 190))
            flag.addLine(to: CGPoint(x: 232, y: 194))
            flag.closeSubpath()
            context.fill(flag, with: .color(SummitPostcardPalette.accent))

            let stamp = Path(CGRect(x: 296, y: 22, width: 72, height: 86))
            context.stroke(
                stamp,
                with: .color(SummitPostcardPalette.ink),
                style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.2])
            )
            context.stroke(
                Path(CGRect(x: 303, y: 29, width: 58, height: 72)),
                with: .color(SummitPostcardPalette.ink),
                lineWidth: 0.8
            )
            context.stroke(geometry.stampMountain, with: .color(SummitPostcardPalette.ink), lineWidth: 1.2)
            context.stroke(geometry.stampFlag, with: .color(SummitPostcardPalette.accent), lineWidth: 0.8)
            context.fill(geometry.stampFlag, with: .color(SummitPostcardPalette.accent))

            context.stroke(
                Path(ellipseIn: CGRect(x: 258, y: 72, width: 60, height: 60)),
                with: .color(SummitPostcardPalette.ink.opacity(0.55)),
                lineWidth: 1
            )
            context.stroke(
                Path(ellipseIn: CGRect(x: 264, y: 78, width: 48, height: 48)),
                with: .color(SummitPostcardPalette.ink.opacity(0.55)),
                lineWidth: 0.7
            )
            for wave in geometry.postmarkWaves {
                context.stroke(
                    wave,
                    with: .color(SummitPostcardPalette.ink.opacity(0.45)),
                    lineWidth: 0.9
                )
            }
        }
        .frame(width: 390, height: 487.5)
        .accessibilityHidden(true)
    }
}

private struct SummitPostcardGeometry {
    static let shared = SummitPostcardGeometry()

    let contours: [Path]
    let profile: Path
    let mountain: Path
    let crest: Path
    let stampMountain: Path
    let stampFlag: Path
    let postmarkWaves: [Path]

    private init() {
        let centerX = 230.0
        let centerY = 250.0
        var contours: [Path] = []
        for index in 1...16 {
            let radius = 12 + 17 * Double(index)
            let offsetX = centerX - Double(index) * 2
            let offsetY = centerY + Double(index) * 1.5
            var path = Path()
            for pointIndex in 0...80 {
                let angle = Double(pointIndex) / 80 * .pi * 2
                let wobble = 1
                    + 0.08 * sin(3 * angle + Double(index) * 0.6)
                    + 0.05 * sin(5 * angle - Double(index) * 0.4)
                    + 0.025 * sin(9 * angle + Double(index))
                let point = CGPoint(
                    x: CGFloat(offsetX + cos(angle) * radius * wobble * 1.25),
                    y: CGFloat(offsetY + sin(angle) * radius * wobble * 0.78)
                )
                if pointIndex == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            contours.append(path)
        }
        self.contours = contours

        let points: [CGPoint] = [
            CGPoint(x: 0, y: 316), CGPoint(x: 36, y: 302), CGPoint(x: 70, y: 306),
            CGPoint(x: 104, y: 300), CGPoint(x: 132, y: 292), CGPoint(x: 160, y: 268),
            CGPoint(x: 184, y: 246), CGPoint(x: 204, y: 226), CGPoint(x: 220, y: 214),
            CGPoint(x: 232, y: 208), CGPoint(x: 246, y: 212), CGPoint(x: 262, y: 222),
            CGPoint(x: 280, y: 240), CGPoint(x: 300, y: 252), CGPoint(x: 318, y: 270),
            CGPoint(x: 340, y: 282), CGPoint(x: 366, y: 300), CGPoint(x: 390, y: 306)
        ]

        var profile = Path()
        for (index, point) in points.enumerated() {
            if index == 0 { profile.move(to: point) } else { profile.addLine(to: point) }
        }
        self.profile = profile

        var mountain = profile
        mountain.addLine(to: CGPoint(x: 390, y: 487.5))
        mountain.addLine(to: CGPoint(x: 0, y: 487.5))
        mountain.closeSubpath()
        self.mountain = mountain

        var crest = Path()
        for (index, point) in points[6...12].enumerated() {
            if index == 0 { crest.move(to: point) } else { crest.addLine(to: point) }
        }
        self.crest = crest

        var stampMountain = Path()
        stampMountain.move(to: CGPoint(x: 307, y: 88))
        stampMountain.addLine(to: CGPoint(x: 318, y: 70))
        stampMountain.addLine(to: CGPoint(x: 324, y: 78))
        stampMountain.addLine(to: CGPoint(x: 333, y: 60))
        stampMountain.addLine(to: CGPoint(x: 346, y: 88))
        self.stampMountain = stampMountain

        var stampFlag = Path()
        stampFlag.move(to: CGPoint(x: 333, y: 60))
        stampFlag.addLine(to: CGPoint(x: 333, y: 50))
        stampFlag.addLine(to: CGPoint(x: 341, y: 53))
        stampFlag.addLine(to: CGPoint(x: 333, y: 56))
        stampFlag.closeSubpath()
        self.stampFlag = stampFlag

        postmarkWaves = [96, 104, 112].map { y in
            var wave = Path()
            wave.move(to: CGPoint(x: 190, y: CGFloat(y)))
            for start in stride(from: 190.0, to: 250.0, by: 20) {
                wave.addQuadCurve(
                    to: CGPoint(x: CGFloat(start + 10), y: CGFloat(y - 5)),
                    control: CGPoint(x: CGFloat(start + 5), y: CGFloat(y - 5))
                )
                wave.addQuadCurve(
                    to: CGPoint(x: CGFloat(start + 20), y: CGFloat(y)),
                    control: CGPoint(x: CGFloat(start + 15), y: CGFloat(y + 5))
                )
            }
            return wave
        }
    }
}

private enum SummitMomentDateFormat {
    static func dayMonth(_ date: Date) -> String {
        format(date, pattern: "d MMM")
    }

    static func fullDate(_ date: Date) -> String {
        format(date, pattern: "d MMM yyyy")
    }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = pattern
        return formatter.string(from: date).uppercased()
    }
}

@MainActor
enum SummitPostcardRenderer {
    static func image(for moment: SummitMoment) -> UIImage {
        let renderer = ImageRenderer(
            content: SummitPostcardView(moment: moment)
                .frame(width: 390, height: 487.5)
        )
        renderer.scale = 1080.0 / 390.0
        return renderer.uiImage ?? UIImage()
    }
}

private enum SummitPostcardExportError: Error {
    case imageEncodingFailed
}

private struct SummitPostcardTransfer: Transferable {
    let moment: SummitMoment

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            try await MainActor.run {
                guard let data = SummitPostcardRenderer.image(for: item.moment).pngData() else {
                    throw SummitPostcardExportError.imageEncodingFailed
                }
                return data
            }
        }
    }
}

struct SummitPostcardShareButton: View {
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 16
    let moment: SummitMoment

    var body: some View {
        ShareLink(
            item: SummitPostcardTransfer(moment: moment),
            preview: SharePreview(
                "Greetings from \(moment.peak.name)",
                image: Image(systemName: "mountain.2.fill")
            )
        ) {
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .font(.system(size: 16, weight: .medium))
                    .accessibilityHidden(true)
                Text("Send a postcard")
                    .font(.system(size: titleSize, weight: .semibold))
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                Capsule().stroke(Color.primary.opacity(0.7), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send a postcard from \(moment.peak.name)")
    }
}

// MARK: - Previews

private extension SummitMoment {
    static var emptyPreview: SummitMoment {
        SummitMoment(
            peak: SummitCatalog.peaks[0],
            previousPeakMetres: 0,
            totalMetres: 0,
            gainedMetres: 0,
            durationMinutes: nil,
            setCount: 0,
            prs: [],
            next: nil,
            metresToNext: nil,
            firstSessionDate: Date(),
            sessionCount: 0,
            date: Date()
        )
    }
}

#Preview("Summit · Light") {
    SummitReachedView(moment: .preview, unitSystem: .metric, onDone: {})
        .preferredColorScheme(.light)
}

#Preview("Summit · Dark") {
    SummitReachedView(moment: .preview, unitSystem: .metric, onDone: {})
        .preferredColorScheme(.dark)
}

#Preview("Summit · Empty") {
    SummitReachedView(moment: .emptyPreview, unitSystem: .imperial, onDone: {})
        .preferredColorScheme(.dark)
}

#Preview("Summit · Accessibility") {
    SummitReachedView(moment: .preview, unitSystem: .metric, onDone: {})
        .environment(\.dynamicTypeSize, .accessibility2)
        .preferredColorScheme(.light)
}

#Preview("Postcard · Light") {
    SummitPostcardView(moment: .preview)
        .frame(width: 390, height: 487.5)
        .preferredColorScheme(.light)
}

#Preview("Postcard · Dark") {
    SummitPostcardView(moment: .preview)
        .frame(width: 390, height: 487.5)
        .preferredColorScheme(.dark)
}

#Preview("Postcard share button") {
    SummitPostcardShareButton(moment: .preview)
        .padding()
        .preferredColorScheme(.dark)
}

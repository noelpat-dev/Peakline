import SwiftUI

private struct SummitRangePoint {
    let lift: SummitLiftPeak
    let x: CGFloat
    let nowY: CGFloat
    let thenY: CGFloat
}

private enum SummitRangeGeometry {
    static func centerOutSlots(_ count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let leftCenter = (count - 1) / 2
        var slots = [leftCenter]
        var distance = 1
        let startsRight = count.isMultiple(of: 2)
        while slots.count < count {
            let left = leftCenter - distance
            let right = leftCenter + distance
            let first = startsRight ? right : left
            let second = startsRight ? left : right
            if (0..<count).contains(first) { slots.append(first) }
            if (0..<count).contains(second) { slots.append(second) }
            distance += 1
        }
        return slots
    }

    static func ridge(points: [SummitRangePoint], width: CGFloat, baseline: CGFloat, then: Bool) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))

        for (index, point) in points.enumerated() {
            let y = then ? point.thenY : point.nowY
            let previousX = index == 0 ? 0 : points[index - 1].x
            let previousY = index == 0
                ? baseline - 20
                : (then ? points[index - 1].thenY : points[index - 1].nowY)
            let saddleX = (previousX + point.x) / 2
            let saddleY = min(max(previousY, y) + 30 + CGFloat(index % 2) * 14, baseline - 8)

            path.addLine(to: CGPoint(x: saddleX, y: index == 0 ? baseline - 20 : saddleY))
            path.addLine(to: CGPoint(x: point.x - 9, y: y + 12))
            path.addLine(to: CGPoint(x: point.x, y: y))
            path.addLine(to: CGPoint(x: point.x + 7, y: y + 9))
        }

        path.addLine(to: CGPoint(x: width, y: baseline - 30))
        return path
    }
}

private struct SummitRangePRFlag: View {
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color)
                .frame(width: 1.5, height: 18)
            Path { path in
                path.move(to: CGPoint(x: 1.5, y: 0))
                path.addLine(to: CGPoint(x: 11.5, y: 3.5))
                path.addLine(to: CGPoint(x: 1.5, y: 7))
                path.closeSubpath()
            }
            .fill(color)
            .frame(width: 12, height: 7)
        }
        .frame(width: 12, height: 18, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct SummitRangeChart: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var legendSize: CGFloat = 10.5

    let lifts: [SummitLiftPeak]
    let selectedID: UUID?
    let unitSystem: UnitSystem

    private var rangeLifts: [SummitLiftPeak] {
        let ranked = lifts.sorted {
            if $0.e1RMNow == $1.e1RMNow { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return $0.e1RMNow > $1.e1RMNow
        }
        var positions = Array<SummitLiftPeak?>(repeating: nil, count: ranked.count)
        for (lift, slot) in zip(ranked, SummitRangeGeometry.centerOutSlots(ranked.count)) {
            positions[slot] = lift
        }
        return positions.compactMap { $0 }
    }

    private var maxValue: Double {
        let values = lifts.flatMap { [$0.e1RMNow, $0.e1RMThen] }
            .map { SummitWeightFormatting.displayValue($0, unitSystem: unitSystem) }
        return max(values.max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let points = makePoints(width: width)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawChart(context: context, size: size, points: points)
                }
                .accessibilityHidden(true)

                Text("— NOW   - - 12 WEEKS AGO")
                    .font(Font.system(size: legendSize, weight: .medium).width(.condensed).monospacedDigit())
                    .tracking(1.1)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .position(x: dynamicTypeSize.isAccessibilitySize ? width / 2 : min(width / 2, 96), y: 228)
                    .accessibilityHidden(true)
            }
            .frame(width: width, height: 236)
        }
        .frame(height: 236)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chartAccessibilityLabel)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedID)
    }

    private func makePoints(width: CGFloat) -> [SummitRangePoint] {
        let ordered = rangeLifts
        guard !ordered.isEmpty else { return [] }
        let margin = min(width * 0.09, 38)
        let step = ordered.count > 1 ? (width - margin * 2) / CGFloat(ordered.count - 1) : 0
        return ordered.enumerated().map { index, lift in
            let x = ordered.count == 1 ? width / 2 : margin + CGFloat(index) * step
            let now = SummitWeightFormatting.displayValue(lift.e1RMNow, unitSystem: unitSystem)
            let then = SummitWeightFormatting.displayValue(lift.e1RMThen, unitSystem: unitSystem)
            return SummitRangePoint(
                lift: lift,
                x: x,
                nowY: 206 - CGFloat(now / maxValue) * 170,
                thenY: 206 - CGFloat(then / maxValue) * 170
            )
        }
    }

    private func drawChart(context: GraphicsContext, size: CGSize, points: [SummitRangePoint]) {
        let backPoints: [CGPoint] = [
            CGPoint(x: 0, y: 150), CGPoint(x: 40, y: 118), CGPoint(x: 78, y: 132),
            CGPoint(x: 120, y: 96), CGPoint(x: 160, y: 112), CGPoint(x: 205, y: 80),
            CGPoint(x: 248, y: 104), CGPoint(x: 290, y: 86), CGPoint(x: 330, y: 110),
            CGPoint(x: 390, y: 92)
        ]
        var backRidge = Path()
        for (index, point) in backPoints.enumerated() {
            let scaled = CGPoint(x: point.x * size.width / 390, y: point.y)
            if index == 0 { backRidge.move(to: scaled) } else { backRidge.addLine(to: scaled) }
        }
        context.stroke(backRidge, with: .color(appTheme.colors.textPrimary.opacity(0.16)), lineWidth: 1)

        let thenRidge = SummitRangeGeometry.ridge(points: points, width: size.width, baseline: 206, then: true)
        context.stroke(
            thenRidge,
            with: .color(appTheme.colors.textPrimary.opacity(0.38)),
            style: StrokeStyle(lineWidth: 1.1, lineJoin: .round, dash: [3, 3])
        )

        let nowRidge = SummitRangeGeometry.ridge(points: points, width: size.width, baseline: 206, then: false)
        context.stroke(nowRidge, with: .color(appTheme.colors.textPrimary), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        if let selected = points.first(where: { $0.lift.id == selectedID }) {
            var dropLine = Path()
            dropLine.move(to: CGPoint(x: selected.x, y: selected.nowY))
            dropLine.addLine(to: CGPoint(x: selected.x, y: 206))
            context.stroke(dropLine, with: .color(appTheme.colors.textPrimary), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

            let ring = Path(ellipseIn: CGRect(x: selected.x - 4, y: selected.nowY - 4, width: 8, height: 8))
            context.fill(ring, with: .color(appTheme.colors.backgroundPrimary))
            context.stroke(ring, with: .color(appTheme.colors.textPrimary), lineWidth: 1.6)
        }

        for point in points where point.lift.hasRecentPR {
            var pole = Path()
            pole.move(to: CGPoint(x: point.x, y: point.nowY))
            pole.addLine(to: CGPoint(x: point.x, y: point.nowY - 18))
            context.stroke(pole, with: .color(appTheme.colors.alpenglow), lineWidth: 1.5)

            var pennant = Path()
            pennant.move(to: CGPoint(x: point.x, y: point.nowY - 18))
            pennant.addLine(to: CGPoint(x: point.x + 10, y: point.nowY - 14.5))
            pennant.addLine(to: CGPoint(x: point.x, y: point.nowY - 11))
            pennant.closeSubpath()
            context.fill(pennant, with: .color(appTheme.colors.alpenglow))
        }

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: 206))
        baseline.addLine(to: CGPoint(x: size.width, y: 206))
        context.stroke(baseline, with: .color(appTheme.colors.cardBorder), lineWidth: 1)
    }

    private var chartAccessibilityLabel: String {
        guard let lift = lifts.first(where: { $0.id == selectedID }) else {
            return "Estimated one-rep max range, no lifts logged"
        }
        let amount = SummitWeightFormatting.displayString(lift.e1RMNow, unitSystem: unitSystem)
        let unit = unitSystem == .imperial ? "pounds" : "kilograms"
        return "Estimated one-rep max range for \(lift.name), currently \(amount) \(unit)"
    }
}

private struct SummitLiftTrend: View {
    @Environment(\.appTheme) private var appTheme

    let values: [Double]
    let hasRecentPR: Bool
    let unitSystem: UnitSystem

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty else { return }
            let shownValues = values.map { SummitWeightFormatting.displayValue($0, unitSystem: unitSystem) }
            let low = (shownValues.min() ?? 0) - 4
            let high = (shownValues.max() ?? 0) + 2
            let span = max(high - low, 1)
            let baseline: CGFloat = size.height - 6

            func point(at index: Int) -> CGPoint {
                let x = shownValues.count == 1
                    ? size.width / 2
                    : 2 + CGFloat(index) / CGFloat(shownValues.count - 1) * (size.width - 4)
                let y = CGFloat(84 - (shownValues[index] - low) / span * 76)
                return CGPoint(x: x, y: y)
            }

            var line = Path()
            for index in shownValues.indices {
                let position = point(at: index)
                if index == shownValues.startIndex { line.move(to: position) } else { line.addLine(to: position) }
            }

            var area = line
            let lastPoint = point(at: shownValues.count - 1)
            let firstPoint = point(at: 0)
            area.addLine(to: CGPoint(x: lastPoint.x, y: baseline))
            area.addLine(to: CGPoint(x: firstPoint.x, y: baseline))
            area.closeSubpath()

            var hatching = context
            hatching.clip(to: area)
            var hatch = Path()
            for y in stride(from: 6.0, through: Double(baseline), by: 5.0) {
                hatch.move(to: CGPoint(x: 0, y: CGFloat(y)))
                hatch.addLine(to: CGPoint(x: size.width, y: CGFloat(y)))
            }
            hatching.stroke(hatch, with: .color(appTheme.colors.textPrimary.opacity(0.22)), lineWidth: 1)

            context.stroke(line, with: .color(appTheme.colors.textPrimary), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            let last = Path(ellipseIn: CGRect(x: lastPoint.x - 3, y: lastPoint.y - 3, width: 6, height: 6))
            context.fill(last, with: .color(hasRecentPR ? appTheme.colors.alpenglow : appTheme.colors.textPrimary))

            var baselinePath = Path()
            baselinePath.move(to: CGPoint(x: 0, y: baseline))
            baselinePath.addLine(to: CGPoint(x: size.width, y: baseline))
            context.stroke(baselinePath, with: .color(appTheme.colors.cardBorder), lineWidth: 1)
        }
        .frame(height: 92)
        .accessibilityHidden(true)
    }
}

struct SummitRangeView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var sectionTitleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var trendLabelSize: CGFloat = 10.5
    @ScaledMetric(relativeTo: .body) private var deltaSize: CGFloat = 15

    let lifts: [SummitLiftPeak]
    let unitSystem: UnitSystem

    @State private var selectedLiftID: UUID?

    /// Pushed inside a navigation stack, the system back button is enough;
    /// the board's "‹ History" link is for standalone presentation only.
    private let showsBackLink: Bool

    init(lifts: [SummitLiftPeak], unitSystem: UnitSystem, showsBackLink: Bool = true) {
        self.lifts = lifts
        self.unitSystem = unitSystem
        self.showsBackLink = showsBackLink
        _selectedLiftID = State(initialValue: lifts.max(by: { $0.e1RMNow < $1.e1RMNow })?.id)
    }

    private var selectedLift: SummitLiftPeak? {
        lifts.first(where: { $0.id == selectedLiftID }) ?? lifts.max(by: { $0.e1RMNow < $1.e1RMNow })
    }

    private var selectorColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                if showsBackLink {
                    Button(action: { dismiss() }) {
                        Text("‹ History")
                            .font(.system(size: 16))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .frame(height: 32, alignment: .leading)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("YOUR RANGE · \(lifts.count) \(lifts.count == 1 ? "LIFT" : "LIFTS") · 12 WEEKS")
                    .modifier(AppTypography.waypointLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Progress")
                    .font(.system(size: sectionTitleSize, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(appTheme.colors.textPrimary)
            }
            .padding(.horizontal, 20)

            SummitRangeChart(lifts: lifts, selectedID: selectedLift?.id, unitSystem: unitSystem)
                .padding(.top, 4)

            if lifts.isEmpty {
                TrailSection(index: 1, label: "YOUR LIFTS") {
                    TrailStop(title: "Your first logged working set will mark the range.")
                }
                .padding(.trailing, 20)
            } else {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(lifts) { lift in
                                        liftButton(lift, scrollable: true)
                                            .id(lift.id)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }
                            .onAppear {
                                if let selectedID = selectedLift?.id {
                                    proxy.scrollTo(selectedID, anchor: .center)
                                }
                            }
                        }
                    } else {
                        LazyVGrid(columns: selectorColumns, spacing: 4) {
                            ForEach(lifts) { lift in
                                liftButton(lift)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.top, 6)

                if let selectedLift {
                    TrailSection(index: 1, label: selectedLift.name) {
                        liftDetail(selectedLift)
                    }
                    .padding(.trailing, 20)
                    .id(selectedLift.id)
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: lifts.map(\.id)) { _, currentIDs in
            guard let selectedLiftID, !currentIDs.contains(selectedLiftID) else { return }
            self.selectedLiftID = lifts.max(by: { $0.e1RMNow < $1.e1RMNow })?.id
        }
    }

    private func liftButton(_ lift: SummitLiftPeak, scrollable: Bool = false) -> some View {
        let isSelected = lift.id == selectedLift?.id
        let value = SummitWeightFormatting.displayString(lift.e1RMNow, unitSystem: unitSystem)
        return Button {
            if reduceMotion {
                selectedLiftID = lift.id
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { selectedLiftID = lift.id }
            }
        } label: {
            VStack(spacing: 0) {
                Text(lift.shortName)
                    .modifier(AppTypography.waypointLabelSmall)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(value)
                    .modifier(AppTypography.instrumentValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(isSelected ? appTheme.colors.textPrimary : appTheme.colors.textSecondary)
            .padding(.horizontal, scrollable ? 10 : 0)
            .fixedSize(horizontal: scrollable, vertical: false)
            .frame(
                minWidth: scrollable ? 76 : nil,
                maxWidth: scrollable ? nil : .infinity,
                minHeight: 48
            )
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? appTheme.colors.textPrimary : appTheme.colors.cardBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(selectorAccessibilityLabel(for: lift))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectorAccessibilityLabel(for lift: SummitLiftPeak) -> String {
        let now = SummitWeightFormatting.displayString(lift.e1RMNow, unitSystem: unitSystem)
        let change = SummitWeightFormatting.displayString(abs(lift.e1RMNow - lift.e1RMThen), unitSystem: unitSystem)
        let unitName = unitSystem == .imperial ? "pounds" : "kilograms"
        let direction = lift.e1RMNow >= lift.e1RMThen ? "up" : "down"
        let recentPR = lift.hasRecentPR ? ", new PR" : ""
        return "\(lift.name), estimated one-rep max \(now) \(unitName), \(direction) \(change) in 12 weeks\(recentPR)"
    }

    private func liftDetail(_ lift: SummitLiftPeak) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(SummitWeightFormatting.displayString(lift.e1RMNow, unitSystem: unitSystem))
                        .modifier(AppTypography.instrumentHero)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text("\(SummitWeightFormatting.unitSymbol(unitSystem).uppercased()) E1RM")
                        .modifier(AppTypography.instrumentUnit)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                let change = lift.e1RMNow - lift.e1RMThen
                let magnitude = SummitWeightFormatting.displayString(abs(change), unitSystem: unitSystem)
                Text("\(change >= 0 ? "▲ +" : "▼ −")\(magnitude) \(SummitWeightFormatting.unitSymbol(unitSystem).uppercased()) · 12 WKS")
                    .font(Font.system(size: deltaSize, weight: .semibold).width(.condensed).monospacedDigit())
                    .tracking(0.4)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .accessibilityElement(children: .combine)

            SummitLiftTrend(values: lift.weeklyBest, hasRecentPR: lift.hasRecentPR, unitSystem: unitSystem)
                .padding(.top, 10)

            HStack {
                Text(trendStartLabel)
                Spacer()
                Text(trendEndLabel)
            }
            .font(Font.system(size: trendLabelSize, weight: .medium).width(.condensed).monospacedDigit())
            .tracking(1.1)
            .foregroundStyle(appTheme.colors.textTertiary)
            .padding(.top, 2)
            .accessibilityHidden(true)

            Text("BEST SETS")
                .modifier(AppTypography.waypointLabel)
                .padding(.top, 18)

            if lift.bestSets.isEmpty {
                Text("No best sets in this range yet.")
                    .font(.system(.body))
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .padding(.vertical, 9)
            } else {
                ForEach(Array(lift.bestSets.prefix(3))) { set in
                    bestSetRow(set)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func bestSetRow(_ set: SummitBestSet) -> some View {
        let setText = "\(SummitWeightFormatting.setLoad(set.weightKg, isBodyweight: set.isBodyweight, unitSystem: unitSystem).uppercased()) × \(set.reps)"
        return HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 8) {
                if set.isPR {
                    SummitRangePRFlag(color: appTheme.colors.alpenglow)
                        .frame(width: 12, height: 14)
                }
                Text(setText)
                    .modifier(AppTypography.instrumentValue)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Text(set.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(.caption))
                .foregroundStyle(appTheme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(appTheme.colors.cardBorder.opacity(0.75)).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(set.isPR ? "Personal record, " : "")\(SummitWeightFormatting.accessibleSetLoad(set.weightKg, isBodyweight: set.isBodyweight, unitSystem: unitSystem)), \(set.reps) reps, \(set.date.formatted(date: .abbreviated, time: .omitted))")
    }

    private var trendStartLabel: String {
        let start = Calendar.current.date(byAdding: .weekOfYear, value: -12, to: .now) ?? .now
        return start.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }

    private var trendEndLabel: String {
        Date.now.formatted(.dateTime.month(.abbreviated)).uppercased()
    }
}

#if DEBUG
#Preview("Summit range · Light") {
    ScrollView { SummitRangeView(lifts: SummitSnapshot.preview.lifts, unitSystem: .metric) }
        .preferredColorScheme(.light)
}

#Preview("Summit range · Dark · Empty") {
    ScrollView { SummitRangeView(lifts: SummitSnapshot.empty.lifts, unitSystem: .metric) }
        .preferredColorScheme(.dark)
}

#Preview("Summit range · Accessibility") {
    ScrollView { SummitRangeView(lifts: SummitSnapshot.preview.lifts, unitSystem: .imperial) }
        .dynamicTypeSize(.accessibility2)
        .preferredColorScheme(.dark)
}
#endif

import SwiftUI

private actor SummitLogIntroGate {
    static let shared = SummitLogIntroGate()
    private var hasPlayed = false

    func claim() -> Bool {
        guard !hasPlayed else { return false }
        hasPlayed = true
        return true
    }
}

private enum SummitMonthRidgeGeometry {
    static func ridgePath(
        loads: [Double?],
        dayCount: Int,
        visibleDays: Int,
        width: CGFloat,
        baseline: CGFloat
    ) -> Path {
        let column = width / CGFloat(max(dayCount, 1))
        var path = Path()
        path.move(to: CGPoint(x: 0, y: baseline))

        guard visibleDays > 0 else { return path }

        for day in 0..<visibleDays {
            let x = CGFloat(day) * column
            let load = day < loads.count ? min(max(loads[day] ?? 0, 0), 1) : 0
            if load > 0 {
                let center = x + column / 2
                let height = CGFloat(load) * 64
                path.addLine(to: CGPoint(x: x + column * 0.08, y: baseline))
                path.addLine(to: CGPoint(x: center - column * 0.28, y: baseline - height * 0.55))
                path.addLine(to: CGPoint(x: center, y: baseline - height))
                path.addLine(to: CGPoint(x: center + column * 0.30, y: baseline - height * 0.48))
                path.addLine(to: CGPoint(x: x + column * 0.92, y: baseline))
            } else {
                path.addLine(to: CGPoint(x: x + column, y: baseline))
            }
        }

        return path
    }

    static func markerPoint(
        day: Int,
        loads: [Double?],
        dayCount: Int,
        width: CGFloat,
        baseline: CGFloat
    ) -> CGPoint {
        let column = width / CGFloat(max(dayCount, 1))
        let load = day < loads.count ? min(max(loads[day] ?? 0, 0), 1) : 0
        return CGPoint(
            x: (CGFloat(day) + 0.5) * column,
            y: baseline - CGFloat(load) * 64
        )
    }
}

private struct SummitLogFlag: View {
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(color)
                .frame(width: 1.5, height: 16)
            Path { path in
                path.move(to: CGPoint(x: 1.5, y: 0))
                path.addLine(to: CGPoint(x: 10.5, y: 3.5))
                path.addLine(to: CGPoint(x: 1.5, y: 7))
                path.closeSubpath()
            }
            .fill(color)
            .frame(width: 11, height: 7)
        }
        .frame(width: 11, height: 16, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct SummitSetProfile: Shape {
    let profile: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY - 1))

        guard !profile.isEmpty else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
            return path
        }

        let step = rect.width / CGFloat(profile.count)
        for (index, value) in profile.enumerated() {
            let x = CGFloat(index) * step
            let height = 3 + CGFloat(min(max(value, 0), 1)) * 24
            path.addLine(to: CGPoint(x: x + step * 0.3, y: rect.maxY - height))
            path.addLine(to: CGPoint(x: x + step * 0.7, y: rect.maxY - height * 0.8))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 1))
        return path
    }
}

private struct SummitMonthRidgeDrawing: View {
    @Environment(\.appTheme) private var appTheme

    let month: SummitMonthRidge
    let progress: CGFloat

    private var dayCount: Int { max(month.dayLoads.count, 1) }

    private var visibleDays: Int {
        if let todayIndex = month.todayIndex {
            return min(max(todayIndex + 1, 0), dayCount)
        }
        return min((month.dayLoads.lastIndex(where: { $0 != nil }).map { $0 + 1 }) ?? 0, dayCount)
    }

    var body: some View {
        Canvas { context, size in
            let baseline: CGFloat = 88
            let column = size.width / CGFloat(dayCount)
            let previousLoads: [Double?] = month.previousMonthLoads.map { Optional($0) }
            let previous = SummitMonthRidgeGeometry.ridgePath(
                loads: previousLoads,
                dayCount: dayCount,
                visibleDays: dayCount,
                width: size.width,
                baseline: baseline
            )
            context.stroke(
                previous,
                with: .color(appTheme.colors.textPrimary.opacity(0.18)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, dash: [3, 3])
            )

            let ridge = SummitMonthRidgeGeometry.ridgePath(
                loads: month.dayLoads,
                dayCount: dayCount,
                visibleDays: visibleDays,
                width: size.width,
                baseline: baseline
            )
            if progress > 0 {
                let trimmed = ridge.trimmedPath(from: 0, to: min(max(progress, 0), 1))
                var fill = trimmed
                let end = trimmed.currentPoint ?? CGPoint(x: 0, y: baseline)
                fill.addLine(to: CGPoint(x: end.x, y: 118))
                fill.addLine(to: CGPoint(x: 0, y: 118))
                fill.closeSubpath()
                context.fill(fill, with: .color(appTheme.colors.backgroundPrimary))
                context.stroke(
                    trimmed,
                    with: .color(appTheme.colors.textPrimary),
                    style: StrokeStyle(lineWidth: 1.8, lineJoin: .round)
                )
            }

            if visibleDays < dayCount {
                var future = Path()
                future.move(to: CGPoint(x: CGFloat(visibleDays) * column, y: baseline))
                future.addLine(to: CGPoint(x: size.width, y: baseline))
                context.stroke(
                    future,
                    with: .color(appTheme.colors.textTertiary),
                    style: StrokeStyle(lineWidth: 1.2, dash: [2, 4])
                )
            }

            var ticks = Path()
            for day in 1...dayCount {
                let x = (CGFloat(day) - 0.5) * column
                let isLabelDay = (day - 1).isMultiple(of: 7)
                ticks.move(to: CGPoint(x: x, y: 95))
                ticks.addLine(to: CGPoint(x: x, y: 97 + (isLabelDay ? 3 : 0)))
            }
            context.stroke(ticks, with: .color(appTheme.colors.textTertiary), lineWidth: 1)

            if let todayIndex = month.todayIndex, (0..<dayCount).contains(todayIndex) {
                let x = (CGFloat(todayIndex) + 0.5) * column
                var todayTick = Path()
                todayTick.move(to: CGPoint(x: x, y: 95))
                todayTick.addLine(to: CGPoint(x: x, y: 101))
                context.stroke(todayTick, with: .color(appTheme.colors.textPrimary), lineWidth: 1.6)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SummitMonthRidgeView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 11

    let month: SummitMonthRidge

    @State private var ridgeProgress: CGFloat = 0
    @State private var flagScale: CGFloat = 0

    private var dayCount: Int { max(month.dayLoads.count, 1) }

    private var flagIndices: [Int] {
        Array(Set(month.prDayIndices + month.summitDayIndices))
            .filter { (0..<dayCount).contains($0) }
            .sorted()
    }

    private var labelDays: [Int] {
        stride(from: 1, through: dayCount, by: 7).map { $0 }
    }

    private var highlightedLabelDay: Int? {
        guard let todayIndex = month.todayIndex else { return nil }
        let todayDay = todayIndex + 1
        return labelDays.last(where: { $0 <= todayDay })
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let column = width / CGFloat(dayCount)

            ZStack(alignment: .topLeading) {
                SummitMonthRidgeDrawing(month: month, progress: reduceMotion ? 1 : ridgeProgress)

                ForEach(flagIndices, id: \.self) { day in
                    let point = SummitMonthRidgeGeometry.markerPoint(
                        day: day,
                        loads: month.dayLoads,
                        dayCount: dayCount,
                        width: width,
                        baseline: 88
                    )
                    SummitLogFlag(color: appTheme.colors.alpenglow)
                        .scaleEffect(reduceMotion ? 1 : flagScale, anchor: .bottom)
                        .position(x: point.x, y: point.y - 8)
                }

                ForEach(labelDays, id: \.self) { day in
                    Text(day.formatted())
                        .font(Font.system(size: labelSize, weight: .medium).width(.condensed).monospacedDigit())
                        .foregroundStyle(day == highlightedLabelDay ? appTheme.colors.textPrimary : appTheme.colors.textTertiary)
                        .lineLimit(1)
                        .position(
                            x: min(max((CGFloat(day) - 0.5) * column, 12), max(width - 12, 12)),
                            y: 113
                        )
                }

                Text("- - \(previousMonthName)")
                    .modifier(AppTypography.waypointLabelSmall)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .lineLimit(1)
                    .position(x: width - 43, y: 25)
                    .accessibilityHidden(true)
            }
            .frame(width: width, height: 118)
        }
        .frame(height: 118)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .task {
            guard !reduceMotion else {
                ridgeProgress = 1
                flagScale = 1
                return
            }
            let shouldAnimate = await SummitLogIntroGate.shared.claim()
            guard shouldAnimate else {
                ridgeProgress = 1
                flagScale = 1
                return
            }
            withAnimation(.easeInOut(duration: 1.2)) {
                ridgeProgress = 1
            }
            do {
                try await Task.sleep(nanoseconds: 1_200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                flagScale = 1
            }
        }
    }

    private var previousMonthName: String {
        Calendar.current.date(byAdding: .month, value: -1, to: month.monthStart)?
            .formatted(.dateTime.month(.wide))
            .uppercased() ?? "PREVIOUS"
    }

    private var accessibilitySummary: String {
        let date = month.monthStart.formatted(.dateTime.month(.wide).year())
        let sessionDays = month.dayLoads.compactMap { $0 }.filter { $0 > 0 }.count
        let achievements = month.prDayIndices.count + month.summitDayIndices.count
        return "\(date), activity on \(sessionDays) days, \(achievements) achievement flags"
    }
}

struct SummitLogStatsRow: View {
    @Environment(\.appTheme) private var appTheme

    let ascents: Int
    let metres: Int
    let prFlags: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(value: ascents.formatted(), label: "ASCENTS")
            divider
            stat(value: metres.formatted(), label: "CLIMBED", unit: "M")
            divider
            stat(value: prFlags.formatted(), label: "PR FLAGS", valueColor: prFlags > 0 ? appTheme.colors.alpenglow : appTheme.colors.textPrimary)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(appTheme.colors.cardBorder.opacity(0.7)).frame(height: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(appTheme.colors.cardBorder.opacity(0.7)).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ascents) ascents, \(metres) metres climbed, \(prFlags) personal record flags")
    }

    private var divider: some View {
        Rectangle()
            .fill(appTheme.colors.cardBorder.opacity(0.7))
            .frame(width: 0.5)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }

    private func stat(value: String, label: String, unit: String? = nil, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .modifier(AppTypography.instrumentLarge)
                    .foregroundStyle(valueColor ?? appTheme.colors.textPrimary)
                if let unit {
                    Text(unit)
                        .modifier(AppTypography.instrumentUnit)
                }
            }
            Text(label)
                .modifier(AppTypography.waypointLabelSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 14)
    }
}

struct SummitLogEntryRow: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var metadataSize: CGFloat = 11.5
    @ScaledMetric(relativeTo: .subheadline) private var noteSize: CGFloat = 13
    @ScaledMetric(relativeTo: .largeTitle) private var dateNumberSize: CGFloat = 26
    @ScaledMetric(relativeTo: .body) private var gainSize: CGFloat = 15

    let climb: SummitSessionClimb
    let isToday: Bool
    let unitSystem: UnitSystem
    var isNewest: Bool = false

    private var dotColor: Color {
        if isNewest { return appTheme.colors.textPrimary }
        if climb.passedPeak != nil { return appTheme.colors.alpenglow }
        return appTheme.colors.textSecondary
    }

    private var displayTitle: String {
        climb.isLowerRoute ? "Lower route · \(climb.title)" : climb.title
    }

    private var metadata: String {
        if climb.isLowerRoute {
            return PeaklineText.joinedMetadata([
                "LOWER ROUTE",
                climb.durationMinutes.map { "\($0) MIN" } ?? "",
                "CAIRN KEPT"
            ])
        }
        return PeaklineText.joinedMetadata([
            climb.durationMinutes.map { "\($0) MIN" } ?? "",
            "\(climb.setCount) SETS",
            "\(SummitWeightFormatting.displayString(climb.volumeKg, unitSystem: unitSystem, maximumFractionDigits: 0)) \(SummitWeightFormatting.unitSymbol(unitSystem).uppercased())"
        ])
    }

    private var dateDay: String { Calendar.current.component(.day, from: climb.date).formatted() }
    private var weekday: String { climb.date.formatted(.dateTime.weekday(.abbreviated)).uppercased() }
    private var gainColor: Color {
        if climb.isLowerRoute { return appTheme.colors.textSecondary }
        return isToday ? appTheme.colors.alpenglow : appTheme.colors.textPrimary
    }

    private var accessibilitySummary: String {
        let unitName = unitSystem == .imperial ? "pounds" : "kilograms"
        var parts = [
            climb.date.formatted(date: .complete, time: .omitted),
            displayTitle,
            "climbed \(climb.metres) metres"
        ]
        if let durationMinutes = climb.durationMinutes {
            parts.append("\(durationMinutes) minutes")
        }
        if climb.isLowerRoute {
            parts.append("lower route, cairn kept")
        } else {
            parts.append("\(climb.setCount) sets")
            parts.append("\(SummitWeightFormatting.displayString(climb.volumeKg, unitSystem: unitSystem, maximumFractionDigits: 0)) \(unitName) total volume")
        }
        parts += climb.prs.map {
            "personal record, \($0.exerciseName), \(SummitWeightFormatting.accessibleSetLoad($0.weightKg, isBodyweight: $0.isBodyweight, unitSystem: unitSystem)) for \($0.reps) reps"
        }
        if let peak = climb.passedPeak {
            parts.append("summit passed, \(peak.name), \(peak.metres) metres")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(weekday)
                    .modifier(AppTypography.waypointLabelSmall)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(dateDay)
                    .font(Font.system(size: dateNumberSize, weight: .semibold).width(.condensed).monospacedDigit())
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: 38, alignment: .leading)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(displayTitle)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("+\(climb.metres.formatted()) M")
                        .font(Font.system(size: gainSize, weight: .semibold).width(.condensed).monospacedDigit())
                        .foregroundStyle(gainColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                SummitSetProfile(profile: climb.setProfile)
                    .stroke(appTheme.colors.textPrimary.opacity(0.85), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(appTheme.colors.cardBorder.opacity(0.75)).frame(height: 1)
                    }
                    .frame(height: 30)
                    .accessibilityHidden(true)

                Text(metadata)
                    .font(Font.system(size: metadataSize, weight: .medium).width(.condensed).monospacedDigit())
                    .tracking(1.2)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(climb.prs.enumerated()), id: \.offset) { _, pr in
                    noteLine(
                        "PR · \(pr.exerciseName) \(SummitWeightFormatting.setLoad(pr.weightKg, isBodyweight: pr.isBodyweight, unitSystem: unitSystem)) × \(pr.reps)",
                        color: appTheme.colors.alpenglow
                    )
                }

                if let peak = climb.passedPeak {
                    noteLine("Summit · \(peak.name) \(peak.metres.formatted()) m passed", color: appTheme.colors.alpenglow)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 48)
        .padding(.trailing, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(appTheme.colors.backgroundPrimary)
                .overlay { Circle().stroke(dotColor, lineWidth: 1.6) }
                .frame(width: 10, height: 10)
                .offset(x: 19, y: 17)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private func noteLine(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            SummitLogFlag(color: color)
                .frame(width: 14, height: 16)
            Text(text)
                .font(.system(size: noteSize, weight: .regular))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

struct SummitLogContent: View {
    let snapshot: SummitSnapshot
    let unitSystem: UnitSystem

    private var monthEntries: [SummitSessionClimb] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: snapshot.month.monthStart) else {
            return []
        }
        return snapshot.log.filter { interval.contains($0.date) }
    }

    private var totalMetres: Int { monthEntries.reduce(0) { $0 + $1.metres } }
    private var prCount: Int { monthEntries.reduce(0) { $0 + $1.prs.count } }

    var body: some View {
        VStack(spacing: 0) {
            SummitMonthRidgeView(month: snapshot.month)
                .padding(.horizontal, 20)

            SummitLogStatsRow(ascents: monthEntries.count, metres: totalMetres, prFlags: prCount)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            TrailPage {
                if monthEntries.isEmpty {
                    TrailStop(
                        title: snapshot.log.isEmpty
                            ? "Your first climb draws the first peak."
                            : "No climbs logged this month yet."
                    )
                        .padding(.leading, 48)
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(monthEntries.enumerated()), id: \.element.id) { index, climb in
                            SummitLogEntryRow(
                                climb: climb,
                                isToday: Calendar.current.isDateInToday(climb.date),
                                unitSystem: unitSystem,
                                isNewest: index == 0
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Summit log · Light") {
    ScrollView { SummitLogContent(snapshot: .preview, unitSystem: .metric) }
        .preferredColorScheme(.light)
}

#Preview("Summit log · Dark · Empty") {
    ScrollView { SummitLogContent(snapshot: .empty, unitSystem: .metric) }
        .preferredColorScheme(.dark)
}

#Preview("Summit log · Accessibility") {
    ScrollView { SummitLogContent(snapshot: .preview, unitSystem: .imperial) }
        .dynamicTypeSize(.accessibility2)
        .preferredColorScheme(.dark)
}
#endif

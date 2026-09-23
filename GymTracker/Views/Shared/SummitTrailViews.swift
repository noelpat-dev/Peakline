import SwiftUI

// MARK: - Summit TrailViews

struct ExpeditionView: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .largeTitle) private var mountainTitleSize: CGFloat = 34

    let progress: ExpeditionProgress?
    let reachedDates: [String: Date]
    let recentSessionsPerWeek: Double?
    let onSetOff: () -> Void

    init(
        progress: ExpeditionProgress?,
        reachedDates: [String: Date] = [:],
        recentSessionsPerWeek: Double? = nil,
        onSetOff: @escaping () -> Void
    ) {
        self.progress = progress
        self.reachedDates = reachedDates
        self.recentSessionsPerWeek = recentSessionsPerWeek
        self.onSetOff = onSetOff
    }

    var body: some View {
        Group {
            if let progress {
                expeditionContent(progress)
            } else {
                emptyContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.colors.backgroundPrimary)
    }

    private func expeditionContent(_ progress: ExpeditionProgress) -> some View {
        let camps = progress.route.camps
        let summit = camps.last
        let nextCamp = progress.nextCamp.flatMap { candidate in camps.first(where: { $0.id == candidate.id }) }
            ?? camps.first(where: { !progress.reachedCampIDs.contains($0.id) })
        let summitWindow = estimatedSummitWindow(for: progress)

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EXPEDITION · \(progress.route.name.uppercased()) · SET OFF \(dateLabel(progress.startDate).uppercased())")
                    .modifier(AppTypography.waypointLabel)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(progress.route.mountain)
                        .font(.system(size: mountainTitleSize, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)

                    Spacer(minLength: 4)

                    if let summit {
                        Text("\(summit.altitude.formatted()) M")
                            .modifier(AppTypography.instrumentValue)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(progress.route.mountain), summit \(summit?.altitude.formatted() ?? "unknown") metres")
            }
            .padding(.horizontal, 20)

            ExpeditionElevationProfile(progress: progress)
                .frame(height: 244)

            ExpeditionStatsRow(
                climbed: progress.climbedSinceStart,
                ascentLeft: progress.remainingAscent,
                summitWindow: summitWindow
            )
            .padding(.horizontal, 20)

            TrailPage {
                VStack(spacing: 0) {
                    ForEach(Array(camps.enumerated()), id: \.element.id) { index, camp in
                        let isReached = progress.reachedCampIDs.contains(camp.id)
                        let detail = campDetail(
                            camp,
                            index: index,
                            progress: progress,
                            camps: camps,
                            nextCamp: nextCamp,
                            isReached: isReached
                        )
                        TrailStop(title: camp.name, detail: detail, done: false) {
                            Text("\(camp.altitude.formatted())")
                                .modifier(AppTypography.instrumentValue)
                                .foregroundStyle(
                                    index == camps.count - 1
                                        ? appTheme.colors.alpenglow
                                        : (isReached ? appTheme.colors.textTertiary : appTheme.colors.textPrimary)
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .overlay(alignment: .leading) {
                            if isReached {
                                Circle()
                                    .fill(appTheme.colors.textPrimary)
                                    .frame(width: 7, height: 7)
                                    .offset(x: -27.5)
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(campAccessibilityLabel(camp, detail: detail))
                        .padding(.trailing, 20)
                    }
                }
                .padding(.top, 2)
            }
            .padding(.bottom, 20)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose an expedition")
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            SummitPrimaryButton(title: "Set off on the Machame Route", action: onSetOff)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
    }

    private func campDetail(
        _ camp: ExpeditionCamp,
        index: Int,
        progress: ExpeditionProgress,
        camps: [ExpeditionCamp],
        nextCamp: ExpeditionCamp?,
        isReached: Bool
    ) -> String? {
        if index == 0, isReached {
            return "Set off · \(dateLabel(progress.startDate))"
        }
        if isReached {
            if let date = reachedDates[camp.id] {
                return "Reached · \(dateLabel(date))"
            }
            return "Reached"
        }
        if nextCamp?.id == camp.id {
            var parts: [String] = ["Next"]
            if let distance = progress.metresToNextCamp {
                parts.append("\(max(0, distance).formatted()) m of lifting")
                if let sessions = estimatedSessions(toCover: distance, progress: progress), sessions > 0 {
                    parts.append("about \(sessions) sessions")
                }
            }
            return parts.joined(separator: " · ")
        }
        if index > 0 {
            let dropOrGain = camp.altitude - camps[index - 1].altitude
            if dropOrGain < 0 {
                return "Descents are free: you drop \((-dropOrGain).formatted()) m"
            }
            if index == camps.count - 1 {
                return "Summit · unlocks the \(progress.route.mountain) postcard"
            }
            return "+\(dropOrGain.formatted()) m"
        }
        return "Trailhead"
    }

    private func campAccessibilityLabel(_ camp: ExpeditionCamp, detail: String?) -> String {
        let description = [camp.name, detail, "\(camp.altitude.formatted()) metres"]
            .compactMap { $0 }
            .joined(separator: ", ")
        return description
    }

    private func estimatedSessions(toCover metres: Int, progress: ExpeditionProgress) -> Int? {
        guard metres > 0,
              progress.remainingAscent > 0,
              let sessionsLeft = progress.estimatedSessionsLeft,
              sessionsLeft > 0 else { return nil }
        return Int((Double(metres) * Double(sessionsLeft) / Double(progress.remainingAscent)).rounded())
    }

    private func estimatedSummitWindow(for progress: ExpeditionProgress) -> String {
        guard let sessionsLeft = progress.estimatedSessionsLeft,
              sessionsLeft >= 0,
              let recentSessionsPerWeek,
              recentSessionsPerWeek.isFinite,
              recentSessionsPerWeek > 0 else { return "—" }

        let weeksLeft = Double(max(0, sessionsLeft)) / recentSessionsPerWeek
        guard weeksLeft.isFinite, weeksLeft < 10_000 else { return "—" }
        let daysLeft = Int((weeksLeft * 7).rounded())
        guard let estimatedDate = Calendar.current.date(byAdding: .day, value: daysLeft, to: Date()) else { return "—" }
        let day = Calendar.current.component(.day, from: estimatedDate)
        let part = day <= 10 ? "EARLY" : (day <= 20 ? "MID" : "LATE")
        let month = DateFormatter.summitMonth(estimatedDate)
        return "\(part) \(month)"
    }
}

private struct ExpeditionStatsRow: View {
    @Environment(\.appTheme) private var appTheme

    let climbed: Int
    let ascentLeft: Int
    let summitWindow: String

    var body: some View {
        HStack(spacing: 0) {
            stat(value: "\(max(0, climbed).formatted()) M", label: "CLIMBED")
            divider
            stat(value: "\(max(0, ascentLeft).formatted()) M", label: "ASCENT LEFT")
            divider
            stat(value: summitWindow, label: "SUMMIT WINDOW")
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { dividerLine }
        .overlay(alignment: .bottom) { dividerLine }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Expedition stats. Climbed \(climbed) metres, \(ascentLeft) metres of ascent left, summit window \(summitWindow)")
    }

    private var divider: some View {
        Rectangle()
            .fill(appTheme.colors.textTertiary.opacity(0.35))
            .frame(width: 0.5, height: 40)
            .accessibilityHidden(true)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(appTheme.colors.textTertiary.opacity(0.35))
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .modifier(AppTypography.instrumentLarge)
                .foregroundStyle(appTheme.colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .modifier(AppTypography.waypointLabelSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

private struct ExpeditionElevationProfile: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .caption) private var gridLabelSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption) private var userLabelSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var descentLabelSize: CGFloat = 9.5
    let progress: ExpeditionProgress
    private let geometry: ExpeditionProfileGeometry

    init(progress: ExpeditionProgress) {
        self.progress = progress
        geometry = ExpeditionProfileGeometry(progress: progress)
    }

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 390
            let grid = geometry.gridPath.applying(CGAffineTransform(scaleX: scaleX, y: 1))
            context.stroke(grid, with: .color(appTheme.colors.textPrimary.opacity(0.07)), lineWidth: 1)

            for altitude in [2_000, 3_000, 4_000, 5_000] {
                let y = ExpeditionProfileGeometry.y(for: altitude) - 3
                context.draw(
                    Text(altitude.formatted())
                        .font(Font.system(size: gridLabelSize, weight: .medium).width(.condensed).monospacedDigit())
                        .foregroundColor(appTheme.colors.textTertiary),
                    at: CGPoint(x: size.width - 5, y: y),
                    anchor: .trailing
                )
            }

            let todo = geometry.todoPath.applying(CGAffineTransform(scaleX: scaleX, y: 1))
            context.stroke(
                todo,
                with: .color(appTheme.colors.textTertiary),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [3, 4])
            )
            let done = geometry.donePath.applying(CGAffineTransform(scaleX: scaleX, y: 1))
            context.stroke(done, with: .color(appTheme.colors.textPrimary), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            for tent in geometry.tents {
                let path = tent.path.applying(CGAffineTransform(scaleX: scaleX, y: 1))
                if tent.reached {
                    context.fill(path, with: .color(appTheme.colors.textPrimary))
                } else {
                    context.fill(path, with: .color(appTheme.colors.backgroundPrimary))
                    context.stroke(path, with: .color(appTheme.colors.textSecondary), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                }
            }

            context.stroke(geometry.summitPole.applying(CGAffineTransform(scaleX: scaleX, y: 1)), with: .color(appTheme.colors.alpenglow), lineWidth: 1.5)
            context.stroke(geometry.summitFlag.applying(CGAffineTransform(scaleX: scaleX, y: 1)), with: .color(appTheme.colors.alpenglow), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))

            let userPoint = CGPoint(x: geometry.userPoint.x * scaleX, y: geometry.userPoint.y)
            let halo = Path(ellipseIn: CGRect(x: userPoint.x - 10, y: userPoint.y - 10, width: 20, height: 20))
            context.stroke(halo, with: .color(appTheme.colors.textPrimary.opacity(0.35)), lineWidth: 1)
            let dot = Path(ellipseIn: CGRect(x: userPoint.x - 4.5, y: userPoint.y - 4.5, width: 9, height: 9))
            context.fill(dot, with: .color(appTheme.colors.textPrimary))
            context.draw(
                Text("YOU · \(max(0, progress.currentAltitude).formatted()) M")
                    .font(Font.system(size: userLabelSize, weight: .semibold).width(.condensed).monospacedDigit())
                    .tracking(1)
                    .foregroundColor(appTheme.colors.textPrimary),
                at: CGPoint(x: max(4, userPoint.x - 30), y: userPoint.y + 24),
                anchor: .leading
            )

            for label in geometry.descentLabels {
                context.draw(
                    Text(label.text)
                        .font(Font.system(size: descentLabelSize, weight: .medium).width(.condensed))
                        .tracking(1)
                        .foregroundColor(appTheme.colors.textSecondary),
                    at: CGPoint(x: label.point.x * scaleX, y: label.point.y),
                    anchor: .center
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elevation profile. You are at \(max(0, progress.currentAltitude).formatted()) metres on the \(progress.route.name), with \(max(0, progress.remainingAscent).formatted()) metres left to the summit.")
        .accessibilityHidden(false)
    }
}

private struct ExpeditionProfileGeometry {
    struct Tent {
        let path: Path
        let reached: Bool
    }

    struct TextMarker {
        let text: String
        let point: CGPoint
    }

    let gridPath: Path
    let donePath: Path
    let todoPath: Path
    let tents: [Tent]
    let summitPole: Path
    let summitFlag: Path
    let userPoint: CGPoint
    let descentLabels: [TextMarker]

    init(progress: ExpeditionProgress) {
        let camps = progress.route.camps
        let boardX: [CGFloat] = [18, 66, 116, 170, 208, 252, 298, 352]
        let points = camps.enumerated().map { index, camp in
            CGPoint(x: boardX[min(index, boardX.count - 1)], y: Self.y(for: camp.altitude))
        }

        var grid = Path()
        for altitude in [2_000, 3_000, 4_000, 5_000] {
            let y = Self.y(for: altitude)
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: 386, y: y))
        }
        gridPath = grid

        let nextIndex = progress.nextCamp.flatMap { next in camps.firstIndex(where: { $0.id == next.id }) }
            ?? camps.firstIndex(where: { !progress.reachedCampIDs.contains($0.id) })
            ?? max(0, camps.count - 1)
        let previousIndex = max(0, nextIndex - 1)
        let userX: CGFloat
        if camps.isEmpty {
            userX = 18
        } else if progress.nextCamp == nil && nextIndex == camps.count - 1 && progress.reachedCampIDs.contains(camps[nextIndex].id) {
            userX = points[nextIndex].x
        } else {
            let previousAltitude = camps.indices.contains(previousIndex) ? camps[previousIndex].altitude : progress.currentAltitude
            let nextAltitude = camps.indices.contains(nextIndex) ? camps[nextIndex].altitude : previousAltitude
            let difference = nextAltitude - previousAltitude
            let rawFraction = difference == 0 ? 0 : Double(progress.currentAltitude - previousAltitude) / Double(difference)
            let fraction = min(max(rawFraction, 0), 1)
            let startX = points.indices.contains(previousIndex) ? points[previousIndex].x : 18
            let endX = points.indices.contains(nextIndex) ? points[nextIndex].x : startX
            userX = startX + (endX - startX) * fraction
        }
        userPoint = CGPoint(x: userX, y: Self.y(for: progress.currentAltitude))

        var walked = Path()
        var ahead = Path()
        if let first = points.first {
            walked.move(to: first)
            for index in 0..<min(previousIndex, max(points.count - 1, 0)) {
                Self.addSegment(from: points[index], to: points[index + 1], fromAltitude: camps[index].altitude, toAltitude: camps[index + 1].altitude, to: &walked)
            }
            walked.addLine(to: userPoint)

            if nextIndex < points.count, !(progress.nextCamp == nil && progress.reachedCampIDs.contains(camps[nextIndex].id)) {
                ahead.move(to: userPoint)
                ahead.addLine(to: points[nextIndex])
                if nextIndex + 1 < points.count {
                    for index in nextIndex..<(points.count - 1) {
                        Self.addSegment(from: points[index], to: points[index + 1], fromAltitude: camps[index].altitude, toAltitude: camps[index + 1].altitude, to: &ahead)
                    }
                }
            }
        }
        donePath = walked
        todoPath = ahead

        if camps.count > 1 {
            tents = camps.dropLast().enumerated().map { index, camp in
                let point = points[index]
                var tent = Path()
                tent.move(to: CGPoint(x: point.x - 5, y: point.y - 3))
                tent.addLine(to: CGPoint(x: point.x, y: point.y - 11))
                tent.addLine(to: CGPoint(x: point.x + 5, y: point.y - 3))
                tent.closeSubpath()
                return Tent(path: tent, reached: progress.reachedCampIDs.contains(camp.id))
            }
        } else {
            tents = []
        }

        var pole = Path()
        var flag = Path()
        if let summit = points.last {
            let poleBase = summit.y - 2
            pole.move(to: CGPoint(x: summit.x, y: poleBase))
            pole.addLine(to: CGPoint(x: summit.x, y: poleBase - 20))
            flag.move(to: CGPoint(x: summit.x, y: poleBase - 20))
            flag.addLine(to: CGPoint(x: summit.x + 11, y: poleBase - 16))
            flag.addLine(to: CGPoint(x: summit.x, y: poleBase - 12))
        }
        summitPole = pole
        summitFlag = flag

        var labels: [TextMarker] = []
        if camps.count > 1 {
            for index in 0..<(camps.count - 1) where camps[index + 1].altitude < camps[index].altitude {
                labels.append(TextMarker(text: "CLIMB HIGH", point: CGPoint(x: points[index].x, y: points[index].y - 16)))
                labels.append(TextMarker(text: "SLEEP LOW", point: CGPoint(x: points[index + 1].x, y: points[index + 1].y + 18)))
            }
        }
        descentLabels = labels
    }

    static func y(for altitude: Int) -> CGFloat {
        222 - CGFloat(altitude - 1_500) / 4_500 * 200
    }

    private static func addSegment(
        from start: CGPoint,
        to end: CGPoint,
        fromAltitude: Int,
        toAltitude: Int,
        to path: inout Path
    ) {
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let jitter: CGFloat = toAltitude > fromAltitude ? -4 : 4
        path.addLine(to: CGPoint(x: midX - 6, y: midY + jitter))
        path.addLine(to: CGPoint(x: midX + 5, y: midY - jitter * 0.5))
        path.addLine(to: end)
    }
}

private extension DateFormatter {
    static func summitMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "MMM"
        return formatter.string(from: date).uppercased()
    }
}

private func dateLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_GB")
    formatter.dateFormat = "d MMM"
    return formatter.string(from: date)
}

#if DEBUG
#Preview("Expedition · dark") {
    ScrollView {
        ExpeditionView(
            progress: SummitSnapshot.preview.expedition,
            reachedDates: [
                "machame-camp": Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 19))!,
                "shira-camp": Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 8))!
            ],
            recentSessionsPerWeek: 4,
            onSetOff: {}
        )
    }
    .environment(\.appTheme, .black)
    .preferredColorScheme(.dark)
}

#Preview("Expedition · light") {
    ScrollView { ExpeditionView(progress: SummitSnapshot.preview.expedition, recentSessionsPerWeek: 4, onSetOff: {}) }
        .environment(\.appTheme, .black)
        .preferredColorScheme(.light)
}

#Preview("Expedition · empty") {
    ExpeditionView(progress: SummitSnapshot.empty.expedition, onSetOff: {})
        .environment(\.appTheme, .black)
        .preferredColorScheme(.dark)
}

#Preview("Expedition · accessibility") {
    ScrollView { ExpeditionView(progress: SummitSnapshot.preview.expedition, recentSessionsPerWeek: 4, onSetOff: {}) }
        .environment(\.appTheme, .black)
        .environment(\.dynamicTypeSize, .accessibility2)
        .preferredColorScheme(.dark)
}
#endif

struct CairnDetailView: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34
    @ScaledMetric(relativeTo: .subheadline) private var subtitleSize: CGFloat = 14

    let state: CairnState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("STREAK · ONE STONE PER WEEK")
                    .modifier(AppTypography.waypointLabel)
                Text("Cairn")
                    .font(.system(size: titleSize, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            CairnIllustration(state: state)
                .frame(height: 300)
                .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(max(0, state.stones).formatted())")
                        .modifier(AppTypography.instrumentHero)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text("WEEKS")
                        .modifier(AppTypography.instrumentUnit)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(max(0, state.stones)) weeks")

                Text(subtitle)
                    .font(.system(size: subtitleSize, weight: .regular))
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)

            CairnWeekStrip(state: state)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            TrailPage {
                VStack(spacing: 0) {
                    ForEach(Array(ruleItems.enumerated()), id: \.offset) { index, item in
                        TrailStop(title: item.title, detail: item.detail, done: false)
                            .overlay(alignment: .leading) {
                                if index < 2 {
                                    Circle()
                                        .fill(appTheme.colors.textPrimary)
                                        .frame(width: 7, height: 7)
                                        .offset(x: -27.5)
                                        .accessibilityHidden(true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding(.trailing, 20)
            }
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(appTheme.colors.backgroundPrimary)
        .accessibilityElement(children: .contain)
    }

    private var subtitle: String {
        if state.stones <= 0 {
            return "Two climbs this week lays your first stone."
        }
        if state.newestIsFresh {
            return "Stone \(state.stones) added this week."
        }
        return "One more climb this week adds stone \(state.stones + 1)."
    }

    private var ruleItems: [(title: String, detail: String)] {
        [
            ("Two climbs in a week add a stone", "Any workout counts. The lower route counts too."),
            ("Rest never knocks it down", "Rest days and storm days are part of the climb."),
            ("A missed week starts a new cairn", "The old one stays standing in the valley. Nothing is lost.")
        ]
    }
}

private struct CairnWeekStrip: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .caption) private var weekLabelSize: CGFloat = 10
    let state: CairnState

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(state.recentWeeks.enumerated()), id: \.offset) { index, week in
                VStack(spacing: 4) {
                    Ellipse()
                        .strokeBorder(
                            weekColor(at: index, week: week),
                            style: StrokeStyle(lineWidth: 1.4, dash: week.isCurrent && !week.qualified ? [3, 3] : [])
                        )
                        .frame(width: 22, height: 11)
                        .frame(maxWidth: .infinity)
                    Text(label(for: index, week: week))
                        .font(Font.system(size: weekLabelSize, weight: .medium).width(.condensed))
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, minHeight: 12)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekStripLabel)
        .accessibilityHidden(false)
    }

    private var weekStripLabel: String {
        let qualified = state.recentWeeks.filter(\.qualified).count
        return "Recent weeks, \(qualified) qualified weeks in the last twelve, current week \(max(0, state.climbsThisWeek)) of \(max(1, state.climbsNeeded)) climbs"
    }

    private func weekColor(at index: Int, week: CairnWeek) -> Color {
        if state.newestIsFresh,
           week.qualified,
           !week.isCurrent,
           index == state.recentWeeks.lastIndex(where: { $0.qualified && !$0.isCurrent }) {
            return appTheme.colors.alpenglow
        }
        if state.newestIsFresh && week.isCurrent && week.qualified {
            return appTheme.colors.alpenglow
        }
        return week.isCurrent && !week.qualified ? appTheme.colors.textTertiary : appTheme.colors.textPrimary
    }

    private func label(for index: Int, week: CairnWeek) -> String {
        if week.isCurrent { return "NOW" }
        if index == 0 { return DateFormatter.summitMonth(week.weekStart) }
        let priorWeek = state.recentWeeks[index - 1]
        let currentMonth = Calendar.current.component(.month, from: week.weekStart)
        let priorMonth = Calendar.current.component(.month, from: priorWeek.weekStart)
        return currentMonth == priorMonth ? "" : DateFormatter.summitMonth(week.weekStart)
    }
}

private struct CairnIllustration: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .caption) private var markerLabelSize: CGFloat = 11
    let state: CairnState
    private let drawing: CairnDrawing

    init(state: CairnState) {
        self.state = state
        drawing = CairnDrawing(state: state)
    }

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 390
            let ground = drawing.ground.applying(CGAffineTransform(scaleX: scaleX, y: 1))
            context.stroke(ground, with: .color(appTheme.colors.textTertiary.opacity(0.7)), lineWidth: 1.2)
            let grass = drawing.grass.applying(CGAffineTransform(scaleX: scaleX, y: 1))
            context.stroke(grass, with: .color(appTheme.colors.textTertiary.opacity(0.65)), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            for past in drawing.pastCairns {
                let transformed = past.paths.map { $0.applying(CGAffineTransform(scaleX: scaleX, y: 1)) }
                for path in transformed {
                    context.fill(path, with: .color(appTheme.colors.backgroundPrimary))
                    context.stroke(path, with: .color(appTheme.colors.textPrimary.opacity(0.3)), lineWidth: 1.1)
                }
                context.draw(
                    Text(past.label)
                        .font(Font.system(size: markerLabelSize - 1, weight: .medium).width(.condensed))
                        .tracking(1.2)
                        .foregroundColor(appTheme.colors.textTertiary),
                    at: CGPoint(x: past.centerX * scaleX, y: 282),
                    anchor: .center
                )
            }

            for (index, stone) in drawing.currentStones.enumerated() {
                let path = stone.path.applying(CGAffineTransform(scaleX: scaleX, y: 1))
                context.fill(path, with: .color(appTheme.colors.backgroundPrimary))
                let isFreshTop = index == drawing.currentStones.count - 1 && state.newestIsFresh
                context.stroke(
                    path,
                    with: .color(isFreshTop ? appTheme.colors.alpenglow : appTheme.colors.textPrimary),
                    style: StrokeStyle(lineWidth: isFreshTop ? 1.8 : 1.5, lineJoin: .round)
                )
            }

            if let pending = drawing.pendingStone {
                let path = pending.path.applying(CGAffineTransform(scaleX: scaleX, y: 1))
                context.stroke(
                    path,
                    with: .color(appTheme.colors.textSecondary),
                    style: StrokeStyle(lineWidth: 1.2, lineJoin: .round, dash: [3, 3])
                )
                context.draw(
                    Text("THIS WEEK · \(max(0, state.climbsThisWeek)) OF \(max(1, state.climbsNeeded))")
                        .font(Font.system(size: markerLabelSize, weight: .medium).width(.condensed))
                        .tracking(1.2)
                        .foregroundColor(appTheme.colors.textSecondary),
                    at: CGPoint(
                        x: size.width < 370
                            ? size.width - 8
                            : (pending.centerX - 2 + pending.rx / 0.82 * 0.9 + 8) * scaleX,
                        y: pending.centerY + 4
                    ),
                    anchor: size.width < 370 ? .trailing : .leading
                )
            }

            if let freshLabel = drawing.freshLabel {
                context.draw(
                    Text(freshLabel.text)
                        .font(Font.system(size: markerLabelSize, weight: .medium).width(.condensed))
                        .tracking(1.2)
                        .foregroundColor(appTheme.colors.alpenglow),
                    at: CGPoint(x: freshLabel.x * scaleX, y: freshLabel.y),
                    anchor: .leading
                )
            }

            if let overflowLabel = drawing.overflowLabel {
                context.draw(
                    Text(overflowLabel)
                        .font(Font.system(size: markerLabelSize + 2, weight: .semibold).width(.condensed).monospacedDigit())
                        .foregroundColor(state.newestIsFresh ? appTheme.colors.alpenglow : appTheme.colors.textPrimary),
                    at: CGPoint(x: 250 * scaleX, y: 62),
                    anchor: .center
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(illustrationLabel)
        .accessibilityHidden(false)
    }

    private var illustrationLabel: String {
        let stoneText = state.stones == 1 ? "1 stone" : "\(max(0, state.stones)) stones"
        let weekText = state.newestIsFresh ? "newest stone added this week" : "new stone needs \(max(0, state.climbsNeeded - state.climbsThisWeek)) more climbs this week"
        return "Cairn illustration, \(stoneText), \(weekText), \(state.pastCairns.count) past cairns in the valley"
    }
}

private struct CairnDrawing {
    struct Stone {
        let path: Path
        let centerX: CGFloat
        let centerY: CGFloat
        let rx: CGFloat
        let ry: CGFloat
    }

    struct Past {
        let paths: [Path]
        let centerX: CGFloat
        let label: String
    }

    struct TextMarker {
        let text: String
        let x: CGFloat
        let y: CGFloat
    }

    let currentStones: [Stone]
    let pastCairns: [Past]
    let pendingStone: Stone?
    let freshLabel: TextMarker?
    let overflowLabel: String?
    let ground: Path
    let grass: Path

    init(state: CairnState) {
        let total = max(0, state.stones)
        let visibleCount = min(total, 14)
        currentStones = Self.pile(centerX: 250, baseY: 254, count: visibleCount, scale: 1.25)

        let visiblePastCairns = Array(state.pastCairns.prefix(2).reversed())
        pastCairns = visiblePastCairns.enumerated().map { index, past in
            let centerX: CGFloat = index == 0 ? 48 : 104
            let scale: CGFloat = index == 0 ? 0.55 : 0.6
            let stones = Self.pile(centerX: centerX, baseY: index == 0 ? 262 : 260, count: min(max(0, past.height), 14), scale: scale)
            return Past(
                paths: stones.map(\.path),
                centerX: centerX,
                label: "\(DateFormatter.summitMonth(past.endedWeek)) · \(past.height)"
            )
        }

        if state.climbsThisWeek < state.climbsNeeded {
            let top: Stone
            if let last = currentStones.last {
                top = last
            } else {
                top = Stone(path: Path(), centerX: 250, centerY: 243, rx: 45, ry: 10.75)
            }
            let centerY = top.centerY - top.ry * 2.1
            let rx = top.rx * 0.82
            let ry = top.ry * 0.9
            pendingStone = Stone(
                path: Self.stone(centerX: top.centerX + 2, centerY: centerY, rx: rx, ry: ry, tilt: 0.05, lump: 0),
                centerX: top.centerX + 2,
                centerY: centerY,
                rx: rx,
                ry: ry
            )
        } else {
            pendingStone = nil
        }

        if state.newestIsFresh, let top = currentStones.last {
            freshLabel = TextMarker(text: "WEEK \(total) · NEW", x: top.centerX - top.rx - 96, y: top.centerY + 4)
        } else {
            freshLabel = nil
        }
        overflowLabel = total > visibleCount ? "+\(total - visibleCount)" : nil

        var groundPath = Path()
        groundPath.move(to: CGPoint(x: 0, y: 262))
        groundPath.addQuadCurve(to: CGPoint(x: 160, y: 258), control: CGPoint(x: 80, y: 250))
        groundPath.addQuadCurve(to: CGPoint(x: 390, y: 252), control: CGPoint(x: 280, y: 266))
        ground = groundPath

        var grassPath = Path()
        for x in [20.0, 70, 132, 160, 330, 352, 372] {
            grassPath.move(to: CGPoint(x: x, y: 258))
            grassPath.addLine(to: CGPoint(x: x - 2, y: 253))
            grassPath.move(to: CGPoint(x: x + 3, y: 258))
            grassPath.addLine(to: CGPoint(x: x + 4, y: 252))
        }
        grass = grassPath
    }

    private static func pile(centerX: CGFloat, baseY: CGFloat, count: Int, scale: CGFloat) -> [Stone] {
        var y = baseY
        return (0..<count).map { index in
            let rx = (36 - CGFloat(index) * 2.6) * scale
            let ry = (8.6 - CGFloat(index) * 0.22) * scale
            y -= ry * (index == 0 ? 1 : 1.72)
            let offset = sin(Double(index) * 1.9) * 3.2 * Double(scale)
            let tilt = sin(Double(index) * 2.7) * 0.07
            let x = centerX + CGFloat(offset)
            return Stone(
                path: stone(centerX: x, centerY: y, rx: rx, ry: ry, tilt: tilt, lump: 0.05),
                centerX: x,
                centerY: y,
                rx: rx,
                ry: ry
            )
        }
    }

    private static func stone(centerX: CGFloat, centerY: CGFloat, rx: CGFloat, ry: CGFloat, tilt: Double, lump: Double) -> Path {
        var path = Path()
        for index in 0...36 {
            let angle = Double(index) / 36 * .pi * 2
            let wobble = 1 + lump * sin(2 * angle + Double(rx)) + lump * 0.6 * sin(3 * angle + Double(ry))
            let x = cos(angle) * Double(rx) * wobble
            let y = sin(angle) * Double(ry) * wobble
            let rotatedX = x * cos(tilt) - y * sin(tilt)
            let rotatedY = x * sin(tilt) + y * cos(tilt)
            let point = CGPoint(x: centerX + CGFloat(rotatedX), y: centerY + CGFloat(rotatedY))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct SummitRouteForkView: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .caption) private var plannedTitleSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .body) private var alternativeTitleSize: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var alternativeDetailSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var secondaryActionSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var steadyNoteSize: CGFloat = 15

    let plan: SummitRoutePlan
    let onTakeLowerRoute: () -> Void
    let onClimbAnyway: () -> Void

    @ViewBuilder
    var body: some View {
        switch plan {
        case .planned:
            EmptyView()
        case let .steady(note):
            steadyView(note: note)
        case let .lowerRoute(plannedTitle, alternative):
            lowerRouteView(plannedTitle: plannedTitle, alternative: alternative)
        }
    }

    private func lowerRouteView(plannedTitle: String, alternative: SummitLowerRoute) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                SummitForkLines()
                    .accessibilityHidden(true)

                DimmedForkSign(text: "HIGH ROUTE · CLOSED")
                    .frame(width: 128, height: 22)
                    .offset(x: 160, y: 26)
                    .accessibilityHidden(true)

                Text(plannedTitle)
                    .font(.system(size: plannedTitleSize))
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .strikethrough(true, pattern: .solid, color: appTheme.colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .offset(x: 160, y: 50)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 0) {
                    TrailSignTag(text: "LOWER ROUTE · OPEN")
                    Text(alternative.title)
                        .font(.system(size: alternativeTitleSize, weight: .semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)
                    Text("\(alternative.minutes) min · \(alternative.detail)")
                        .font(.system(size: alternativeDetailSize))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .frame(maxWidth: 300, alignment: .leading)
                .offset(x: 48, y: 96)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Lower route open. \(alternative.title), \(alternative.minutes) minutes. \(alternative.detail)")

                Text("YOUR CAIRN IS SAFE · REST NEVER KNOCKS IT DOWN")
                    .modifier(AppTypography.waypointLabelSmall)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 48)
                    .padding(.trailing, 20)
                    .offset(y: 181)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your cairn is safe. Rest never knocks it down.")
            }
            .frame(height: 210)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("High route closed: \(plannedTitle). Lower route open: \(alternative.title), \(alternative.minutes) minutes. \(alternative.detail). Your cairn is safe. Rest never knocks it down.")

            VStack(spacing: 2) {
                SummitPrimaryButton(title: "Take the lower route", action: onTakeLowerRoute)
                Button(action: onClimbAnyway) {
                    Text("Climb as planned anyway")
                        .font(.system(size: secondaryActionSize))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 48)
            .padding(.trailing, 20)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func steadyView(note: String) -> some View {
        TrailPage {
            VStack(alignment: .leading, spacing: 10) {
                TrailSignTag(text: "STEADY CLIMB")
                Text(note)
                    .font(.system(size: steadyNoteSize))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Steady climb. \(note)")
            }
            .padding(.top, 10)
            .padding(.leading, 48)
            .padding(.trailing, 20)
            .padding(.bottom, 18)
        }
    }
}

private struct SummitForkLines: View {
    @Environment(\.appTheme) private var appTheme

    private let mainTrail = Path { path in
        path.move(to: CGPoint(x: 24.5, y: 0))
        path.addLine(to: CGPoint(x: 24.5, y: 210))
    }
    private let closedBranch = Path { path in
        path.move(to: CGPoint(x: 24.5, y: 0))
        path.addLine(to: CGPoint(x: 24.5, y: 28))
        path.addCurve(to: CGPoint(x: 70, y: 62), control1: CGPoint(x: 24.5, y: 50), control2: CGPoint(x: 40, y: 58))
        path.addLine(to: CGPoint(x: 112, y: 50))
        path.addLine(to: CGPoint(x: 140, y: 42))
    }
    private let cross = Path { path in
        path.move(to: CGPoint(x: 130, y: 34))
        path.addLine(to: CGPoint(x: 150, y: 44))
        path.move(to: CGPoint(x: 130, y: 44))
        path.addLine(to: CGPoint(x: 150, y: 34))
    }
    private let junction = Path(ellipseIn: CGRect(x: 19.5, y: 23, width: 10, height: 10))

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 390
            context.stroke(
                mainTrail.applying(CGAffineTransform(scaleX: scaleX, y: 1)),
                with: .color(appTheme.colors.textPrimary),
                style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
            )
            context.stroke(
                closedBranch.applying(CGAffineTransform(scaleX: scaleX, y: 1)),
                with: .color(appTheme.colors.textTertiary),
                style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])
            )
            context.stroke(
                cross.applying(CGAffineTransform(scaleX: scaleX, y: 1)),
                with: .color(appTheme.colors.textTertiary),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )
            let node = junction.applying(CGAffineTransform(scaleX: scaleX, y: 1))
            context.fill(node, with: .color(appTheme.colors.backgroundPrimary))
            context.stroke(node, with: .color(appTheme.colors.textPrimary), lineWidth: 1.6)
        }
    }
}

private struct SummitForkSignShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 13, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: rect.maxX - 4, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 13, y: rect.maxY - 2))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 2))
        path.closeSubpath()
        return path
    }
}

private struct DimmedForkSign: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 11.5
    let text: String

    var body: some View {
        Text(text)
            .font(Font.system(size: labelSize, weight: .semibold).width(.condensed).monospacedDigit())
            .tracking(0.9)
            .foregroundStyle(appTheme.colors.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 22)
            .background {
                SummitForkSignShape()
                    .stroke(appTheme.colors.textTertiary, lineWidth: 1.2)
            }
    }
}

#if DEBUG
#Preview("Cairn · dark") {
    ScrollView { CairnDetailView(state: SummitSnapshot.preview.cairn) }
        .environment(\.appTheme, .black)
        .preferredColorScheme(.dark)
}

#Preview("Cairn · light") {
    ScrollView { CairnDetailView(state: SummitSnapshot.preview.cairn) }
        .environment(\.appTheme, .black)
        .preferredColorScheme(.light)
}

#Preview("Cairn · empty") {
    ScrollView { CairnDetailView(state: SummitSnapshot.empty.cairn) }
        .environment(\.appTheme, .black)
        .preferredColorScheme(.dark)
}

#Preview("Cairn · accessibility") {
    ScrollView { CairnDetailView(state: SummitSnapshot.preview.cairn) }
        .environment(\.appTheme, .black)
        .environment(\.dynamicTypeSize, .accessibility2)
        .preferredColorScheme(.dark)
}

#Preview("Route fork · dark") {
    ScrollView {
        SummitRouteForkView(
            plan: .lowerRoute(
                plannedTitle: "Legs · Heavy · Squat 5 × 5",
                alternative: SummitLowerRoute(title: "Mobility + zone 2 walk", detail: "hips, T-spine, 20 min easy walk", minutes: 30)
            ),
            onTakeLowerRoute: {},
            onClimbAnyway: {}
        )
    }
    .environment(\.appTheme, .black)
    .preferredColorScheme(.dark)
}

#Preview("Route fork · light") {
    SummitRouteForkView(
        plan: .lowerRoute(
            plannedTitle: "Legs · Heavy · Squat 5 × 5",
            alternative: SummitLowerRoute(title: "Mobility + zone 2 walk", detail: "hips, T-spine, 20 min easy walk", minutes: 30)
        ),
        onTakeLowerRoute: {},
        onClimbAnyway: {}
    )
    .environment(\.appTheme, .black)
    .preferredColorScheme(.light)
}

#Preview("Route fork · steady") {
    SummitRouteForkView(plan: .steady(note: "Your planned climb is ready."), onTakeLowerRoute: {}, onClimbAnyway: {})
        .environment(\.appTheme, .black)
}

#Preview("Route fork · accessibility") {
    SummitRouteForkView(
        plan: .lowerRoute(
            plannedTitle: "Legs · Heavy · Squat 5 × 5",
            alternative: SummitLowerRoute(title: "Mobility + zone 2 walk", detail: "hips, T-spine, 20 min easy walk", minutes: 30)
        ),
        onTakeLowerRoute: {},
        onClimbAnyway: {}
    )
    .environment(\.appTheme, .black)
    .environment(\.dynamicTypeSize, .accessibility2)
    .preferredColorScheme(.dark)
}
#endif

import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct PeaklineWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivityWidget()
    }
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(
                attributes: context.attributes,
                state: context.state,
                isStale: context.isStale
            )
            .activityBackgroundTint(SummitWidgetStyle.black)
            .activitySystemActionForegroundColor(SummitWidgetStyle.primary)
        } dynamicIsland: { context in
            let now = Date.now
            let activityIsStale = context.isStale
            let activePR = context.state.pr.flatMap { pr in
                activityDeadlineIsLive(pr.until, now: now, isStale: activityIsStale) ? pr : nil
            }
            let activeRestEnd = context.state.restEndsAt.flatMap { restEndsAt in
                activityDeadlineIsLive(restEndsAt, now: now, isStale: activityIsStale)
                    ? restEndsAt
                    : nil
            }
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedIslandHeader(
                        attributes: context.attributes,
                        state: context.state,
                        pr: activePR,
                        restEndsAt: activeRestEnd
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedIslandTrailing(
                        state: context.state,
                        pr: activePR
                    )
                }
                .contentMargins(activePR == nil ? .trailing : [], 12)
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedIslandContent(
                        attributes: context.attributes,
                        state: context.state,
                        pr: activePR
                    )
                }
                .contentMargins(activePR == nil ? .horizontal : [], 12)
            } compactLeading: {
                HStack(spacing: 5) {
                    SummitMountainGlyph()
                        .stroke(SummitWidgetStyle.primary, lineWidth: 1.5)
                        .frame(width: 15, height: 12)
                    Text("\(context.state.overallSetIndex)/\(context.state.overallSetCount)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .fontWidth(.condensed)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 32, alignment: .leading)
                }
                .foregroundStyle(SummitWidgetStyle.primary)
            } compactTrailing: {
                IslandTimerText(
                    attributes: context.attributes,
                    state: context.state,
                    size: 16
                )
                .foregroundStyle(SummitWidgetStyle.primary)
                .frame(width: 44, alignment: .trailing)
            } minimal: {
                WorkoutProgressRing(
                    completedSetCount: context.state.completedSetCount,
                    setCount: context.state.overallSetCount
                )
                .frame(width: 26, height: 26)
            }
            .keylineTint(SummitWidgetStyle.primary)
        }
    }
}

private enum SummitWidgetStyle {
    static let black = Color.black
    static let card = Color(red: 0.118, green: 0.118, blue: 0.125)
    static let primary = Color(red: 0.961, green: 0.961, blue: 0.969)
    static let secondary = Color(red: 0.596, green: 0.596, blue: 0.616)
    static let quiet = Color(red: 0.388, green: 0.388, blue: 0.400)
    static let alpenglow = Color(red: 1.0, green: 0.612, blue: 0.478)
}

private struct WorkoutLockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    SummitMountainGlyph()
                        .stroke(SummitWidgetStyle.primary, lineWidth: 1.5)
                        .frame(width: 20, height: 16)
                    Text("\(attributes.sessionTitle.uppercased()) · \(elapsedMinutes) MIN")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .fontWidth(.condensed)
                        .monospacedDigit()
                        .tracking(1.3)
                        .foregroundStyle(SummitWidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 4)
                MetresLabel(metres: state.metresGained, size: 15)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.exerciseName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SummitWidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 4) {
                        Text("Set \(state.setIndexInExercise) of \(state.setsInExercise) · next")
                            .fontWidth(.condensed)
                            .monospacedDigit()
                            .foregroundStyle(SummitWidgetStyle.secondary)
                        if let prescription = nextPrescription {
                            Text(prescription)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .fontWidth(.condensed)
                                .monospacedDigit()
                                .foregroundStyle(SummitWidgetStyle.primary)
                        }
                    }
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(activeRestEnd == nil ? "ELAPSED" : "REST")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .fontWidth(.condensed)
                        .tracking(1.3)
                        .foregroundStyle(SummitWidgetStyle.secondary)
                    Group {
                        if let activeRestEnd {
                            Text(timerInterval: Date.now...activeRestEnd, countsDown: true)
                        } else {
                            Text(elapsedDurationText(activeElapsedSeconds(attributes: attributes, state: state, now: .now)))
                        }
                    }
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .fontWidth(.condensed)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(SummitWidgetStyle.primary)
                    .frame(width: 116, alignment: .trailing)
                }
            }

            WorkoutTrailView(
                completedSetCount: state.completedSetCount,
                currentSetIndex: state.overallSetIndex,
                setCount: state.overallSetCount
            )
            .frame(height: 24)

            HStack {
                Text("SET \(state.overallSetIndex) OF \(state.overallSetCount)")
                Spacer()
                Text("\(state.exercisesLeft) EXERCISES LEFT")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .fontWidth(.condensed)
            .monospacedDigit()
            .tracking(1.2)
            .foregroundStyle(SummitWidgetStyle.quiet)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SummitWidgetStyle.card, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var elapsedMinutes: Int {
        activeElapsedSeconds(attributes: attributes, state: state, now: .now) / 60
    }

    private var activeRestEnd: Date? {
        guard let restEndsAt = state.restEndsAt,
              activityDeadlineIsLive(restEndsAt, now: .now, isStale: isStale) else { return nil }
        return restEndsAt
    }

    private var nextPrescription: String? {
        let weight = state.nextWeightKg.map {
            formattedWeight($0, unitSystem: state.unitSystem)
        }
        let reps = state.nextReps.map(String.init)

        switch (weight, reps) {
        case let (weight?, reps?): return "\(weight) × \(reps)"
        case let (weight?, nil): return weight
        case let (nil, reps?): return "\(reps) REPS"
        case (nil, nil): return nil
        }
    }
}

private struct ExpandedIslandHeader: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let pr: WorkoutActivityAttributes.PRFlash?
    let restEndsAt: Date?

    var body: some View {
        if let pr {
            HStack(spacing: 6) {
                SummitFlagGlyph()
                    .stroke(SummitWidgetStyle.alpenglow, lineWidth: 1.8)
                    .frame(width: 14, height: 21)
                VStack(alignment: .leading, spacing: 1) {
                    Text("NEW PR FLAG")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .fontWidth(.condensed)
                        .tracking(0.8)
                        .foregroundStyle(SummitWidgetStyle.alpenglow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(pr.exerciseName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SummitWidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 7) {
                SummitMountainGlyph()
                    .stroke(SummitWidgetStyle.primary, lineWidth: 1.5)
                    .frame(width: 18, height: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attributes.sessionTitle.uppercased())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 3) {
                        if let restEndsAt {
                            Text("REST")
                            Text(timerInterval: Date.now...restEndsAt, countsDown: true)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        } else {
                            Text("\(activeElapsedSeconds(attributes: attributes, state: state, now: .now) / 60) MIN")
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(SummitWidgetStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .fontWidth(.condensed)
                .tracking(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(SummitWidgetStyle.primary)
        }
    }
}

private struct ExpandedIslandTrailing: View {
    let state: WorkoutActivityAttributes.ContentState
    let pr: WorkoutActivityAttributes.PRFlash?

    var body: some View {
        if let pr {
            Text("\(formattedWeight(pr.weightKg, unitSystem: state.unitSystem)) × \(pr.reps)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .fontWidth(.condensed)
                .monospacedDigit()
                .foregroundStyle(SummitWidgetStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            MetresLabel(
                metres: state.metresGained,
                size: 12,
                minimumScaleFactor: 0.75
            )
            .padding(.trailing, 12)
        }
    }
}

private struct ExpandedIslandContent: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let pr: WorkoutActivityAttributes.PRFlash?

    var body: some View {
        if pr != nil {
            VStack(spacing: 8) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 0.5)
                HStack {
                    Text("PERSONAL RECORD")
                        .foregroundStyle(SummitWidgetStyle.secondary)
                        .lineLimit(1)
                    Spacer()
                    MetresLabel(metres: state.metresGained, size: 12)
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .fontWidth(.condensed)
                .tracking(1.2)
                .padding(.horizontal, 4)
            }
            .padding(.top, 8)
        } else {
            ExpandedWorkoutProgressView(
                attributes: attributes,
                state: state
            )
        }
    }
}

private struct ExpandedWorkoutProgressView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 6) {
            Text(state.exerciseName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SummitWidgetStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("SET \(state.setIndexInExercise) OF \(state.setsInExercise)")
                Spacer()
                if let prescription = nextPrescription {
                    Text("NEXT \(prescription)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(SummitWidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .fontWidth(.condensed)
            .monospacedDigit()
            .tracking(0.8)
            .foregroundStyle(SummitWidgetStyle.secondary)
            // The trail's end flag rises into this row's trailing corner;
            // keep the prescription clear of it without adding height.
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity)

            WorkoutTrailView(
                completedSetCount: state.completedSetCount,
                currentSetIndex: state.overallSetIndex,
                setCount: state.overallSetCount
            )
            .frame(height: 25)

            HStack {
                Text("SET \(state.overallSetIndex) OF \(state.overallSetCount)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Text("\(state.exercisesLeft) EXERCISES LEFT")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .fontWidth(.condensed)
            .monospacedDigit()
            .tracking(1)
            .foregroundStyle(SummitWidgetStyle.quiet)
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
    }

    private var nextPrescription: String? {
        let weight = state.nextWeightKg.map { formattedWeight($0, unitSystem: state.unitSystem) }
        let reps = state.nextReps.map(String.init)
        switch (weight, reps) {
        case let (weight?, reps?): return "\(weight) × \(reps)"
        case let (weight?, nil): return weight
        case let (nil, reps?): return "\(reps) REPS"
        case (nil, nil): return nil
        }
    }
}

private struct IslandTimerText: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if let restEndsAt = activeRestEnd {
                Text(timerInterval: Date.now...restEndsAt, countsDown: true)
            } else if state.pausedAt != nil {
                Text(elapsedDurationText(activeElapsedSeconds(attributes: attributes, state: state, now: .now)))
            } else {
                Text(elapsedStart, style: .timer)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .fontWidth(.condensed)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var activeRestEnd: Date? {
        guard let restEndsAt = state.restEndsAt, restEndsAt > .now else { return nil }
        return restEndsAt
    }

    private var elapsedStart: Date {
        let now = Date.now
        let shiftedStart = attributes.startedAt.addingTimeInterval(TimeInterval(state.accumulatedPausedSeconds))
        return min(shiftedStart, now)
    }
}

private struct MetresLabel: View {
    let metres: Int
    let size: CGFloat
    let minimumScaleFactor: CGFloat

    init(metres: Int, size: CGFloat, minimumScaleFactor: CGFloat = 1) {
        self.metres = metres
        self.size = size
        self.minimumScaleFactor = minimumScaleFactor
    }

    var body: some View {
        Text("▲ +\(metres) M")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .fontWidth(.condensed)
            .monospacedDigit()
            .foregroundStyle(SummitWidgetStyle.alpenglow)
            .lineLimit(1)
            .minimumScaleFactor(minimumScaleFactor)
    }
}

private struct WorkoutProgressRing: View {
    let completedSetCount: Int
    let setCount: Int

    private var progress: CGFloat {
        let total = max(1, setCount)
        let completed = min(total, max(0, completedSetCount))
        return CGFloat(completed) / CGFloat(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(SummitWidgetStyle.quiet.opacity(0.8), lineWidth: 2.4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    SummitWidgetStyle.primary,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            SummitMountainGlyph()
                .stroke(SummitWidgetStyle.primary, lineWidth: 1.2)
                .frame(width: 12, height: 10)
        }
    }
}

private struct WorkoutTrailView: View {
    let completedSetCount: Int
    let currentSetIndex: Int
    let setCount: Int

    var body: some View {
        Canvas { context, size in
            guard setCount > 0 else { return }
            let total = max(1, setCount)
            let completed = min(total, max(0, completedSetCount))
            let current = min(total - 1, max(0, currentSetIndex - 1))
            let lastX = max(6, size.width - 24)

            func point(_ index: Int) -> CGPoint {
                let fraction = total == 1 ? 0 : CGFloat(index) / CGFloat(total - 1)
                let x = 6 + fraction * (lastX - 6)
                let easedFraction = CGFloat(pow(Double(fraction), 1.3))
                let wobble = CGFloat(sin(Double(index) * 1.7)) * 1.8
                let y = 24 - easedFraction * 16 + wobble
                return CGPoint(x: x, y: y)
            }

            var completedPath = Path()
            for index in 0..<max(1, completed) {
                if index == 0 {
                    completedPath.move(to: point(index))
                } else {
                    completedPath.addLine(to: point(index))
                }
            }
            if completed > 1 {
                context.stroke(completedPath, with: .color(SummitWidgetStyle.primary), lineWidth: 1.6)
            }

            var remainingPath = Path()
            remainingPath.move(to: point(current))
            if completed < total {
                for index in (current + 1)..<total {
                    remainingPath.addLine(to: point(index))
                }
            }
            let last = point(total - 1)
            let flagPoleX = min(size.width - 10, last.x + 12)
            let flagBase = CGPoint(x: flagPoleX, y: last.y - 2)
            if completed < total {
                remainingPath.addLine(to: flagBase)
                context.stroke(
                    remainingPath,
                    with: .color(SummitWidgetStyle.quiet),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 4])
                )
            }

            for index in 0..<completed {
                let center = point(index)
                let dot = CGRect(x: center.x - 2.6, y: center.y - 2.6, width: 5.2, height: 5.2)
                context.fill(Path(ellipseIn: dot), with: .color(SummitWidgetStyle.primary))
            }

            for index in min(total, completed + 1)..<total {
                let center = point(index)
                let dot = CGRect(x: center.x - 2.6, y: center.y - 2.6, width: 5.2, height: 5.2)
                context.fill(Path(ellipseIn: dot), with: .color(SummitWidgetStyle.card))
                context.stroke(Path(ellipseIn: dot), with: .color(SummitWidgetStyle.secondary), lineWidth: 1.1)
            }

            if completed < total {
                let currentPoint = point(current)
                let currentRing = CGRect(x: currentPoint.x - 6, y: currentPoint.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: currentRing), with: .color(SummitWidgetStyle.card))
                context.stroke(Path(ellipseIn: currentRing), with: .color(SummitWidgetStyle.primary), lineWidth: 1.8)
            }

            var flag = Path()
            flag.move(to: CGPoint(x: flagPoleX, y: last.y - 18))
            flag.addLine(to: flagBase)
            flag.move(to: CGPoint(x: flagPoleX, y: last.y - 18))
            flag.addLine(to: CGPoint(x: min(size.width - 1, flagPoleX + 9), y: last.y - 14.5))
            flag.addLine(to: flagBase)
            context.stroke(flag, with: .color(SummitWidgetStyle.secondary), lineWidth: 1.1)
        }
        .accessibilityHidden(true)
    }
}

private struct SummitMountainGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.23))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.5, y: rect.minY + rect.height * 0.61))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.67, y: rect.minY + rect.height * 0.10))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SummitFlagGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let poleX = rect.minX + rect.width * 0.12
        path.move(to: CGPoint(x: poleX, y: rect.minY))
        path.addLine(to: CGPoint(x: poleX, y: rect.maxY))
        path.move(to: CGPoint(x: poleX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.23))
        path.addLine(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.47))
        return path
    }
}

private func formattedWeight(_ weightKg: Double, unitSystem: String) -> String {
    let isImperial = unitSystem == "imperial"
    let value = isImperial ? weightKg * 2.2046226218 : weightKg
    let unit = isImperial ? "LB" : "KG"
    return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
}

private func activeElapsedSeconds(
    attributes: WorkoutActivityAttributes,
    state: WorkoutActivityAttributes.ContentState,
    now: Date
) -> Int {
    let runningUntil = state.pausedAt ?? now
    return max(0, Int(runningUntil.timeIntervalSince(attributes.startedAt)) - state.accumulatedPausedSeconds)
}

private func elapsedDurationText(_ seconds: Int) -> String {
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainder = seconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    }
    return String(format: "%d:%02d", minutes, remainder)
}

// Staleness wakes this configuration at the earliest deadline; test each value's
// own date so an expired PR does not hide a rest timer that is still active.
private func activityDeadlineIsLive(_ deadline: Date, now: Date, isStale: Bool) -> Bool {
    if isStale && deadline <= now {
        return false
    }
    return deadline > now
}

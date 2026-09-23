import SwiftUI

enum WorkoutPreviewExerciseOrderCoordinateSpace {
    static let name = "workout-preview-exercise-order-coordinate-space"
}

struct WorkoutPreviewExerciseRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

enum WorkoutPreviewExerciseDropEdge: Equatable {
    case before
    case after
}

struct WorkoutPreviewExerciseRowFramePublisher: ViewModifier {
    let exerciseID: UUID
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WorkoutPreviewExerciseRowFramePreferenceKey.self,
                        value: [
                            exerciseID: proxy.frame(
                                in: .named(WorkoutPreviewExerciseOrderCoordinateSpace.name)
                            )
                        ]
                    )
                }
            }
        } else {
            content
        }
    }
}

private struct WorkoutPreviewExerciseDropTargetStyle: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let edge: WorkoutPreviewExerciseDropEdge?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .before ? .top : .bottom) {
                if edge != nil {
                    HStack(spacing: 0) {
                        Circle()
                            .fill(appTheme.colors.accent)
                            .frame(width: 7, height: 7)

                        Capsule()
                            .fill(appTheme.colors.accent)
                            .frame(height: 2.5)
                    }
                    .padding(.horizontal, 14)
                    .offset(y: edge == .before ? -1.5 : 1.5)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
            .animation(AppMotion.previewReorderTarget(reduceMotion: reduceMotion), value: edge)
    }
}

private struct WorkoutPreviewExerciseDragStyle: ViewModifier {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let isDragging: Bool
    let verticalOffset: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: appTheme.metrics.compactCardRadius,
            style: .continuous
        )

        content
            .background {
                if isDragging {
                    shape
                        .fill(appTheme.cardBackground)
                        .overlay {
                            shape.stroke(appTheme.colors.accent.opacity(0.48), lineWidth: 1.5)
                        }
                }
            }
            .scaleEffect(isDragging && !reduceMotion ? 1.012 : 1)
            .shadow(
                color: isDragging
                    ? Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16)
                    : .clear,
                radius: isDragging ? 14 : 0,
                x: 0,
                y: isDragging ? 8 : 0
            )
            .opacity(isDragging ? 0.98 : 1)
            .zIndex(isDragging ? 2 : 0)
            .animation(AppMotion.previewReorderLift(reduceMotion: reduceMotion), value: isDragging)
            // Keep the live finger offset outside the lift animation. The
            // pickup can settle visually without making the lifted row lag
            // behind the next drag update.
            .offset(y: verticalOffset)
    }
}

private struct WorkoutPreviewTrailStopRow<Detail: View, Trailing: View>: View {
    @Environment(\.appTheme) private var appTheme
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var detailSize: CGFloat = 12.5

    let title: String
    let titleAccessibilityIdentifier: String
    private let detail: Detail
    private let trailing: Trailing

    init(
        title: String,
        titleAccessibilityIdentifier: String,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.titleAccessibilityIdentifier = titleAccessibilityIdentifier
        self.detail = detail()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(titleAccessibilityIdentifier)

                detail
                    .font(.system(size: detailSize, weight: .regular))
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Circle()
                .fill(appTheme.colors.backgroundPrimary)
                .overlay {
                    Circle().stroke(appTheme.colors.textSecondary, lineWidth: 1.3)
                }
                .frame(width: 7, height: 7)
                .offset(x: -27.5)
                .accessibilityHidden(true)
        }
    }
}

struct WorkoutPreviewExerciseCard: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var guideEntry: ExerciseGuideEntry?
    @State private var isGestureDragging = false
    @State private var gestureVerticalOffset: CGFloat = 0
    @State private var isGestureEnding = false
    @GestureState private var isGestureActive = false

    let exercise: PlannedWorkoutExercise
    let suggestion: TargetSuggestion
    let requestSubstitute: () -> Void
    let moveToTop: () -> Void
    let moveToBottom: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    let canMoveToTop: Bool
    let canMoveToBottom: Bool
    let position: Int
    let totalCount: Int
    let tracksReorderFrame: Bool
    let gestureDropEdge: WorkoutPreviewExerciseDropEdge?
    let updateGestureDropTarget: (CGPoint) -> Void
    let finishGestureDrop: (CGPoint) -> Void
    let cancelGestureDrop: () -> Void

    var body: some View {
        WorkoutPreviewTrailStopRow(
            title: exercise.exerciseNameSnapshot,
            titleAccessibilityIdentifier: "workout-preview-exercise-name-\(exercise.exerciseNameSnapshot)"
        ) {
            exerciseDetails
        } trailing: {
            HStack(spacing: 0) {
                reorderHandle
                actionsButton
            }
        }
        .contentShape(Rectangle())
        .modifier(
            WorkoutPreviewExerciseRowFramePublisher(
                exerciseID: exercise.id,
                isEnabled: tracksReorderFrame
            )
        )
        .modifier(WorkoutPreviewExerciseDropTargetStyle(edge: gestureDropEdge))
        .modifier(
            WorkoutPreviewExerciseDragStyle(
                isDragging: isGestureDragging,
                verticalOffset: gestureVerticalOffset
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-preview-exercise-row-\(exercise.exerciseNameSnapshot)")
        .sheet(item: $guideEntry) { entry in
            ExerciseGuideSheet(entry: entry)
        }
    }

    private var exerciseDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    setRepSummary
                    TrailSignTag(text: CoachBadgeState(recommendationType: suggestion.recommendationType).label)
                }

                VStack(alignment: .leading, spacing: 6) {
                    setRepSummary
                    TrailSignTag(text: CoachBadgeState(recommendationType: suggestion.recommendationType).label)
                }
            }

            targetSummary

            Text(suggestion.reason)
                .font(AppTypography.body)
                .foregroundStyle(appTheme.mutedText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let notes = exercise.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(notes, systemImage: "note.text")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setRepSummary: some View {
        Text(
            PeaklineText.setRepSummary(
                sets: exercise.targetSets,
                minimumReps: exercise.minReps,
                maximumReps: exercise.maxReps
            )
        )
        .modifier(AppTypography.instrumentValue)
        .foregroundStyle(appTheme.colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var reorderHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(AppTypography.compactCardTitle)
            .foregroundStyle(isGestureDragging ? appTheme.colors.accent : appTheme.colors.textSecondary)
            .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
            .background(
                isGestureDragging ? appTheme.colors.accentSurfaceStrong : appTheme.elevatedCardBackground,
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        appTheme.colors.accent.opacity(isGestureDragging ? 0.42 : 0),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isGestureDragging && !reduceMotion ? 1.08 : 1)
            .animation(AppMotion.previewReorderLift(reduceMotion: reduceMotion), value: isGestureDragging)
            .contentShape(Circle())
            .highPriorityGesture(
                LongPressGesture(
                    minimumDuration: AppMotion.Duration.micro.seconds,
                    maximumDistance: 10
                )
                .sequenced(before: DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named(WorkoutPreviewExerciseOrderCoordinateSpace.name)
                ))
                .updating($isGestureActive) { value, isActive, _ in
                    if case .second = value {
                        isActive = true
                    }
                }
                .onChanged { value in
                    guard case let .second(pressRecognized, dragValue) = value, pressRecognized else { return }

                    if !isGestureDragging {
                        isGestureEnding = false
                        isGestureDragging = true
                        AppHaptics.prepareSelection()
                        AppHaptics.lightImpact()
                    }
                    guard let dragValue else { return }
                    AppMotion.withoutAnimation {
                        gestureVerticalOffset = dragValue.translation.height
                    }
                    updateGestureDropTarget(dragValue.location)
                }
                .onEnded { value in
                    guard
                        case let .second(true, dragValue?) = value,
                        isGestureDragging,
                        !isGestureEnding
                    else {
                        if isGestureDragging {
                            resetCancelledGesture()
                        } else {
                            cancelGestureDrop()
                        }
                        return
                    }

                    isGestureEnding = true
                    withAnimation(AppMotion.previewReorderCommit(reduceMotion: reduceMotion)) {
                        finishGestureDrop(dragValue.location)
                        gestureVerticalOffset = 0
                        isGestureDragging = false
                    }
                }
            )
            .onChange(of: isGestureActive) { wasActive, isActive in
                guard wasActive, !isActive, isGestureDragging, !isGestureEnding else { return }

                // A scroll handoff or disappearing gesture has no onEnded
                // callback. Restore both local lift state and the parent's
                // insertion cue when that cancellation path occurs.
                resetCancelledGesture()
            }
            .accessibilityLabel("Reorder \(exercise.exerciseNameSnapshot)")
            .accessibilityValue("Position \(position) of \(totalCount)")
            .accessibilityHint("Press and hold briefly, then drag up or down and release when the insertion line appears, or use Move Up and Move Down actions")
            .accessibilityIdentifier("workout-preview-reorder-handle")
            .accessibilityActions {
                if canMoveToTop {
                    Button("Move Up") {
                        moveUp()
                    }
                }

                if canMoveToBottom {
                    Button("Move Down") {
                        moveDown()
                    }
                }
            }
    }

    private func resetCancelledGesture() {
        guard !isGestureEnding else { return }

        isGestureEnding = true
        withAnimation(AppMotion.previewReorderCommit(reduceMotion: reduceMotion)) {
            cancelGestureDrop()
            gestureVerticalOffset = 0
            isGestureDragging = false
        }
    }

    private var actionsButton: some View {
        Menu {
            if let entry = ExerciseIconMapper.guideEntry(forName: exercise.exerciseNameSnapshot) {
                Button {
                    guideEntry = entry
                } label: {
                    Label("Exercise Guide", systemImage: "info.circle")
                }
                .accessibilityIdentifier("workout-preview-exercise-guide")
            }

            Button {
                requestSubstitute()
            } label: {
                Label("Choose Substitute", systemImage: "arrow.triangle.2.circlepath")
            }

            Button {
                moveToTop()
            } label: {
                Label("Move to Top", systemImage: "arrow.up.to.line")
            }
            .disabled(!canMoveToTop)

            Button {
                moveToBottom()
            } label: {
                Label("Move to Bottom", systemImage: "arrow.down.to.line")
            }
            .disabled(!canMoveToBottom)

            Divider()

            Button(role: .destructive) {
                remove()
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(AppTypography.compactCardTitle)
                .foregroundStyle(appTheme.colors.textSecondary)
                .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                .background(appTheme.elevatedCardBackground, in: Circle())
        }
        .accessibilityLabel("Actions for \(exercise.exerciseNameSnapshot)")
        .accessibilityIdentifier("workout-preview-exercise-actions")
    }

    private var targetSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            if let lastBest = suggestion.lastBestSetDescription {
                instrumentTarget(label: "Last", value: lastBest)
            }

            instrumentTarget(label: "Target", value: targetDescription)
        }
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func instrumentTarget(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .modifier(AppTypography.waypointLabelSmall)
                .foregroundStyle(appTheme.colors.textSecondary)

            Text(value)
                .modifier(AppTypography.instrumentValue)
                .foregroundStyle(label == "Target" ? appTheme.colors.textPrimary : appTheme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targetDescription: String {
        switch (suggestion.suggestedWeight, suggestion.suggestedReps) {
        case let (.some(weight), .some(reps)):
            return PeaklineText.loadReps(weight: format(weight), reps: reps)
        case let (.some(weight), .none):
            return "\(format(weight)) kg"
        case let (.none, .some(reps)):
            return "\(reps)+ reps"
        case (.none, .none):
            return "Log sets"
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

#Preview("Workout exercise stop · Light") {
    TrailPage {
        TrailSection(index: 1, label: "Exercise Order") {
            WorkoutPreviewTrailStopRow(
                title: "Barbell Bench Press",
                titleAccessibilityIdentifier: "workout-preview-exercise-name-Barbell Bench Press"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("4 sets · 6–8 reps")
                            .modifier(AppTypography.instrumentValue)
                        TrailSignTag(text: "Increase")
                    }
                    Text("Target: 62.5 kg × 8")
                        .modifier(AppTypography.instrumentValue)
                    Text("A small load increase fits your recent working sets.")
                        .font(AppTypography.body)
                    Text("Pause briefly on each rep.")
                        .font(AppTypography.metadata)
                }
            } trailing: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
        }
    }
    .padding(.horizontal, 20)
    .preferredColorScheme(.light)
}

#Preview("Workout exercise stop · Dark") {
    TrailPage {
        TrailSection(index: 1, label: "Exercise Order") {
            WorkoutPreviewTrailStopRow(
                title: "Barbell Bench Press",
                titleAccessibilityIdentifier: "workout-preview-exercise-name-Barbell Bench Press"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("4 sets · 6–8 reps")
                            .modifier(AppTypography.instrumentValue)
                        TrailSignTag(text: "Increase")
                    }
                    Text("Target: 62.5 kg × 8")
                        .modifier(AppTypography.instrumentValue)
                    Text("A small load increase fits your recent working sets.")
                        .font(AppTypography.body)
                    Text("Pause briefly on each rep.")
                        .font(AppTypography.metadata)
                }
            } trailing: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
            }
        }
    }
    .padding(.horizontal, 20)
    .preferredColorScheme(.dark)
}

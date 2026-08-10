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
            .offset(y: reduceMotion ? 0 : verticalOffset)
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
    }
}

struct WorkoutPreviewExerciseCard: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isGestureDragging = false
    @State private var gestureVerticalOffset: CGFloat = 0

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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(forName: exercise.exerciseNameSnapshot),
                size: 44,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(exercise.exerciseNameSnapshot)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("workout-preview-exercise-name-\(exercise.exerciseNameSnapshot)")

                    Spacer(minLength: 8)

                    reorderHandle

                    actionsButton
                }

                CoachBadgeView(recommendationType: suggestion.recommendationType)

                Text(
                    PeaklineText.setRepSummary(
                        sets: exercise.targetSets,
                        minimumReps: exercise.minReps,
                        maximumReps: exercise.maxReps
                    )
                )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appTheme.colors.textSecondary)

                targetSummary

                Text(suggestion.reason)
                    .font(.footnote)
                    .foregroundStyle(appTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let notes = exercise.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(notes, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private var reorderHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.headline.weight(.semibold))
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
                DragGesture(
                    minimumDistance: 4,
                    coordinateSpace: .named(WorkoutPreviewExerciseOrderCoordinateSpace.name)
                )
                .onChanged { value in
                    if !isGestureDragging {
                        isGestureDragging = true
                        AppHaptics.prepareSelection()
                        AppHaptics.lightImpact()
                    }
                    AppMotion.withoutAnimation {
                        gestureVerticalOffset = value.translation.height
                    }
                    updateGestureDropTarget(value.location)
                }
                .onEnded { value in
                    withAnimation(AppMotion.previewReorderCommit(reduceMotion: reduceMotion)) {
                        finishGestureDrop(value.location)
                        gestureVerticalOffset = 0
                        isGestureDragging = false
                    }
                }
            )
            .accessibilityLabel("Reorder \(exercise.exerciseNameSnapshot)")
            .accessibilityValue("Position \(position) of \(totalCount)")
            .accessibilityHint("Drag up or down and release when the insertion line appears, or use Move Up and Move Down actions")
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

    private var actionsButton: some View {
        Menu {
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
                .font(.headline.weight(.semibold))
                .foregroundStyle(appTheme.colors.textSecondary)
                .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                .background(appTheme.elevatedCardBackground, in: Circle())
        }
        .accessibilityLabel("Actions for \(exercise.exerciseNameSnapshot)")
        .accessibilityIdentifier("workout-preview-exercise-actions")
    }

    private var targetSummary: some View {
        HStack(spacing: 6) {
            if let lastBest = suggestion.lastBestSetDescription {
                Text("Last: \(lastBest)")
                    .foregroundStyle(appTheme.colors.textSecondary)

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(appTheme.colors.textTertiary)
            }

            Text("Target: \(targetDescription)")
                .foregroundStyle(appTheme.colors.textPrimary)
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
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

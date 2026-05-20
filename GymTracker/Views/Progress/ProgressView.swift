import Charts
import SwiftData
import SwiftUI

struct ProgressView: View {
    var body: some View {
        NavigationStack {
            ProgressContentView()
        }
    }
}

struct ProgressContentView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    private let analytics = TrainingAnalyticsService()

    private var weeklySummary: WeeklyTrainingSummary {
        analytics.weeklySummary(from: completedSessions)
    }

    private var splitConsistency: SplitConsistencySummary {
        analytics.splitConsistency(from: completedSessions)
    }

    var body: some View {
        FitnessScreen(
            title: "Progress",
            subtitle: "Lift trends, PRs, and weekly training balance.",
            systemImage: "chart.xyaxis.line"
        ) {
            DashboardSection(title: "This Week") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            MetricTile(label: "Workouts", value: "\(weeklySummary.completedWorkouts)", caption: "Completed", systemImage: "figure.strengthtraining.traditional")
                            MetricTile(label: "Sets", value: "\(weeklySummary.workingSets)", caption: "Working", systemImage: "checkmark.circle")
                        }
                        HStack(spacing: 10) {
                            MetricTile(label: "Best-set vol", value: format(weeklySummary.bestSetVolumeTotal), caption: "kg total", systemImage: "chart.bar")
                            MetricTile(label: "Tonnage", value: format(weeklySummary.totalTonnage), caption: "kg total", systemImage: "sum")
                        }
                        Text("Push \(splitConsistency.pushCount) - Pull \(splitConsistency.pullCount) - Legs \(splitConsistency.legsCount). \(splitConsistency.balanceDescription)")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            DashboardSection(title: "Progress Charts") {
                if exercises.isEmpty {
                    DashboardEmptyStateCard(
                        title: "More data needed",
                        message: "Add exercises and finish workouts to unlock progress charts.",
                        systemImage: "chart.xyaxis.line"
                    )
                } else {
                    HStack(spacing: 12) {
                        NavigationLink {
                            ExerciseProgressChartsIndexView(exercises: exercises, sessions: completedSessions)
                        } label: {
                            ProgressActionCard(title: "Exercise Charts", subtitle: "Open lazy-loaded trends", systemImage: "chart.xyaxis.line")
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            PRTimelineView()
                        } label: {
                            ProgressActionCard(title: "PR Timeline", subtitle: "Review best-set jumps", systemImage: "trophy.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            DashboardSection(title: "Exercises") {
                if exercises.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No exercises yet",
                        message: "Create split exercises to build a progress dashboard.",
                        systemImage: "dumbbell"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(exercises) { exercise in
                            NavigationLink {
                                ExerciseProgressDetailView(exercise: exercise, sessions: completedSessions)
                            } label: {
                                FitnessCard(padding: 16) {
                                    HStack(spacing: 12) {
                                        ExerciseIconView(
                                            iconKey: ExerciseIconMapper.iconKey(for: exercise),
                                            size: 40,
                                            showBackground: true,
                                            isDecorative: true
                                        )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(exercise.name)
                                                .font(.headline)
                                                .foregroundStyle(appTheme.colors.textPrimary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                            Text(exercise.primaryMuscleGroup.displayName)
                                                .font(.subheadline)
                                                .foregroundStyle(appTheme.colors.textSecondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(appTheme.colors.textTertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Progress")
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

private struct ProgressActionCard: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(appTheme.colors.accent)
                .frame(width: 38, height: 38)
                .background(appTheme.colors.accentSurface, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(appTheme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
    }
}

private struct ExerciseProgressDetailView: View {
    let exercise: Exercise
    let sessions: [WorkoutSession]

    private var entries: [ExerciseProgressEntry] {
        sessions.compactMap { session in
            guard let exerciseLog = session.exerciseLogs.first(where: { $0.exerciseId == exercise.id }) else {
                return nil
            }

            let sets = exerciseLog.setLogs
                .filter { $0.completed && !$0.isWarmup }
                .sorted { $0.setNumber < $1.setNumber }

            guard !sets.isEmpty else { return nil }
            return ExerciseProgressEntry(session: session, sets: sets)
        }
    }

    var body: some View {
        FitnessScreen(
            title: exercise.name,
            subtitle: exercise.primaryMuscleGroup.displayName,
            systemImage: "chart.xyaxis.line"
        ) {
            if let latest = entries.first {
                DashboardSection(title: "Latest") {
                    HStack(spacing: 10) {
                        MetricTile(label: "Best set", value: latest.bestSetText, caption: nil, systemImage: "dumbbell")
                        MetricTile(label: "Est. 1RM", value: latest.estimatedOneRepMaxText, caption: nil, systemImage: "gauge.with.dots.needle.67percent")
                    }
                    HStack(spacing: 10) {
                        MetricTile(label: "Best-set vol", value: latest.bestSetVolumeText, caption: nil, systemImage: "chart.bar")
                        MetricTile(label: "Sets", value: "\(latest.completedSets)", caption: "Latest session", systemImage: "checkmark.circle")
                    }
                }
            }

            DashboardSection(title: "Chart") {
                if entries.count < 2 {
                    DashboardEmptyStateCard(
                        title: "More data needed",
                        message: "Log this exercise in at least two sessions to show a trend.",
                        systemImage: "chart.line.uptrend.xyaxis"
                    )
                } else {
                    FitnessCard {
                        ExerciseTrendChart(entries: entries.reversed())
                            .frame(height: 220)
                    }
                }
            }

            DashboardSection(title: "History") {
                if entries.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No completed working sets yet",
                        message: "Finish a set for this exercise to start its progress history.",
                        systemImage: "checkmark.circle"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(entries) { entry in
                            FitnessCard(padding: 16) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.session.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.headline)
                                    Text(entry.setsText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text("Best-set volume \(entry.bestSetVolumeText) - est. 1RM \(entry.estimatedOneRepMaxText)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
    }
}

private struct ExerciseProgressChartsIndexView: View {
    let exercises: [Exercise]
    let sessions: [WorkoutSession]

    var body: some View {
        FitnessScreen(
            title: "Progress Charts",
            subtitle: "Open one exercise at a time to keep charts fast.",
            systemImage: "chart.xyaxis.line"
        ) {
            LazyVStack(spacing: 12) {
                ForEach(exercises) { exercise in
                    NavigationLink {
                        ExerciseProgressDetailView(exercise: exercise, sessions: sessions)
                    } label: {
                        FitnessCard(padding: 16) {
                            HStack(spacing: 12) {
                                ExerciseIconView(
                                    iconKey: ExerciseIconMapper.iconKey(for: exercise),
                                    size: 40,
                                    showBackground: true,
                                    isDecorative: true
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(exercise.name)
                                        .font(.headline)
                                    Text(exercise.primaryMuscleGroup.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Progress Charts")
    }
}

private struct ExerciseTrendChart: View {
    @Environment(\.appTheme) private var appTheme
    let entries: ReversedCollection<[ExerciseProgressEntry]>

    var body: some View {
        Chart(Array(entries)) { entry in
            LineMark(
                x: .value("Date", entry.session.date),
                y: .value("Estimated 1RM", entry.estimatedOneRepMax)
            )
            .foregroundStyle(appTheme.colors.accent)

            PointMark(
                x: .value("Date", entry.session.date),
                y: .value("Estimated 1RM", entry.estimatedOneRepMax)
            )
            .foregroundStyle(appTheme.colors.accent)
        }
        .chartYAxisLabel("Est. 1RM kg")
    }
}

private struct ExerciseProgressEntry: Identifiable {
    let session: WorkoutSession
    let sets: [SetLog]

    var id: UUID {
        session.id
    }

    var completedSets: Int {
        sets.count
    }

    var bestSet: SetLog {
        sets.max { estimatedOneRepMax(for: $0) < estimatedOneRepMax(for: $1) } ?? sets[0]
    }

    var bestSetText: String {
        "\(format(bestSet.weight))kg x \(bestSet.reps)"
    }

    var estimatedOneRepMaxText: String {
        "\(format(estimatedOneRepMax))kg"
    }

    var estimatedOneRepMax: Double {
        estimatedOneRepMax(for: bestSet)
    }

    var bestSetVolumeText: String {
        "\(format(bestSetVolume))kg"
    }

    var bestSetVolume: Double {
        bestSet.weight * Double(bestSet.reps)
    }

    var setsText: String {
        sets.map { "\(format($0.weight))kg x \($0.reps)" }.joined(separator: ", ")
    }

    private func estimatedOneRepMax(for set: SetLog) -> Double {
        set.weight * (1 + Double(set.reps) / 30)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)))
    }
}

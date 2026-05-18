import SwiftData
import SwiftUI

struct SplitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \TrainingSplit.name)
    private var splits: [TrainingSplit]

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    @State private var showingAddSplit = false
    @State private var showingOtherSplits = false

    private let coachEngine = CoachRecommendationEngine()
    private let targetService = TargetSuggestionService()

    private var pplSplits: [TrainingSplit] {
        PPLRotation.names.compactMap { name in
            splits.first { $0.name == name && $0.isActive }
        }
    }

    private var otherSplits: [TrainingSplit] {
        splits.filter { !PPLRotation.names.contains($0.name) || !$0.isActive }
    }

    private var recommendedSplitName: String? {
        coachEngine.makeSummary(activeSplits: pplSplits, completedSessions: completedSessions).recommendedSplitName
    }

    private var splitStatuses: [String: SplitStatus] {
        Dictionary(uniqueKeysWithValues: pplSplits.map { split in
            (split.name, status(for: split))
        })
    }

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Splits",
                subtitle: "Manage your training programme and open each day.",
                systemImage: "list.bullet.rectangle"
            ) {
                if !pplSplits.isEmpty {
                    SplitProgrammeCard(splits: pplSplits, statuses: splitStatuses)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Training Days")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        ForEach(pplSplits) { split in
                            NavigationLink {
                                SplitDetailView(split: split)
                            } label: {
                                SplitTrainingDayCard(
                                    split: split,
                                    status: status(for: split),
                                    lastTrainedText: lastTrainedDescription(for: split),
                                    focusDescription: focusDescription(for: split)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No Active Programme")
                                .font(.headline)
                            Text("Create or activate Push, Pull, and Legs splits to build your programme dashboard.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    }
                }

                if !otherSplits.isEmpty {
                    FitnessCard(padding: 0) {
                        DisclosureGroup(isExpanded: $showingOtherSplits) {
                            VStack(spacing: 0) {
                                Text("Inactive templates are not used by today's recommendations.")
                                    .font(.footnote)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 18)
                                    .padding(.bottom, 8)

                                ForEach(otherSplits) { split in
                                    Divider()
                                        .padding(.leading, 66)

                                    NavigationLink {
                                        SplitDetailView(split: split)
                                    } label: {
                                        inactiveSplitRow(split)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            delete(split)
                                        } label: {
                                            Label("Delete Split", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 12)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Other Splits")
                                        .font(.headline)
                                        .foregroundStyle(appTheme.colors.textPrimary)
                                    Text("\(otherSplits.count) inactive or custom templates")
                                        .font(.subheadline)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                }

                                Spacer()

                                Text(showingOtherSplits ? "Hide" : "Show")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(showingOtherSplits ? appTheme.colors.accent : appTheme.colors.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(
                                        showingOtherSplits ? appTheme.colors.accentSurfaceStrong : appTheme.elevatedCardBackground,
                                        in: Capsule()
                                    )
                            }
                            .padding(18)
                        }
                    }
                }
            }
            .navigationTitle("Splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button {
                    showingAddSplit = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(appTheme.colors.accent)
                }
                .accessibilityLabel("Add split")
            }
            .sheet(isPresented: $showingAddSplit) {
                AddSplitView()
            }
        }
    }

    private func inactiveSplitRow(_ split: TrainingSplit) -> some View {
        HStack(spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                size: 36,
                tint: appTheme.colors.textSecondary,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(split.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(appTheme.colors.textPrimary)
                Text("\(split.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }

            Spacer()

            SplitStatusBadge(status: split.isActive ? .custom : .inactive)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(appTheme.colors.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func deleteOtherSplits(at offsets: IndexSet) {
        let deletableSplits = offsets.map { otherSplits[$0] }
        for split in deletableSplits {
            delete(split)
        }
    }

    private func deleteSplits(at offsets: IndexSet) {
        for index in offsets {
            delete(splits[index])
        }
    }

    private func delete(_ split: TrainingSplit) {
        modelContext.delete(split)
        try? modelContext.save()
    }

    private func status(for split: TrainingSplit) -> SplitStatus {
        guard split.isActive else { return .inactive }

        if wasTrainedRecently(split) {
            return .recentlyTrained
        }

        if isPrioritised(split) {
            return .prioritise
        }

        if hasProgressOpportunity(split) {
            return .progressOpportunity
        }

        if recommendedSplitName == split.name {
            return .ready
        }

        return PPLRotation.names.contains(split.name) ? .ready : .custom
    }

    private func wasTrainedRecently(_ split: TrainingSplit) -> Bool {
        guard let last = lastSession(for: split) else { return false }
        return Calendar.current.isDateInToday(last.date) || Calendar.current.isDateInYesterday(last.date)
    }

    private func isPrioritised(_ split: TrainingSplit) -> Bool {
        guard let last = lastSession(for: split) else { return false }
        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
        return days >= 7
    }

    private func hasProgressOpportunity(_ split: TrainingSplit) -> Bool {
        split.exercises.contains { splitExercise in
            let suggestion = targetService.suggestion(for: splitExercise, completedSessions: completedSessions)
            return suggestion.recommendationType == .increaseLoad || suggestion.recommendationType == .addReps
        }
    }

    private func lastSession(for split: TrainingSplit) -> WorkoutSession? {
        completedSessions.first { baseSplitName($0.splitNameSnapshot) == split.name }
    }

    private func lastTrainedDescription(for split: TrainingSplit) -> String {
        guard let last = lastSession(for: split) else { return "No history yet" }

        if Calendar.current.isDateInToday(last.date) {
            return "Last trained today"
        }

        if Calendar.current.isDateInYesterday(last.date) {
            return "Last trained yesterday"
        }

        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day
        if let days, days > 1, days < 14 {
            return "Last trained \(days) days ago"
        }

        return "Last trained \(last.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func focusDescription(for split: TrainingSplit) -> String {
        switch split.name {
        case "Push":
            return "Chest - Shoulders - Triceps"
        case "Pull":
            return "Back - Biceps - Rear delts"
        case "Legs":
            return "Quads - Hamstrings - Calves"
        default:
            return split.splitType.displayName
        }
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }
}

private enum PPLRotation {
    static let names = ["Push", "Pull", "Legs"]
}

private struct SplitDetailView: View {
    @Environment(\.appTheme) private var appTheme
    @Bindable var split: TrainingSplit

    @Query(filter: #Predicate<WorkoutSession> { $0.completed }, sort: \WorkoutSession.date, order: .reverse)
    private var completedSessions: [WorkoutSession]

    private let targetService = TargetSuggestionService()

    private var orderedExercises: [SplitExercise] {
        split.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        FitnessScreen {
            splitHeroCard

            VStack(alignment: .leading, spacing: 10) {
                Text("Exercises")
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)

                if orderedExercises.isEmpty {
                    FitnessCard {
                        Text("No exercises yet")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                } else {
                    FitnessCard(padding: 14) {
                        VStack(spacing: 0) {
                            ForEach(Array(orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                                if index > 0 {
                                    Divider()
                                        .padding(.leading, 50)
                                }

                                SplitExerciseRow(
                                    exercise: exercise,
                                    suggestion: targetService.suggestion(for: exercise, completedSessions: completedSessions)
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(split.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            NavigationLink {
                SplitEditorView(split: split)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }

    private var splitHeroCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ExerciseIconTile(
                        iconKey: ExerciseIconMapper.splitIconKey(for: split.name),
                        title: nil,
                        size: 68,
                        style: .compact,
                        tint: split.isActive ? appTheme.colors.accent : appTheme.colors.textSecondary
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(split.isActive ? "PPL Training Day" : "Inactive Template")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        Text(split.name)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(orderedExercises.count) exercises - \(split.daysPerWeek) days/week")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer(minLength: 0)

                    SplitStatusBadge(status: detailStatus)
                }

                HStack(spacing: 10) {
                    MetricTile(label: "Last trained", value: compactLastTrainedText, caption: nil, systemImage: "clock.arrow.circlepath")
                    MetricTile(label: "Focus", value: focusDescription, caption: split.splitType.displayName, systemImage: "scope")
                }
            }
        }
    }

    private var detailStatus: SplitStatus {
        guard split.isActive else { return .inactive }
        guard let last = lastSession else { return .ready }
        if Calendar.current.isDateInToday(last.date) || Calendar.current.isDateInYesterday(last.date) {
            return .recentlyTrained
        }
        let days = Calendar.current.dateComponents([.day], from: last.date, to: .now).day ?? 0
        return days >= 7 ? .prioritise : .ready
    }

    private var lastSession: WorkoutSession? {
        completedSessions.first { baseSplitName($0.splitNameSnapshot) == split.name }
    }

    private var compactLastTrainedText: String {
        guard let lastSession else { return "Never" }
        if Calendar.current.isDateInToday(lastSession.date) { return "Today" }
        if Calendar.current.isDateInYesterday(lastSession.date) { return "Yesterday" }
        return lastSession.date.formatted(date: .abbreviated, time: .omitted)
    }

    private var focusDescription: String {
        switch split.name {
        case "Push":
            return "Chest"
        case "Pull":
            return "Back"
        case "Legs":
            return "Legs"
        default:
            return "Custom"
        }
    }

    private func baseSplitName(_ snapshot: String) -> String {
        snapshot.components(separatedBy: " - ").first ?? snapshot
    }
}

private struct AddSplitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var splitType = SplitType.custom
    @State private var daysPerWeek = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("Split") {
                    TextField("Name", text: $name)

                    Picker("Type", selection: $splitType) {
                        ForEach(SplitType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    Stepper("Days per week: \(daysPerWeek)", value: $daysPerWeek, in: 1...7)
                }
            }
            .navigationTitle("New Split")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createSplit()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createSplit() {
        let split = TrainingSplit(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            splitType: splitType,
            daysPerWeek: daysPerWeek
        )
        modelContext.insert(split)
        try? modelContext.save()
        dismiss()
    }
}

private struct SplitEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var split: TrainingSplit

    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var selectedExerciseId: UUID?

    private var orderedExercises: [SplitExercise] {
        split.exercises.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        Form {
            Section("Split") {
                TextField("Name", text: $split.name)

                Picker("Type", selection: $split.splitType) {
                    ForEach(SplitType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                Stepper("Days per week: \(split.daysPerWeek)", value: $split.daysPerWeek, in: 1...7)
                Toggle("Active", isOn: $split.isActive)
            }

            Section("Add Exercise") {
                Picker("Exercise", selection: $selectedExerciseId) {
                    Text("Choose").tag(Optional<UUID>.none)
                    ForEach(exercises) { exercise in
                        Text(exercise.name).tag(Optional(exercise.id))
                    }
                }

                Button {
                    addSelectedExercise()
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }
                .disabled(selectedExerciseId == nil)
            }

            Section("Exercises") {
                if orderedExercises.isEmpty {
                    Text("No exercises yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedExercises) { splitExercise in
                        SplitExerciseEditorRow(splitExercise: splitExercise)
                    }
                    .onDelete(perform: deleteExercises)
                    .onMove(perform: moveExercises)
                }
            }
        }
        .navigationTitle("Edit Split")
        .toolbar {
            EditButton()
        }
        .onDisappear {
            split.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func addSelectedExercise() {
        guard
            let selectedExerciseId,
            let exercise = exercises.first(where: { $0.id == selectedExerciseId })
        else { return }

        let splitExercise = SplitExercise(
            splitId: split.id,
            exerciseId: exercise.id,
            exerciseNameSnapshot: exercise.name,
            orderIndex: orderedExercises.count,
            targetSets: 2,
            minReps: 8,
            maxReps: 12,
            restSeconds: 120,
            notes: "Use double progression: add reps inside the target range before adding load."
        )
        splitExercise.split = split
        split.exercises.append(splitExercise)
        self.selectedExerciseId = nil
        split.updatedAt = .now
        try? modelContext.save()
    }

    private func deleteExercises(at offsets: IndexSet) {
        let exercisesToDelete = offsets.map { orderedExercises[$0] }
        for exercise in exercisesToDelete {
            split.exercises.removeAll { $0.id == exercise.id }
            modelContext.delete(exercise)
        }
        renumberExercises()
        split.updatedAt = .now
        try? modelContext.save()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var reordered = orderedExercises
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in reordered.enumerated() {
            exercise.orderIndex = index
        }
        split.updatedAt = .now
        try? modelContext.save()
    }

    private func renumberExercises() {
        for (index, exercise) in orderedExercises.enumerated() {
            exercise.orderIndex = index
        }
    }
}

private struct SplitExerciseEditorRow: View {
    @Bindable var splitExercise: SplitExercise

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: splitExercise),
                size: 36,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(splitExercise.exerciseNameSnapshot)
                    .font(.headline)

                Stepper("Sets: \(splitExercise.targetSets)", value: $splitExercise.targetSets, in: 1...10)
                Stepper("Min reps: \(splitExercise.minReps)", value: $splitExercise.minReps, in: 1...50)
                Stepper("Max reps: \(splitExercise.maxReps)", value: $splitExercise.maxReps, in: max(splitExercise.minReps, 1)...50)
                Stepper("Rest: \(restText)", value: Binding($splitExercise.restSeconds, replacingNilWith: 120), in: 30...300, step: 15)
                TextField("Progression note", text: Binding($splitExercise.notes, replacingNilWith: ""), axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        .padding(.vertical, 4)
    }

    private var restText: String {
        guard let restSeconds = splitExercise.restSeconds else { return "not set" }
        return "\(restSeconds)s"
    }
}

private extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init {
            source.wrappedValue ?? fallback
        } set: { newValue in
            source.wrappedValue = newValue.isEmpty ? nil : newValue
        }
    }
}

private extension Binding where Value == Int {
    init(_ source: Binding<Int?>, replacingNilWith fallback: Int) {
        self.init {
            source.wrappedValue ?? fallback
        } set: { newValue in
            source.wrappedValue = newValue
        }
    }
}

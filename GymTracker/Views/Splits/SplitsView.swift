import SwiftData
import SwiftUI

struct SplitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query
    private var splits: [TrainingSplit]

    @Query
    private var completedSessions: [WorkoutSession]

    @State private var showingAddSplit = false
    @State private var showingOtherSplits = false
    @State private var pendingDeleteSplit: TrainingSplit?
    @State private var dashboardSnapshot = SplitsDashboardSnapshot.empty
    @State private var lastDashboardSignature: String?

    private let coachEngine = CoachRecommendationEngine()
    private let targetService = TargetSuggestionService()

    init() {
        _splits = Query(Self.splitsDescriptor)
        _completedSessions = Query(Self.completedSessionsDescriptor)
    }

    private static var splitsDescriptor: FetchDescriptor<TrainingSplit> {
        FetchDescriptor<TrainingSplit>(
            sortBy: [SortDescriptor(\.name)]
        )
    }

    private static var completedSessionsDescriptor: FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate<WorkoutSession> { $0.completed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return descriptor
    }

    private var pplSplits: [TrainingSplit] {
        currentDashboardSnapshot.pplSplits
    }

    private var otherSplits: [TrainingSplit] {
        currentDashboardSnapshot.otherSplits
    }

    private var recommendedSplitName: String? {
        currentDashboardSnapshot.recommendedSplitName
    }

    private var splitStatuses: [String: SplitStatus] {
        currentDashboardSnapshot.statusesBySplitName
    }

    var body: some View {
        let snapshot = currentDashboardSnapshot

        NavigationStack {
            FitnessScreen(
                title: "Splits",
                subtitle: "Manage your training programme and open each day.",
                systemImage: "list.bullet.rectangle"
            ) {
                if !snapshot.pplSplits.isEmpty {
                    SplitProgrammeCard(splits: snapshot.pplSplits, statuses: snapshot.statusesBySplitName)

                    DashboardSection(title: "Training Days") {
                        ForEach(snapshot.pplSplits) { split in
                            NavigationLink {
                                SplitDetailView(split: split)
                            } label: {
                                SplitTrainingDayCard(
                                    split: split,
                                    status: snapshot.statusesBySplitName[split.name] ?? .ready,
                                    lastTrainedText: snapshot.lastTrainedTextBySplitName[split.name] ?? "No history yet",
                                    focusDescription: snapshot.focusTextBySplitName[split.name] ?? focusDescription(for: split)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    DashboardEmptyStateCard(
                        title: "No active programme",
                        message: "Create or activate Push, Pull, and Legs splits to build your programme dashboard.",
                        systemImage: "list.bullet.rectangle"
                    )
                }

                if !snapshot.otherSplits.isEmpty {
                    FitnessCard(style: .compact, padding: 0) {
                        VStack(spacing: 0) {
                            Button {
                                withAnimation(AppMotion.reorderSpring(reduceMotion: reduceMotion)) {
                                    showingOtherSplits.toggle()
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Other Splits")
                                            .font(.headline)
                                            .foregroundStyle(appTheme.colors.textPrimary)
                                        Text("\(snapshot.otherSplits.count) inactive or custom templates")
                                            .font(.subheadline)
                                            .foregroundStyle(appTheme.colors.textSecondary)
                                    }

                                    Spacer(minLength: 12)

                                    Text(showingOtherSplits ? "Hide" : "Show")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(showingOtherSplits ? appTheme.colors.accent : appTheme.colors.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(
                                            showingOtherSplits ? appTheme.colors.accentSurfaceStrong : appTheme.elevatedCardBackground,
                                            in: Capsule()
                                        )

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(appTheme.colors.textTertiary)
                                        .rotationEffect(.degrees(showingOtherSplits ? 90 : 0))
                                }
                                .padding(18)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showingOtherSplits ? "Hide other splits" : "Show other splits")

                            if showingOtherSplits {
                                VStack(spacing: 0) {
                                    Text("Inactive templates are not used by today's recommendations.")
                                        .font(.footnote)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 18)
                                        .padding(.bottom, 8)

                                    ForEach(snapshot.otherSplits) { split in
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
                                                pendingDeleteSplit = split
                                            } label: {
                                                Label("Delete Split", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .padding(.bottom, 12)
                            }
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
            .alert("Delete split?", isPresented: deleteAlertBinding) {
                Button("Cancel", role: .cancel) {
                    pendingDeleteSplit = nil
                }
                Button("Delete", role: .destructive) {
                    deletePendingSplit()
                }
            } message: {
                Text("This removes the split template and its exercise setup. Workout history stays intact.")
            }
        }
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                refreshDashboardSnapshot(force: true)
            }
        }
        .onChange(of: dashboardSignature) { _, _ in
            refreshDashboardSnapshot()
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding {
            pendingDeleteSplit != nil
        } set: { showing in
            if !showing {
                pendingDeleteSplit = nil
            }
        }
    }

    private var currentDashboardSnapshot: SplitsDashboardSnapshot {
        guard lastDashboardSignature != nil else {
            return dashboardSnapshot
        }

        let signature = dashboardSignature
        if signature == lastDashboardSignature {
            return dashboardSnapshot
        }

        return dashboardSnapshot
    }

    private var dashboardSignature: String {
        [
            splits.map { split in
                let exerciseSignature = split.exercises
                    .map { "\($0.id.uuidString):\($0.exerciseId.uuidString):\($0.orderIndex):\($0.targetSets):\($0.minReps):\($0.maxReps):\($0.notes ?? "")" }
                    .sorted()
                    .joined(separator: ";")
                return "\(split.id.uuidString):\(split.name):\(split.isActive):\(split.updatedAt.timeIntervalSince1970):\(exerciseSignature)"
            }
            .joined(separator: "|"),
            completedSessions.prefix(40).map { session in
                let logSignature = session.exerciseLogs
                    .map { "\($0.id.uuidString):\($0.exerciseId.uuidString):\($0.setLogs.count)" }
                    .joined(separator: ";")
                return "\(session.id.uuidString):\(session.date.timeIntervalSince1970):\(session.endedAt?.timeIntervalSince1970 ?? 0):\(logSignature)"
            }
            .joined(separator: "|")
        ].joined(separator: "||")
    }

    private func refreshDashboardSnapshot(force: Bool = false) {
        let signature = dashboardSignature
        guard force || signature != lastDashboardSignature else { return }
        dashboardSnapshot = PerformanceTracer.trace(.splitsDashboard) {
            makeDashboardSnapshot()
        }
        lastDashboardSignature = signature
    }

    private func makeDashboardSnapshot() -> SplitsDashboardSnapshot {
        let pplSplits = PPLRotation.names.compactMap { name in
            splits.first { $0.name == name && $0.isActive }
        }
        let otherSplits = splits.filter { !PPLRotation.names.contains($0.name) || !$0.isActive }
        let recommendedSplitName = coachEngine.makeSummary(activeSplits: pplSplits, completedSessions: completedSessions).recommendedSplitName
        var statusesBySplitName: [String: SplitStatus] = [:]
        var lastTrainedTextBySplitName: [String: String] = [:]
        var focusTextBySplitName: [String: String] = [:]

        for split in pplSplits {
            statusesBySplitName[split.name] = status(for: split, recommendedSplitName: recommendedSplitName)
            lastTrainedTextBySplitName[split.name] = lastTrainedDescription(for: split)
            focusTextBySplitName[split.name] = focusDescription(for: split)
        }

        return SplitsDashboardSnapshot(
            pplSplits: pplSplits,
            otherSplits: otherSplits,
            recommendedSplitName: recommendedSplitName,
            statusesBySplitName: statusesBySplitName,
            lastTrainedTextBySplitName: lastTrainedTextBySplitName,
            focusTextBySplitName: focusTextBySplitName
        )
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

    private func deletePendingSplit() {
        guard let pendingDeleteSplit else { return }
        delete(pendingDeleteSplit)
        self.pendingDeleteSplit = nil
    }

    private func status(for split: TrainingSplit) -> SplitStatus {
        status(for: split, recommendedSplitName: recommendedSplitName)
    }

    private func status(for split: TrainingSplit, recommendedSplitName: String?) -> SplitStatus {
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

private struct SplitsDashboardSnapshot {
    let pplSplits: [TrainingSplit]
    let otherSplits: [TrainingSplit]
    let recommendedSplitName: String?
    let statusesBySplitName: [String: SplitStatus]
    let lastTrainedTextBySplitName: [String: String]
    let focusTextBySplitName: [String: String]

    static let empty = SplitsDashboardSnapshot(
        pplSplits: [],
        otherSplits: [],
        recommendedSplitName: nil,
        statusesBySplitName: [:],
        lastTrainedTextBySplitName: [:],
        focusTextBySplitName: [:]
    )
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

            DashboardSection(title: "Exercises") {
                if orderedExercises.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No exercises yet",
                        message: "Add exercises to make this split useful in previews and coaching.",
                        systemImage: "dumbbell"
                    )
                } else {
                    FitnessCard(style: .compact, padding: 14) {
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
        FitnessCard(style: .hero) {
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
    @Environment(\.appTheme) private var appTheme
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
                        .foregroundStyle(appTheme.colors.textSecondary)
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
                ExerciseNotesEditor(
                    text: Binding($splitExercise.notes, replacingNilWith: ""),
                    title: "Template note",
                    placeholder: "Seat height, grip, setup cue, or progression reminder."
                )
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

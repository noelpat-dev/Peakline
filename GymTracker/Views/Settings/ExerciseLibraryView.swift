import SwiftData
import SwiftUI

struct ExerciseLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \CoachExerciseMetadata.updatedAt, order: .reverse)
    private var coachMetadata: [CoachExerciseMetadata]

    @State private var showingAddExercise = false
    @State private var showingArchived = false
    @State private var showingBulkMetadataEditor = false

    private var visibleExercises: [Exercise] {
        exercises.filter { showingArchived || !$0.isArchived }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ExerciseGuideLibraryView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Browse Exercise Guide")
                                .font(AppTypography.bodyEmphasis)
                            Text("Illustrations, equipment and muscle groups")
                                .font(AppTypography.metadata)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "figure.strengthtraining.traditional")
                    }
                }
                .accessibilityIdentifier("exercise-library-guide")
            }

            Section {
                Toggle("Show archived", isOn: $showingArchived)
            }

            Section("Exercises") {
                if visibleExercises.isEmpty {
                    Text(showingArchived ? "No exercises yet" : "No active exercises")
                        .foregroundStyle(appTheme.colors.textSecondary)
                } else {
                    ForEach(visibleExercises) { exercise in
                        NavigationLink {
                            ExerciseEditorView(exercise: exercise)
                        } label: {
                            ExerciseLibraryRow(
                                exercise: exercise,
                                metadata: coachMetadata.first { $0.exerciseId == exercise.id }
                            )
                        }
                        .accessibilityIdentifier("exercise-library-row-\(exercise.name)")
                    }
                    .onDelete(perform: archiveExercises)
                }
            }
        }
        .peaklineGroupedContent()
        .navigationTitle("Exercise Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingBulkMetadataEditor = true
                } label: {
                    Label("Bulk Coach Metadata", systemImage: "square.stack.3d.up")
                }
                .accessibilityIdentifier("bulk-metadata-open")

                Button {
                    showingAddExercise = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            AddExerciseView()
        }
        .sheet(isPresented: $showingBulkMetadataEditor) {
            BulkCoachMetadataEditorView(
                exercises: visibleExercises,
                existingMetadata: coachMetadata
            )
        }
    }

    private func archiveExercises(at offsets: IndexSet) {
        for index in offsets {
            visibleExercises[index].isArchived = true
            visibleExercises[index].updatedAt = .now
        }
        try? modelContext.save()
    }
}

private struct ExerciseLibraryRow: View {
    @Environment(\.appTheme) private var appTheme

    let exercise: Exercise
    let metadata: CoachExerciseMetadata?

    var body: some View {
        HStack(spacing: 12) {
            ExerciseIconView(
                iconKey: ExerciseIconMapper.iconKey(for: exercise),
                size: 48,
                showBackground: true,
                isDecorative: true
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(exercise.name)
                        .font(AppTypography.sectionTitle)

                    if exercise.isArchived {
                        Text("Archived")
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                Text("\(exercise.primaryMuscleGroup.displayName) - \(exercise.equipment.displayName) - \(exercise.movementPattern.displayName)")
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)

                if let metadata {
                    Text("Coach: \(metadata.role.displayName) - \(metadata.priority.displayName) priority")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AddExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var primaryMuscleGroup = MuscleGroup.chest
    @State private var secondaryMuscleGroups: [MuscleGroup] = []
    @State private var movementPattern = MovementPattern.push
    @State private var equipment = EquipmentType.barbell
    @State private var isCompound = true

    var body: some View {
        NavigationStack {
            ExerciseForm(
                name: $name,
                primaryMuscleGroup: $primaryMuscleGroup,
                secondaryMuscleGroups: $secondaryMuscleGroups,
                movementPattern: $movementPattern,
                equipment: $equipment,
                isCompound: $isCompound
            )
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createExercise()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createExercise() {
        let exercise = Exercise(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryMuscleGroup: primaryMuscleGroup,
            secondaryMuscleGroups: secondaryMuscleGroups,
            movementPattern: movementPattern,
            equipment: equipment,
            isCompound: isCompound
        )
        modelContext.insert(exercise)
        try? modelContext.save()
        dismiss()
    }
}

private struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var exercise: Exercise
    @Query private var matchingCoachMetadata: [CoachExerciseMetadata]

    @State private var coachRole = CoachExerciseMetadataRole.compound
    @State private var coachSplitClassification = CoachSplitClassification.unspecified
    @State private var coachPriority = CoachExercisePriorityLevel.normal
    @State private var coachNote = ""
    @State private var editorMetadata: CoachExerciseMetadata?
    @State private var didLoadCoachMetadata = false
    @State private var saveError: String?
    private let metadataService = CoachExerciseMetadataService()

    init(exercise: Exercise) {
        self.exercise = exercise
        let exerciseID = exercise.id
        _matchingCoachMetadata = Query(
            filter: #Predicate<CoachExerciseMetadata> { $0.exerciseId == exerciseID },
            sort: \CoachExerciseMetadata.updatedAt,
            order: .reverse
        )
    }

    private var draft: CoachExerciseMetadataDraft {
        CoachExerciseMetadataDraft(
            role: coachRole,
            primaryMuscleGroup: exercise.primaryMuscleGroup,
            secondaryMuscleGroups: exercise.secondaryMuscleGroups.filter { $0 != exercise.primaryMuscleGroup },
            movementPattern: exercise.movementPattern,
            splitClassification: coachSplitClassification,
            priority: coachPriority,
            userNote: coachNote
        )
    }

    var body: some View {
        ExerciseForm(
            name: $exercise.name,
            primaryMuscleGroup: $exercise.primaryMuscleGroup,
            secondaryMuscleGroups: $exercise.secondaryMuscleGroups,
            movementPattern: $exercise.movementPattern,
            equipment: $exercise.equipment,
            isCompound: $exercise.isCompound,
            isArchived: $exercise.isArchived,
            coachRole: $coachRole,
            coachSplitClassification: $coachSplitClassification,
            coachPriority: $coachPriority,
            coachNote: $coachNote,
            illustration: ExerciseIconMapper.illustrationEntry(for: exercise)
        )
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ExerciseArtworkCreditsView()
                } label: {
                    Label("Artwork credits", systemImage: "info.circle")
                }
                .accessibilityIdentifier("exercise-editor-credits")
            }
        }
        .onAppear { loadCoachMetadataIfNeeded() }
        .onChange(of: exercise.isCompound) { _, isCompound in
            if coachRole == .compound || coachRole == .isolation {
                coachRole = isCompound ? .compound : .isolation
            }
        }
        .onChange(of: coachRole) { _, role in
            guard didLoadCoachMetadata else { return }
            if role == .compound { exercise.isCompound = true }
            if role == .isolation { exercise.isCompound = false }
        }
        .onDisappear {
            synchronizeMetadata()
            if modelContext.hasChanges { exercise.updatedAt = .now }
            saveChanges()
        }
        .alert("Couldn't save exercise", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("Retry") { saveChanges() }
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "Please try again.")
        }
    }

    private func loadCoachMetadataIfNeeded() {
        guard !didLoadCoachMetadata else { return }
        editorMetadata = matchingCoachMetadata.first
        let initial = metadataService.editorDraft(for: exercise, metadata: editorMetadata)
        coachRole = initial.role
        coachSplitClassification = initial.splitClassification
        coachPriority = initial.priority
        coachNote = initial.userNote
        didLoadCoachMetadata = true
        synchronizeMetadata()
        saveChanges()
    }

    private func synchronizeMetadata() {
        guard didLoadCoachMetadata else { return }
        if let editorMetadata {
            if metadataService.updateIfNeeded(editorMetadata, from: draft) {
                exercise.updatedAt = .now
            }
        } else {
            let metadata = metadataService.makeMetadata(from: draft, exercise: exercise)
            modelContext.insert(metadata)
            editorMetadata = metadata
        }
    }

    private func saveChanges() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct ExerciseForm: View {
    @Binding var name: String
    @Binding var primaryMuscleGroup: MuscleGroup
    @Binding var secondaryMuscleGroups: [MuscleGroup]
    @Binding var movementPattern: MovementPattern
    @Binding var equipment: EquipmentType
    @Binding var isCompound: Bool
    var isArchived: Binding<Bool>?
    var coachRole: Binding<CoachExerciseMetadataRole>?
    var coachSplitClassification: Binding<CoachSplitClassification>?
    var coachPriority: Binding<CoachExercisePriorityLevel>?
    var coachNote: Binding<String>?
    var illustration: ExerciseGuideEntry?

    var body: some View {
        Form {
            if let illustration {
                Section {
                    ExercisePosePreview(entry: illustration, autoplay: true)
                        .id(illustration.slug)
                        .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
            }

            Section("Exercise details") {
                TextField("Name", text: $name)

                Picker("Primary muscle", selection: $primaryMuscleGroup) {
                    ForEach(MuscleGroup.allCases) { group in
                        Text(group.displayName).tag(group)
                    }
                }

                DisclosureGroup("Secondary muscles") {
                    ForEach(MuscleGroup.allCases) { group in
                        if group != primaryMuscleGroup {
                            Toggle(group.displayName, isOn: secondaryMuscleBinding(for: group))
                        }
                    }
                }

                Picker("Pattern", selection: $movementPattern) {
                    ForEach(MovementPattern.allCases) { pattern in
                        Text(pattern.displayName).tag(pattern)
                    }
                }

                Picker("Equipment", selection: $equipment) {
                    ForEach(EquipmentType.allCases) { equipment in
                        Text(equipment.displayName).tag(equipment)
                    }
                }

                Toggle("Compound lift", isOn: $isCompound)

                if
                    let coachRole,
                    let coachSplitClassification,
                    let coachPriority,
                    let coachNote
                {
                    DisclosureGroup("Coaching preferences") {
                        Picker("Role", selection: coachRole) {
                            ForEach(CoachExerciseMetadataRole.allCases) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                        .accessibilityIdentifier("coach-metadata-role")

                        Picker("Priority", selection: coachPriority) {
                            ForEach(CoachExercisePriorityLevel.allCases) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .accessibilityIdentifier("coach-metadata-priority")

                        Picker("PPL context", selection: coachSplitClassification) {
                            ForEach(CoachSplitClassification.allCases) { context in
                                Text(context.displayName).tag(context)
                            }
                        }

                        TextField("Coach context note", text: coachNote, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("coach-metadata-note")
                    }
                }
            }

            if let isArchived {
                Section("Library") {
                    Toggle("Archived", isOn: isArchived)
                }
            }
        }
        .peaklineGroupedContent()
        .peaklineKeyboardDismissal()
        .onChange(of: primaryMuscleGroup) { _, newPrimaryMuscleGroup in
            secondaryMuscleGroups.removeAll { $0 == newPrimaryMuscleGroup }
        }
    }

    private func secondaryMuscleBinding(for group: MuscleGroup) -> Binding<Bool> {
        Binding {
            secondaryMuscleGroups.contains(group)
        } set: { isSelected in
            if isSelected {
                if !secondaryMuscleGroups.contains(group) {
                    secondaryMuscleGroups.append(group)
                }
            } else {
                secondaryMuscleGroups.removeAll { $0 == group }
            }
        }
    }

}

private struct BulkCoachMetadataEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    let exercises: [Exercise]
    let existingMetadata: [CoachExerciseMetadata]

    @State private var scope = CoachBulkMetadataScope.selectedExercises
    @State private var selectedExerciseIds: Set<UUID> = []
    @State private var muscleGroup = MuscleGroup.chest
    @State private var splitClassification = CoachSplitClassification.push
    @State private var overwriteExisting = false

    @State private var applyRole = true
    @State private var role = CoachExerciseMetadataRole.accessory
    @State private var applyPriority = true
    @State private var priority = CoachExercisePriorityLevel.normal
    @State private var applyPrimaryMuscle = false
    @State private var primaryMuscleGroup = MuscleGroup.chest
    @State private var applySecondaryMuscles = false
    @State private var secondaryMuscleGroups: [MuscleGroup] = []
    @State private var applyPPL = false
    @State private var updateSplitClassification = CoachSplitClassification.push
    @State private var applyMovement = false
    @State private var movementPattern = MovementPattern.push
    @State private var review: CoachBulkMetadataReview?

    private let bulkService = CoachBulkMetadataService()
    private let metadataService = CoachExerciseMetadataService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FitnessCard(style: .hero) {
                        HStack(alignment: .top, spacing: 12) {
                            FitnessIconBadge(systemImage: "square.stack.3d.up", size: 46)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bulk Coach Metadata")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                Text("Review coach metadata updates before applying them locally.")
                                    .font(AppTypography.body)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker("Scope", selection: $scope) {
                                ForEach(CoachBulkMetadataScope.allCases) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)

                            scopeControls

                            Toggle("Overwrite existing coach metadata", isOn: $overwriteExisting)
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 14) {
                            metadataToggle("Role", isOn: $applyRole) {
                                Picker("Role", selection: $role) {
                                    ForEach(CoachExerciseMetadataRole.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                            }

                            metadataToggle("Priority", isOn: $applyPriority) {
                                Picker("Priority", selection: $priority) {
                                    ForEach(CoachExercisePriorityLevel.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                            }

                            metadataToggle("Primary muscle", isOn: $applyPrimaryMuscle) {
                                Picker("Primary muscle", selection: $primaryMuscleGroup) {
                                    ForEach(MuscleGroup.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                            }

                            metadataToggle("Secondary muscles", isOn: $applySecondaryMuscles) {
                                DisclosureGroup("Choose muscles") {
                                    ForEach(MuscleGroup.allCases) { group in
                                        Toggle(group.displayName, isOn: secondaryMuscleBinding(for: group))
                                    }
                                }
                            }

                            metadataToggle("PPL context", isOn: $applyPPL) {
                                Picker("PPL context", selection: $updateSplitClassification) {
                                    ForEach(CoachSplitClassification.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                            }

                            metadataToggle("Movement", isOn: $applyMovement) {
                                Picker("Movement", selection: $movementPattern) {
                                    ForEach(MovementPattern.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                            }

                            Button {
                                review = makeReview()
                            } label: {
                                Label("Review Changes", systemImage: "checklist")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryFitnessButtonStyle())
                            .disabled(!bulkUpdate.hasChanges)
                            .accessibilityIdentifier("bulk-metadata-review")
                        }
                    }

                    if let review {
                        reviewCard(review)
                    }
                }
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, 24)
            }
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Bulk Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if selectedExerciseIds.isEmpty {
                selectedExerciseIds = Set(exercises.prefix(3).map(\.id))
            }
        }
    }

    @ViewBuilder
    private var scopeControls: some View {
        switch scope {
        case .selectedExercises:
            DisclosureGroup("Selected exercises (\(selectedExerciseIds.count))") {
                ForEach(exercises.prefix(50)) { exercise in
                    Toggle(exercise.name, isOn: selectedBinding(for: exercise.id))
                }
            }
        case .muscleGroup:
            Picker("Muscle group", selection: $muscleGroup) {
                ForEach(MuscleGroup.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        case .splitClassification:
            Picker("PPL category", selection: $splitClassification) {
                ForEach(CoachSplitClassification.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        case .accessories, .isolation, .priorityLifts, .warmUps:
            Text("Matches exercises using existing coach metadata first, then conservative library metadata.")
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var bulkUpdate: CoachBulkMetadataUpdate {
        CoachBulkMetadataUpdate(
            role: applyRole ? role : nil,
            priority: applyPriority ? priority : nil,
            primaryMuscleGroup: applyPrimaryMuscle ? primaryMuscleGroup : nil,
            secondaryMuscleGroups: applySecondaryMuscles ? secondaryMuscleGroups : nil,
            splitClassification: applyPPL ? updateSplitClassification : nil,
            movementPattern: applyMovement ? movementPattern : nil
        )
    }

    private func makeReview() -> CoachBulkMetadataReview {
        bulkService.review(
            scope: scope,
            selectedExerciseIds: selectedExerciseIds,
            muscleGroup: muscleGroup,
            splitClassification: splitClassification,
            exercises: exercises,
            existingMetadata: existingMetadata,
            update: bulkUpdate,
            overwriteExisting: overwriteExisting
        )
    }

    private func reviewCard(_ review: CoachBulkMetadataReview) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review Summary")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(review.summary)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    MetricTile(label: "Create", value: "\(review.willCreateCount)", caption: "New metadata", systemImage: "plus.circle")
                    MetricTile(label: "Update", value: "\(review.willUpdateCount)", caption: "Existing", systemImage: "pencil")
                }

                if review.skippedExistingCount > 0 {
                    Text("\(review.skippedExistingCount) existing metadata records will be skipped.")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textTertiary)
                }

                if !review.matchedExerciseNames.isEmpty {
                    Text(review.matchedExerciseNames.prefix(6).joined(separator: ", "))
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button {
                        self.review = nil
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeutralFitnessButtonStyle())

                    Button {
                        apply(review)
                    } label: {
                        Label("Apply", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .disabled(review.matchedExerciseIds.isEmpty)
                    .accessibilityIdentifier("bulk-metadata-apply")
                }
            }
        }
    }

    private func apply(_ review: CoachBulkMetadataReview) {
        let metadataByExerciseId = Dictionary(existingMetadata.map { ($0.exerciseId, $0) }, uniquingKeysWith: { first, _ in first })
        let matchedIds = Set(review.matchedExerciseIds)

        for exercise in exercises where matchedIds.contains(exercise.id) {
            let existing = metadataByExerciseId[exercise.id]
            guard let draft = bulkService.updatedDraft(
                for: exercise,
                existingMetadata: existing,
                update: bulkUpdate,
                overwriteExisting: overwriteExisting
            ) else { continue }

            if let existing {
                metadataService.update(existing, from: draft)
            } else {
                modelContext.insert(metadataService.makeMetadata(from: draft, exercise: exercise))
            }
        }

        try? modelContext.save()
        dismiss()
    }

    private func metadataToggle<Content: View>(
        _ title: String,
        isOn: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: isOn)
            if isOn.wrappedValue {
                content()
            }
        }
    }

    private func selectedBinding(for id: UUID) -> Binding<Bool> {
        Binding {
            selectedExerciseIds.contains(id)
        } set: { isSelected in
            if isSelected {
                selectedExerciseIds.insert(id)
            } else {
                selectedExerciseIds.remove(id)
            }
        }
    }

    private func secondaryMuscleBinding(for group: MuscleGroup) -> Binding<Bool> {
        Binding {
            secondaryMuscleGroups.contains(group)
        } set: { isSelected in
            if isSelected {
                if !secondaryMuscleGroups.contains(group) {
                    secondaryMuscleGroups.append(group)
                }
            } else {
                secondaryMuscleGroups.removeAll { $0 == group }
            }
        }
    }
}

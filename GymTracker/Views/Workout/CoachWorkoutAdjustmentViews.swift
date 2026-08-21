import SwiftData
import SwiftUI

struct WorkoutAdjustmentPreviewSheet: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    let preview: CoachWorkoutAdjustmentPreview
    let preferences: CoachPreferencesSnapshot
    let splitMetadata: CoachSplitMetadataSnapshot?
    let apply: (CoachWorkoutAdjustmentPreview) -> Void
    let cancel: () -> Void

    @State private var draft: EditableCoachWorkoutAdjustmentDraft
    @State private var didResolve = false

    private let adjustmentService = CoachWorkoutAdjustmentService()
    private let explanationService = CoachWorkoutChangeExplanationService()

    init(
        preview: CoachWorkoutAdjustmentPreview,
        preferences: CoachPreferencesSnapshot = .default,
        splitMetadata: CoachSplitMetadataSnapshot? = nil,
        apply: @escaping (CoachWorkoutAdjustmentPreview) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.preview = preview
        self.preferences = preferences
        self.splitMetadata = splitMetadata
        self.apply = apply
        self.cancel = cancel
        _draft = State(initialValue: CoachWorkoutAdjustmentService().editableDraft(from: preview))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    metrics
                    if draft.hasWorkoutChanges {
                        CoachWorkoutChangeExplanationCard(
                            explanation: explanationService.explanation(
                                for: adjustmentService.makePreview(from: draft),
                                preferences: preferences,
                                splitMetadata: splitMetadata
                            )
                        )
                    }
                    explanationSection
                    changesSection
                    beforeAfterSection
                }
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, 24)
            }
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Preview Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        didResolve = true
                        dismiss()
                        DispatchQueue.main.async {
                            cancel()
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(applyButtonTitle) {
                        didResolve = true
                        let resolvedPreview = adjustmentService.makePreview(from: draft)
                        dismiss()
                        DispatchQueue.main.async {
                            apply(resolvedPreview)
                        }
                    }
                }
            }
        }
        .onDisappear {
            if !didResolve {
                didResolve = true
                DispatchQueue.main.async {
                    cancel()
                }
            }
        }
    }

    private var header: some View {
        FitnessCard(style: .hero) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: preview.action.systemImage, size: 46)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text(preview.summary)
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                confidencePill
            }
        }
    }

    private var confidencePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge")
                .font(AppTypography.chip)
            Text(preview.confidence.displayName)
                .font(AppTypography.chip)
        }
        .foregroundStyle(appTheme.colors.textAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(appTheme.colors.accentSurface, in: Capsule())
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            MetricTile(
                label: "Exercises",
                value: "\(draft.basePreview.beforeExerciseCount) to \(draft.basePreview.afterExerciseCount)",
                caption: "Current preview",
                systemImage: "list.bullet"
            )

            MetricTile(
                label: "Sets",
                value: "\(draft.beforeTotalSets) to \(draft.afterTotalSets)",
                caption: "Working targets",
                systemImage: "chart.bar"
            )
        }
    }

    private var explanationSection: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                labeledText(title: "Why", text: preview.whySuggested)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Signals")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    ForEach(preview.contributingSignals, id: \.self) { signal in
                        Label(signal, systemImage: "circle.fill")
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var changesSection: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 14) {
                bulletGroup(title: "What changes", items: preview.changes, systemImage: "checkmark.circle.fill", tint: appTheme.colors.success)
                bulletGroup(title: "What stays the same", items: preview.unchanged, systemImage: "minus.circle.fill", tint: appTheme.colors.textTertiary)
            }
        }
    }

    private var beforeAfterSection: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("Exercise Preview")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Spacer(minLength: 8)

                    Button {
                        draft = adjustmentService.resetAllAdjustments(in: draft)
                    } label: {
                        Label("Reset All", systemImage: "arrow.counterclockwise")
                            .font(AppTypography.chip)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("coach-adjustment-reset-all")
                }

                ForEach($draft.exerciseAdjustments) { $adjustment in
                    editableAdjustmentRow($adjustment)

                    if adjustment.id != draft.exerciseAdjustments.last?.id {
                        Divider()
                    }
                }
            }
        }
        .accessibilityIdentifier("coach-adjustment-edit-preview")
    }

    private var applyButtonTitle: String {
        if preview.action == .keepPlan || !draft.hasWorkoutChanges {
            return "Keep"
        }
        return "Apply"
    }

    private func editableAdjustmentRow(_ adjustment: Binding<EditableCoachWorkoutExerciseAdjustment>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(adjustment.wrappedValue.name)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text(adjustment.wrappedValue.reason)
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    draft = adjustmentService.resetAdjustment(exerciseId: adjustment.wrappedValue.id, in: draft)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reset \(adjustment.wrappedValue.name)")
                .accessibilityIdentifier("coach-adjustment-reset-\(adjustment.wrappedValue.id.uuidString)")
            }

            Stepper(value: adjustment.editedSets, in: 1...max(8, adjustment.wrappedValue.beforeSets + 2)) {
                HStack {
                    Text("Target sets")
                        .font(AppTypography.chip)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    Spacer()

                    Text("\(adjustment.wrappedValue.beforeSets) -> \(adjustment.wrappedValue.editedSets)")
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(adjustment.wrappedValue.changedFromOriginal ? appTheme.colors.accent : appTheme.colors.textTertiary)
                }
            }

            TextField("Coach note", text: adjustment.editedNotes, axis: .vertical)
                .font(AppTypography.metadata)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("coach-adjustment-note-\(adjustment.wrappedValue.id.uuidString)")
        }
        .padding(.vertical, 4)
    }

    private func labeledText(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)

            Text(text)
                .font(AppTypography.body)
                .foregroundStyle(appTheme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bulletGroup(title: String, items: [String], systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)

            ForEach(items, id: \.self) { item in
                Label(item, systemImage: systemImage)
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .tint(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CoachWorkoutChangeExplanationCard: View {
    @Environment(\.appTheme) private var appTheme

    let explanation: CoachWorkoutChangeExplanation

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "questionmark.circle", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why This Changed")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("\(explanation.originalTotalSets) to \(explanation.adjustedTotalSets) sets with \(explanation.exercisesChanged.count) exercise\(explanation.exercisesChanged.count == 1 ? "" : "s") changed.")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !explanation.exercisesReduced.isEmpty {
                    compactLine("Reduced", explanation.exercisesReduced.prefix(4).joined(separator: ", "))
                }

                if !explanation.exercisesProtected.isEmpty {
                    compactLine("Protected", explanation.exercisesProtected.prefix(4).joined(separator: ", "))
                }

                compactLine("Reason", explanation.mainReason)

                if !explanation.readinessFatigueSignals.isEmpty {
                    compactLine("Signals", explanation.readinessFatigueSignals.prefix(3).joined(separator: " · "))
                }

                if let preferenceInfluence = explanation.preferenceInfluence {
                    compactLine("Preference", preferenceInfluence)
                }

                if let metadataInfluence = explanation.metadataInfluence {
                    compactLine("Metadata", metadataInfluence)
                }

                compactLine("Confidence", explanation.confidence.displayName)
            }
        }
        .accessibilityIdentifier("why-this-changed-card")
    }

    private func compactLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textTertiary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct ManualDeloadPlannerSheet: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    @State private var duration: ManualDeloadDuration
    @State private var volumeReduction: ManualDeloadVolumeReduction
    @State private var focus: ManualDeloadFocus
    @State private var didSaveBlock = false
    @State private var reviewPreview: CoachDeloadCalendarPreview?

    let fatigueRisk: CoachFatigueRisk
    let calendarPreview: (ManualDeloadPlan) -> CoachDeloadCalendarPreview
    let previewPlan: (ManualDeloadPlan) -> Void
    let savePlan: (ManualDeloadPlan) -> Void

    init(
        defaultPlan: ManualDeloadPlan,
        fatigueRisk: CoachFatigueRisk,
        calendarPreview: @escaping (ManualDeloadPlan) -> CoachDeloadCalendarPreview,
        previewPlan: @escaping (ManualDeloadPlan) -> Void,
        savePlan: @escaping (ManualDeloadPlan) -> Void
    ) {
        _duration = State(initialValue: defaultPlan.duration)
        _volumeReduction = State(initialValue: defaultPlan.volumeReduction)
        _focus = State(initialValue: defaultPlan.focus)
        self.fatigueRisk = fatigueRisk
        self.calendarPreview = calendarPreview
        self.previewPlan = previewPlan
        self.savePlan = savePlan
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FitnessCard(style: .hero) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                FitnessIconBadge(systemImage: "arrow.down.forward.circle", size: 46)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Manual Deload Planner")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(appTheme.colors.textPrimary)

                                    Text("Optional lighter-work guidance based on current fatigue signals. It does not schedule anything.")
                                        .font(AppTypography.body)
                                        .foregroundStyle(appTheme.mutedText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 14) {
                            durationPicker
                            volumePicker
                            focusPicker

                            Button {
                                reviewPreview = calendarPreview(currentPlan)
                            } label: {
                                Label(didSaveBlock ? "Deload Block Saved" : "Review Deload Block", systemImage: didSaveBlock ? "checkmark.circle.fill" : "calendar.badge.clock")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryFitnessButtonStyle())
                            .disabled(didSaveBlock)
                            .accessibilityIdentifier("manual-deload-save-block")
                        }
                    }

                    if let reviewPreview {
                        deloadReviewCard(reviewPreview)
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(fatigueRisk.title)
                                .font(AppTypography.sectionTitle)
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(fatigueRisk.summary)
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(fatigueRisk.factors.prefix(3), id: \.self) { factor in
                                Label(factor, systemImage: "circle.fill")
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                            }
                        }
                    }
                }
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, 24)
            }
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Deload")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Preview") {
                        previewPlan(currentPlan)
                        dismiss()
                    }
                }
            }
        }
    }

    private var currentPlan: ManualDeloadPlan {
        ManualDeloadPlan(
            duration: duration,
            volumeReduction: volumeReduction,
            focus: focus
        )
    }

    private func deloadReviewCard(_ preview: CoachDeloadCalendarPreview) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "calendar.badge.clock", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review Calendar Impact")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .accessibilityIdentifier("manual-deload-calendar-review")
                        Text("\(preview.startsAt.formatted(date: .abbreviated, time: .omitted)) - \(preview.endsAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    MetricTile(label: "Days", value: "\(preview.plan.duration.dayCount)", caption: preview.plan.duration.displayName, systemImage: "calendar")
                    MetricTile(label: "Training", value: "\(preview.estimatedAffectedTrainingDays)", caption: "Est. affected", systemImage: "figure.strengthtraining.traditional")
                }

                Text(preview.volumeSummary)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(preview.focusExplanation)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !preview.affectedSplitNames.isEmpty {
                    Text("Likely splits: \(preview.affectedSplitNames.joined(separator: ", ")).")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button {
                        reviewPreview = nil
                    } label: {
                        Label("Edit", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeutralFitnessButtonStyle())

                    Button {
                        savePlan(preview.plan)
                        didSaveBlock = true
                    } label: {
                        Label("Confirm", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .accessibilityIdentifier("manual-deload-confirm-save")
                }
            }
        }
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duration")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)

            Picker("Duration", selection: $duration) {
                ForEach(ManualDeloadDuration.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var volumePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)

            Picker("Volume", selection: $volumeReduction) {
                ForEach(ManualDeloadVolumeReduction.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var focusPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus")
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(appTheme.colors.textPrimary)

            Picker("Focus", selection: $focus) {
                ForEach(ManualDeloadFocus.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct CoachActionHistoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let entries: [CoachActionHistoryEntry]
    let feedback: [CoachRecommendationFeedback]

    @State private var outcomeFilter: CoachActionHistoryOutcome?
    @State private var actionFilter: CoachWorkoutAdjustmentAction?
    @State private var splitFilter: String?
    @State private var readinessFilter: ReadinessCategory?
    @State private var fatigueFilter: CoachFatigueRiskLevel?
    @State private var selectedEntry: CoachActionHistoryEntry?

    private let feedbackService = CoachRecommendationFeedbackService()
    private let filterService = CoachActionHistoryFilterService()
    private let exportService = CoachHistoryExportService()

    private var filteredEntries: [CoachActionHistoryEntry] {
        filterService.filter(entries, using: activeFilter)
    }

    private var activeFilter: CoachActionHistoryFilter {
        CoachActionHistoryFilter(
            outcome: outcomeFilter,
            action: actionFilter,
            splitName: splitFilter,
            readinessCategory: readinessFilter,
            fatigueRiskLevel: fatigueFilter
        )
    }

    private var splitOptions: [String] {
        Array(Set(entries.map { $0.splitName ?? "Unknown" })).sorted()
    }

    var body: some View {
        FitnessScreen(
            title: "Coach History",
            subtitle: "Review actions, signals, and feedback.",
            systemImage: "clock.arrow.circlepath"
        ) {
            DashboardSection(title: "Filters") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            MetricTile(label: "Shown", value: "\(filteredEntries.count)", caption: "Actions", systemImage: "line.3.horizontal.decrease")
                            MetricTile(label: "Feedback", value: "\(feedback.count)", caption: "Local", systemImage: "hand.thumbsup")
                        }

                        ShareLink(item: exportService.csv(entries: filteredEntries, feedback: feedback)) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())
                        .accessibilityIdentifier("coach-history-export")

                        filterGrid

                        if filtersAreActive {
                            Button {
                                resetFilters()
                            } label: {
                                Label("Clear filters", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(NeutralFitnessButtonStyle())
                        }
                    }
                }
            }

            DashboardSection(title: "Actions") {
                if filteredEntries.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No matching actions",
                        message: "Adjust the filters to review more coach actions.",
                        systemImage: "clock.arrow.circlepath"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEntries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                historyDetailRow(entry)
                            }
                            .buttonStyle(PressableCardButtonStyle())
                            .accessibilityIdentifier("coach-history-row-\(entry.id.uuidString)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Coach History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEntry) { entry in
            CoachActionHistoryDetailSheet(
                entry: entry,
                feedback: feedback.filter { $0.historyEntryId == entry.id },
                saveFeedback: { tags, note in
                    let item = feedbackService.makeFeedback(for: entry, tags: tags, note: note)
                    modelContext.insert(item)
                    try? modelContext.save()
                }
            )
        }
    }

    private var filterGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                filterMenu(title: "Outcome", value: outcomeFilter?.displayName ?? "All") {
                    Button("All") { outcomeFilter = nil }
                    ForEach(CoachActionHistoryOutcome.allCases) { outcome in
                        Button(outcome.displayName) { outcomeFilter = outcome }
                    }
                }
                .accessibilityIdentifier("coach-history-filter-outcome")

                filterMenu(title: "Action", value: actionFilter?.displayName ?? "All") {
                    Button("All") { actionFilter = nil }
                    ForEach(CoachWorkoutAdjustmentAction.allCases) { action in
                        Button(action.displayName) { actionFilter = action }
                    }
                }
                .accessibilityIdentifier("coach-history-filter-action")
            }

            HStack(spacing: 10) {
                filterMenu(title: "Split", value: splitFilter ?? "All") {
                    Button("All") { splitFilter = nil }
                    ForEach(splitOptions, id: \.self) { splitName in
                        Button(splitName) { splitFilter = splitName }
                    }
                }

                filterMenu(title: "Readiness", value: readinessFilter?.displayName ?? "All") {
                    Button("All") { readinessFilter = nil }
                    ForEach(ReadinessCategory.allCases, id: \.self) { category in
                        Button(category.displayName) { readinessFilter = category }
                    }
                }
            }

            filterMenu(title: "Fatigue", value: fatigueFilter?.displayName ?? "All") {
                Button("All") { fatigueFilter = nil }
                ForEach(CoachFatigueRiskLevel.allCases, id: \.self) { level in
                    Button(level.displayName) { fatigueFilter = level }
                }
            }
        }
    }

    private func filterMenu<Content: View>(
        title: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTypography.chip)
                        .foregroundStyle(appTheme.colors.textTertiary)
                    Text(value)
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
            .padding(12)
            .background(appTheme.elevatedCardBackground, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))
        }
    }

    private func historyDetailRow(_ entry: CoachActionHistoryEntry) -> some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .top, spacing: 12) {
                FitnessIconBadge(systemImage: entry.outcome.systemImage, size: 40)

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(entry.action.displayName) \(entry.outcome.displayName.lowercased())")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                    Text("\(entry.beforeTotalSets) to \(entry.afterTotalSets) sets")
                        .font(AppTypography.chip)
                        .foregroundStyle(appTheme.colors.textAccent)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
        }
    }

    private var filtersAreActive: Bool {
        activeFilter.isActive
    }

    private func resetFilters() {
        outcomeFilter = nil
        actionFilter = nil
        splitFilter = nil
        readinessFilter = nil
        fatigueFilter = nil
    }
}

private struct CoachActionHistoryDetailSheet: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dismiss) private var dismiss

    let entry: CoachActionHistoryEntry
    let feedback: [CoachRecommendationFeedback]
    let saveFeedback: ([CoachRecommendationFeedbackTag], String?) -> Void

    @State private var selectedTags: Set<CoachRecommendationFeedbackTag> = []
    @State private var note = ""

    private let feedbackService = CoachRecommendationFeedbackService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FitnessCard(style: .hero) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("\(entry.action.displayName) \(entry.outcome.displayName.lowercased())", systemImage: entry.outcome.systemImage)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(appTheme.colors.textPrimary)

                            Text(entry.shortReason)
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 10) {
                        MetricTile(label: "Sets", value: "\(entry.beforeTotalSets) to \(entry.afterTotalSets)", caption: "Before / after", systemImage: "chart.bar")
                        MetricTile(label: "Confidence", value: confidenceShortName, caption: entry.confidence.displayName, systemImage: "gauge")
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            detailLine("Workout", entry.splitName ?? entry.workoutName ?? "Unknown")
                            detailLine("Readiness", entry.readinessCategory.displayName)
                            detailLine("Fatigue", entry.fatigueRiskLevel.displayName)
                            detailLine("When", entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Coach Reason")
                                .font(AppTypography.sectionTitle)
                            Text(entry.diagnosticSummary ?? entry.shortReason)
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            ForEach(entry.contributingSignals, id: \.self) { signal in
                                Label(signal, systemImage: "circle.fill")
                                    .font(AppTypography.metadata)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                            }
                        }
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Feedback")
                                .font(AppTypography.sectionTitle)

                            Text(feedbackService.feedbackSummary(feedback))
                                .font(AppTypography.body)
                                .foregroundStyle(appTheme.colors.textSecondary)

                            feedbackTagGrid

                            TextField("Optional note", text: $note, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)

                            Button {
                                saveFeedback(Array(selectedTags), note)
                                selectedTags.removeAll()
                                note = ""
                                dismiss()
                            } label: {
                                Label("Save Feedback", systemImage: "hand.thumbsup")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryFitnessButtonStyle())
                            .disabled(selectedTags.isEmpty)
                            .accessibilityIdentifier("coach-history-save-feedback")
                        }
                    }
                }
                .padding(appTheme.metrics.screenPadding)
                .padding(.bottom, 24)
            }
            .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Action Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var confidenceShortName: String {
        switch entry.confidence {
        case .high:
            return "High"
        case .medium:
            return "Med"
        case .low:
            return "Low"
        }
    }

    private var feedbackTagGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(CoachRecommendationFeedbackTag.allCases) { tag in
                Button {
                    if selectedTags.contains(tag) {
                        selectedTags.remove(tag)
                    } else {
                        selectedTags.insert(tag)
                    }
                } label: {
                    Text(tag.displayName)
                        .font(AppTypography.chip)
                        .foregroundStyle(selectedTags.contains(tag) ? appTheme.colors.backgroundPrimary : appTheme.colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .padding(.horizontal, 8)
                        .background(selectedTags.contains(tag) ? appTheme.colors.accent : appTheme.elevatedCardBackground, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach-feedback-\(tag.rawValue)")
            }
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textTertiary)
            Spacer()
            Text(value)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SavedDeloadBlocksList: View {
    @Environment(\.appTheme) private var appTheme

    let blocks: [SavedCoachDeloadBlock]
    let complete: (SavedCoachDeloadBlock) -> Void
    let cancel: (SavedCoachDeloadBlock) -> Void

    var body: some View {
        if blocks.isEmpty {
            FitnessCard {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(systemImage: "arrow.down.forward.circle", size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No saved deload block")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("When fatigue is elevated, saving a deload block keeps the plan visible without changing future workouts.")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(blocks.prefix(3)) { block in
                    deloadBlockRow(block)
                }
            }
        }
    }

    private func deloadBlockRow(_ block: SavedCoachDeloadBlock) -> some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    FitnessIconBadge(
                        systemImage: block.state.systemImage,
                        size: 40,
                        tint: tint(for: block.state),
                        background: tint(for: block.state).opacity(0.14)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(block.plan.title)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)

                        Text("\(block.volumeReduction.displayName) volume - \(block.focus.displayName)")
                            .font(AppTypography.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer(minLength: 8)

                    Text(block.state.displayName)
                        .font(AppTypography.eyebrow)
                        .foregroundStyle(tint(for: block.state))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tint(for: block.state).opacity(0.12), in: Capsule())
                }

                Text("\(block.startsAt.formatted(date: .abbreviated, time: .omitted)) - \(block.endsAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textTertiary)

                Text(block.reason)
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if block.state == .active {
                    HStack {
                        Button {
                            complete(block)
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryFitnessButtonStyle())

                        Button {
                            cancel(block)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NeutralFitnessButtonStyle())
                    }
                }
            }
        }
    }

    private func tint(for state: CoachDeloadBlockState) -> Color {
        switch state {
        case .active:
            return appTheme.colors.warning
        case .completed:
            return appTheme.colors.success
        case .cancelled:
            return appTheme.colors.textTertiary
        }
    }
}

struct CoachDiagnosticsCard: View {
    @Environment(\.appTheme) private var appTheme

    let diagnostics: CoachDiagnostics

    var body: some View {
        FitnessCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    diagnosticGroup("Readiness inputs", items: diagnostics.readinessInputs)
                    diagnosticGroup("Fatigue inputs", items: diagnostics.fatigueInputs)
                    diagnosticGroup("Exercise metadata", items: diagnostics.exerciseMetadataInputs)
                    diagnosticGroup("Feedback influence", items: diagnostics.feedbackInfluence)
                    diagnosticGroup("Confidence adjustments", items: diagnostics.confidenceAdjustmentReasons)
                    diagnosticGroup("Preferences", items: diagnostics.coachPreferenceInfluence)
                    diagnosticGroup("Split metadata", items: diagnostics.splitMetadataInfluence)
                    diagnosticGroup("Bulk metadata", items: diagnostics.bulkMetadataInfluence)
                    diagnosticGroup("Urgency", items: diagnostics.urgencyAdjustmentReasons)
                    diagnosticGroup("Missing data", items: diagnostics.missingDataReasons.isEmpty ? ["No major missing inputs."] : diagnostics.missingDataReasons)
                    labeledText("Adaptive action", diagnostics.adaptiveActionReason)
                    labeledText("Deload trigger", diagnostics.deloadTriggerReason ?? "No elevated deload trigger.")
                    labeledText("Deload blocks", diagnostics.deloadBlockInfluence ?? "No saved deload influence.")
                    labeledText("Action history", diagnostics.actionHistoryInfluence ?? "No action history influence.")
                }
                .padding(.top, 12)
            } label: {
                HStack(spacing: 12) {
                    FitnessIconBadge(systemImage: "stethoscope", size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coach Diagnostics")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text(diagnostics.confidence.displayName)
                            .font(AppTypography.metadata)
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }
                }
            }
        }
    }

    private func diagnosticGroup(_ title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textTertiary)

            ForEach(items.prefix(5), id: \.self) { item in
                Text(item)
                    .font(AppTypography.metadata)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func labeledText(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textTertiary)
            Text(text)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CoachPreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var preferences: [CoachPreferences] = []
    @State private var activeSplits: [TrainingSplit] = []
    @State private var splitMetadata: [CoachSplitMetadata] = []
    @State private var snapshot = CoachPreferencesSnapshot.default
    @State private var didLoad = false

    private let preferencesService = CoachPreferencesService()

    private static var preferencesDescriptor: FetchDescriptor<CoachPreferences> {
        var descriptor = FetchDescriptor<CoachPreferences>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        descriptor.includePendingChanges = true
        return descriptor
    }

    private static var activeSplitsDescriptor: FetchDescriptor<TrainingSplit> {
        var descriptor = FetchDescriptor<TrainingSplit>(
            predicate: #Predicate<TrainingSplit> { $0.isActive },
            sortBy: [SortDescriptor(\.name)]
        )
        descriptor.fetchLimit = 12
        descriptor.includePendingChanges = true
        return descriptor
    }

    private static var splitMetadataDescriptor: FetchDescriptor<CoachSplitMetadata> {
        var descriptor = FetchDescriptor<CoachSplitMetadata>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        descriptor.includePendingChanges = true
        return descriptor
    }

    var body: some View {
        FitnessScreen(
            title: "Coach Preferences",
            subtitle: "Tune wording and adjustment style.",
            systemImage: "slider.horizontal.3"
        ) {
            DashboardSection(title: "Coach Behaviour") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 14) {
                        preferencePicker("Aggressiveness", selection: $snapshot.aggressiveness, options: CoachAggressiveness.allCases)
                            .accessibilityIdentifier("coach-preferences-aggressiveness")
                        preferencePicker("Deload wording", selection: $snapshot.deloadWording, options: CoachDeloadWording.allCases)
                        preferencePicker("Detail level", selection: $snapshot.detailLevel, options: CoachDetailLevel.allCases)
                        preferencePicker("Training priority", selection: $snapshot.trainingPriority, options: CoachTrainingPriority.allCases)
                        preferencePicker("Reduction style", selection: $snapshot.reductionPreference, options: CoachReductionPreference.allCases)
                        preferencePicker("Recommendation frequency", selection: $snapshot.recommendationFrequency, options: CoachRecommendationFrequency.allCases)

                        Toggle("Show diagnostics", isOn: $snapshot.showDiagnostics)
                            .accessibilityIdentifier("coach-preferences-diagnostics")
                    }
                }
            }

            DashboardSection(title: "Split Intent") {
                if activeSplits.isEmpty {
                    DashboardEmptyStateCard(
                        title: "No active splits",
                        message: "Create a split to add optional coach intent.",
                        systemImage: "square.stack.3d.up"
                    )
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(activeSplits) { split in
                            NavigationLink {
                                CoachSplitMetadataEditorView(split: split)
                            } label: {
                                splitIntentRow(split)
                            }
                            .buttonStyle(PressableCardButtonStyle())
                            .accessibilityIdentifier("split-metadata-open-\(split.name)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Coach Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach-preferences-screen")
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: savePreferences)
    }

    private func preferencePicker<Option: CaseIterable & Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Option>,
        options: Option.AllCases
    ) -> some View where Option.AllCases: RandomAccessCollection, Option: Identifiable {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textTertiary)

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(displayName(for: option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displayName<Option>(for option: Option) -> String {
        switch option {
        case let value as CoachAggressiveness:
            return value.displayName
        case let value as CoachDeloadWording:
            return value.displayName
        case let value as CoachDetailLevel:
            return value.displayName
        case let value as CoachTrainingPriority:
            return value.displayName
        case let value as CoachReductionPreference:
            return value.displayName
        case let value as CoachRecommendationFrequency:
            return value.displayName
        default:
            return "\(option)"
        }
    }

    private func splitIntentRow(_ split: TrainingSplit) -> some View {
        let metadata = splitMetadata.first { $0.splitId == split.id }
        let snapshot = metadata?.snapshot ?? CoachSplitMetadataSnapshot.defaultFor(splitId: split.id, splitName: split.name)

        return FitnessCard(style: .compact) {
            HStack(alignment: .top, spacing: 12) {
                FitnessIconBadge(systemImage: "square.stack.3d.up", size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(split.name)
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text("\(snapshot.primaryGoal.displayName) · \(snapshot.expectedFatigue.displayName) fatigue · \(snapshot.preferredAdjustmentStyle.displayName)")
                        .font(AppTypography.metadata)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppTypography.eyebrow)
                    .foregroundStyle(appTheme.colors.textTertiary)
            }
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        do {
            preferences = try modelContext.fetch(Self.preferencesDescriptor)
            activeSplits = try modelContext.fetch(Self.activeSplitsDescriptor)
            splitMetadata = try modelContext.fetch(Self.splitMetadataDescriptor)
        } catch {
            preferences = []
            activeSplits = []
            splitMetadata = []
        }

        snapshot = preferencesService.snapshot(from: preferences)
        didLoad = true
    }

    private func savePreferences() {
        guard didLoad else { return }
        if let current = preferences.first {
            preferencesService.update(current, from: snapshot)
        } else {
            modelContext.insert(preferencesService.makePreferences(from: snapshot))
        }
        try? modelContext.save()
    }
}

struct CoachSplitMetadataEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    let split: TrainingSplit

    @Query(sort: \CoachSplitMetadata.updatedAt, order: .reverse)
    private var allMetadata: [CoachSplitMetadata]

    @State private var snapshot: CoachSplitMetadataSnapshot
    @State private var note: String
    @State private var didLoad = false

    private let metadataService = CoachSplitMetadataService()

    init(split: TrainingSplit) {
        self.split = split
        let defaultSnapshot = CoachSplitMetadataSnapshot.defaultFor(splitId: split.id, splitName: split.name)
        _snapshot = State(initialValue: defaultSnapshot)
        _note = State(initialValue: defaultSnapshot.userNote ?? "")
    }

    var body: some View {
        FitnessScreen(
            title: split.name,
            subtitle: "Optional coach intent for this split.",
            systemImage: "square.stack.3d.up"
        ) {
            DashboardSection(title: "Training Intent") {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 14) {
                        splitPicker("Split priority", selection: $snapshot.priority, options: CoachSplitPriority.allCases)
                            .accessibilityIdentifier("split-metadata-priority")
                        splitPicker("Planned intensity", selection: $snapshot.plannedIntensity, options: CoachPlannedIntensity.allCases)
                        splitPicker("Primary goal", selection: $snapshot.primaryGoal, options: CoachSplitGoal.allCases)
                        splitPicker("Expected fatigue", selection: $snapshot.expectedFatigue, options: CoachExpectedFatigue.allCases)
                        splitPicker("Adjustment style", selection: $snapshot.preferredAdjustmentStyle, options: CoachPreferredAdjustmentStyle.allCases)

                        Toggle("Protect compounds", isOn: $snapshot.protectCompounds)
                        Toggle("Accessories flexible", isOn: $snapshot.accessoriesFlexible)

                        TextField("Coach note", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .navigationTitle("Split Intent")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: saveMetadata)
    }

    private func splitPicker<Option: CaseIterable & Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Option>,
        options: Option.AllCases
    ) -> some View where Option.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.chip)
                .foregroundStyle(appTheme.colors.textTertiary)

            Picker(title, selection: selection) {
                ForEach(options) { option in
                    Text(displayName(for: option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displayName<Option>(for option: Option) -> String {
        switch option {
        case let value as CoachSplitPriority:
            return value.displayName
        case let value as CoachPlannedIntensity:
            return value.displayName
        case let value as CoachSplitGoal:
            return value.displayName
        case let value as CoachExpectedFatigue:
            return value.displayName
        case let value as CoachPreferredAdjustmentStyle:
            return value.displayName
        default:
            return "\(option)"
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        if let current = allMetadata.first(where: { $0.splitId == split.id }) {
            snapshot = current.snapshot
            note = current.userNote ?? ""
        }
        didLoad = true
    }

    private func saveMetadata() {
        guard didLoad else { return }
        var updatedSnapshot = snapshot
        updatedSnapshot.userNote = note
        if let current = allMetadata.first(where: { $0.splitId == split.id }) {
            metadataService.update(current, from: updatedSnapshot)
        } else {
            modelContext.insert(metadataService.makeMetadata(from: updatedSnapshot))
        }
        try? modelContext.save()
    }
}

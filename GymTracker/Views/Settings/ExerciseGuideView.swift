import SwiftUI

/// Read-only illustration catalogue. Browsing never inserts exercises into the user's library.
struct ExerciseGuideLibraryView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @State private var equipment = ""
    @State private var muscle = ""

    private var entries: [ExerciseGuideEntry] {
        ExerciseGuideCatalog.exercises.filter { entry in
            (equipment.isEmpty || entry.equipment == equipment)
                && (muscle.isEmpty || entry.primaryMuscle == muscle)
                && (searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || ([entry.name, entry.equipment, entry.primaryMuscle] + entry.secondaryMuscles)
                        .joined(separator: " ").localizedStandardContains(searchText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 145), spacing: 12, alignment: .top)]
    }

    var body: some View {
        let results = entries
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("\(results.count) exercises")
                        .font(AppTypography.metadataEmphasis)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .accessibilityIdentifier("exercise-guide-result-count")
                    Spacer()
                    if !equipment.isEmpty || !muscle.isEmpty {
                        Button("Clear filters") {
                            equipment = ""
                            muscle = ""
                        }
                        .font(AppTypography.bodyEmphasis)
                        .frame(minHeight: 44)
                    }
                }

                if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(results) { entry in
                            NavigationLink {
                                ExerciseGuideDetailView(entry: entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    ExerciseGuideImage(entry: entry, frame: 1)
                                        .frame(height: 116)
                                        .frame(maxWidth: .infinity)
                                        .accessibilityHidden(true)
                                    Text(entry.name)
                                        .font(AppTypography.bodyEmphasis)
                                        .foregroundStyle(appTheme.colors.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text("\(entry.primaryMuscle) · \(entry.equipment)")
                                        .font(AppTypography.metadata)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(appTheme.colors.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(appTheme.colors.cardBorder, lineWidth: 0.75)
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("exercise-guide-row-\(entry.slug)")
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(appTheme.colors.backgroundPrimary)
        .peaklineKeyboardDismissal()
        .navigationTitle("Exercise Guide")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Exercise, muscle or equipment")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Equipment", selection: $equipment) {
                        Text("All equipment").tag("")
                        ForEach(Array(Set(ExerciseGuideCatalog.exercises.map(\.equipment))).sorted(), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    Picker("Primary muscle", selection: $muscle) {
                        Text("All muscles").tag("")
                        ForEach(Array(Set(ExerciseGuideCatalog.exercises.map(\.primaryMuscle))).sorted(), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                } label: {
                    Label("Filter exercises", systemImage: equipment.isEmpty && muscle.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityIdentifier("exercise-guide-filters")
            }
        }
        .tint(appTheme.colors.accent)
        .accessibilityIdentifier("exercise-guide-library")
    }
}
struct ExerciseGuideDetailView: View {
    @Environment(\.appTheme) private var appTheme
    let entry: ExerciseGuideEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ExercisePosePreview(entry: entry)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Exercise details")
                        .font(AppTypography.sectionTitle)
                    detail("Equipment", entry.equipment)
                    detail("Primary muscle", entry.primaryMuscle)
                    if !entry.secondaryMuscles.isEmpty {
                        detail("Secondary muscles", entry.secondaryMuscles.joined(separator: ", "))
                    }
                    detail("Tracking", trackingDescription)
                    if entry.isStretch {
                        detail("Category", "Stretch")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                NavigationLink {
                    ExerciseArtworkCreditsView()
                } label: {
                    Label("Artwork credits", systemImage: "info.circle")
                        .font(AppTypography.body)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("exercise-guide-credits")
            }
            .padding(20)
        }
        .background(appTheme.colors.backgroundPrimary)
        .foregroundStyle(appTheme.colors.textPrimary)
        .tint(appTheme.colors.accent)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("exercise-guide-detail-\(entry.slug)")
    }

    private var trackingDescription: String {
        switch entry.exerciseType {
        case "weight_reps": "Weight and reps"
        case "reps": "Reps"
        case "duration": "Duration"
        case "distance_duration": "Distance and duration"
        default: entry.exerciseType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(AppTypography.metadata)
                .foregroundStyle(appTheme.colors.textSecondary)
            Text(value)
                .font(AppTypography.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A lightweight three-pose sequence. Playback never drives model or persistence updates.
struct ExercisePosePreview: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let entry: ExerciseGuideEntry
    @State private var selectedFrame = 1
    @State private var direction = 1
    @State private var isVisible = false
    @State private var selectionRevision = 0

    private var shouldPlay: Bool { isVisible && !reduceMotion && scenePhase == .active }

    var body: some View {
        VStack(spacing: 16) {
            ExerciseGuideImage(entry: entry, frame: selectedFrame)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(entry.name), pose \(selectedFrame) of 3")
                .accessibilityIdentifier("exercise-guide-illustration")

            HStack(spacing: 12) {
                ForEach(1...3, id: \.self) { frame in
                    Button {
                        selectedFrame = frame
                        if frame == 1 { direction = 1 }
                        if frame == 3 { direction = -1 }
                        selectionRevision += 1
                    } label: {
                        VStack(spacing: 6) {
                            ExerciseGuideImage(entry: entry, frame: frame)
                                .frame(height: 58)
                                .accessibilityHidden(true)
                            Text("\(frame)")
                                .font(AppTypography.metadataEmphasis)
                                .foregroundStyle(appTheme.colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding(6)
                        .background(selectedFrame == frame ? appTheme.colors.accentSurface : appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedFrame == frame ? appTheme.colors.accent : appTheme.colors.cardBorder, lineWidth: selectedFrame == frame ? 2 : 0.75)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pose \(frame)")
                    .accessibilityAddTraits(selectedFrame == frame ? .isSelected : [])
                    .accessibilityIdentifier("exercise-guide-pose-\(frame)")
                }
            }
        }

        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: "\(shouldPlay)-\(selectionRevision)") {
            guard shouldPlay else { return }
            // Sleep between discrete asset changes; no display-link or model updates.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(850)) }
                catch { return }
                guard !Task.isCancelled else { return }
                if selectedFrame == 1 { direction = 1 }
                if selectedFrame == 3 { direction = -1 }
                selectedFrame += direction
            }
        }
    }
}

private struct ExerciseGuideImage: View {
    @Environment(\.appTheme) private var appTheme
    let entry: ExerciseGuideEntry
    let frame: Int

    var body: some View {
        Image(entry.assetName(frame: frame))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(appTheme.colors.textAccent)
    }
}

struct ExerciseGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: ExerciseGuideEntry

    var body: some View {
        NavigationStack {
            ExerciseGuideDetailView(entry: entry)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

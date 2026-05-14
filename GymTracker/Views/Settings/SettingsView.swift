import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @AppStorage("appTheme") private var storedTheme = AppTheme.appleGreen.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    if let profile = profiles.first {
                        NavigationLink {
                            ProfileEditorView(profile: profile)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.goal.displayName)
                                    .font(.headline)
                                Text("\(profile.experienceLevel.displayName) - \(profile.trainingDaysPerWeek) days/week")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            createProfile()
                        } label: {
                            Label("Create Profile", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }

                Section("Training Setup") {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Exercise Library", systemImage: "dumbbell")
                    }

                    NavigationLink {
                        ProgressContentView()
                    } label: {
                        Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                    }

                    NavigationLink {
                        CoachContentView()
                    } label: {
                        Label("Coach", systemImage: "sparkles")
                    }
                }

                Section("Themes") {
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        HStack {
                            Text("Theme")
                            Spacer()
                            Circle()
                                .fill(selectedTheme.primaryColor)
                                .frame(width: 18, height: 18)
                            Text(selectedTheme.displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Safety") {
                    Text("This app provides general fitness tracking and training suggestions based on your logged workouts. It is not medical advice. Stop exercising and seek professional advice if you experience pain, dizziness, or symptoms that concern you.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("iCloud Backup") {
                    Label("iCloud sync planned", systemImage: "icloud")
                    Text("Workout data is stored locally with SwiftData. iCloud/CloudKit sync should be enabled from Xcode Signing & Capabilities once this Apple ID has access to iCloud containers. Free personal signing may not support that capability.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func createProfile() {
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: storedTheme) ?? .appleGreen
    }
}

private struct ThemeSettingsView: View {
    @AppStorage("appTheme") private var storedTheme = AppTheme.appleGreen.rawValue
    @AppStorage("appAppearance") private var storedAppearance = AppAppearance.system.rawValue

    private var selectedTheme: Binding<AppTheme> {
        Binding {
            AppTheme(rawValue: storedTheme) ?? .appleGreen
        } set: { newTheme in
            storedTheme = newTheme.rawValue
        }
    }

    private var selectedAppearance: Binding<AppAppearance> {
        Binding {
            AppAppearance(rawValue: storedAppearance) ?? .system
        } set: { newAppearance in
            storedAppearance = newAppearance.rawValue
        }
    }

    var body: some View {
        Form {
            Section("Colour") {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        selectedTheme.wrappedValue = theme
                    } label: {
                        HStack {
                            Circle()
                                .fill(theme.primaryColor)
                                .frame(width: 22, height: 22)
                            Text(theme.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedTheme.wrappedValue == theme {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Appearance") {
                Picker("Mode", selection: selectedAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: UserProfile

    var body: some View {
        Form {
            Section("Training") {
                Picker("Goal", selection: $profile.goal) {
                    ForEach(TrainingGoal.allCases) { goal in
                        Text(goal.displayName).tag(goal)
                    }
                }

                Picker("Experience", selection: $profile.experienceLevel) {
                    ForEach(ExperienceLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }

                Picker("Preferred split", selection: $profile.preferredSplitType) {
                    ForEach(SplitType.allCases) { splitType in
                        Text(splitType.displayName).tag(splitType)
                    }
                }

                Stepper("Training days: \(profile.trainingDaysPerWeek)", value: $profile.trainingDaysPerWeek, in: 1...7)

                DatePicker(
                    "Lifting start",
                    selection: Binding($profile.liftingStartDate, replacingNilWith: .now),
                    displayedComponents: .date
                )
            }

            Section("Body") {
                Picker("Units", selection: $profile.unitSystem) {
                    Text("kg").tag(UnitSystem.metric)
                    Text("lb").tag(UnitSystem.imperial)
                }

                OptionalDoubleField(title: "Bodyweight", value: $profile.bodyweight)
            }

            Section("Notes") {
                TextField("Injury notes", text: Binding($profile.injuryNotes, replacingNilWith: ""), axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            profile.updatedAt = .now
            try? modelContext.save()
        }
    }
}

private struct OptionalDoubleField: View {
    let title: String
    @Binding var value: Double?

    private var text: Binding<String> {
        Binding {
            guard let value else { return "" }
            return value.formatted(.number.precision(.fractionLength(0...1)))
        } set: { newValue in
            value = Double(newValue)
        }
    }

    var body: some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
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

private extension Binding where Value == Date {
    init(_ source: Binding<Date?>, replacingNilWith fallback: Date) {
        self.init {
            source.wrappedValue ?? fallback
        } set: { newValue in
            source.wrappedValue = newValue
        }
    }
}

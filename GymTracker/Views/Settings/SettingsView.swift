import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Query private var profiles: [UserProfile]
    @AppStorage("appTheme") private var storedTheme = AppTheme.black.rawValue

    var body: some View {
        NavigationStack {
            FitnessScreen(
                title: "Settings",
                subtitle: "Preferences, utilities, and local data.",
                systemImage: "gearshape"
            ) {
                DashboardSection(title: "Profile") {
                    if let profile = profiles.first {
                        NavigationLink {
                            ProfileEditorView(profile: profile)
                        } label: {
                            SettingsCardRow(
                                title: profile.goal.displayName,
                                subtitle: "\(profile.experienceLevel.displayName) - \(profile.trainingDaysPerWeek) days/week",
                                systemImage: "person.crop.circle"
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            createProfile()
                        } label: {
                            SettingsCardRow(
                                title: "Create Profile",
                                subtitle: "Set goal, training days, and unit preferences.",
                                systemImage: "person.crop.circle.badge.plus",
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                DashboardSection(title: "Training Setup") {
                    FitnessCard(style: .compact, padding: 12) {
                        VStack(spacing: 0) {
                            NavigationLink {
                                ExerciseLibraryView()
                            } label: {
                                SettingsInlineRow(title: "Exercise Library", subtitle: "Manage exercises and icons", systemImage: "dumbbell")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-exercise-library")

                            SettingsDivider()

                            NavigationLink {
                                ProgressContentView()
                            } label: {
                                SettingsInlineRow(title: "Progress", subtitle: "Charts, PRs, and lift trends", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-progress")

                            SettingsDivider()

                            NavigationLink(value: SettingsRoute.coach) {
                                SettingsInlineRow(title: "Coach", subtitle: "Targets, warnings, and weekly review", systemImage: "sparkles")
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings-coach")
                        }
                    }
                }

                DashboardSection(title: "Gym Utilities") {
                    HStack(spacing: 12) {
                        NavigationLink {
                            PlateCalculatorView()
                        } label: {
                            SettingsUtilityTile(title: "Plate Calculator", subtitle: "Load the bar quickly", systemImage: "scalemass")
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ThemeSettingsView()
                        } label: {
                            SettingsUtilityTile(title: "Themes", subtitle: selectedTheme.displayName, systemImage: "paintpalette")
                        }
                        .buttonStyle(.plain)
                    }
                }

                DashboardSection(title: "Apple Health") {
                    VStack(spacing: 12) {
                        NavigationLink {
                            SleepSettingsStandaloneView()
                        } label: {
                            SettingsCardRow(
                                title: "Sleep Settings",
                                subtitle: "Sleep reminders, Apple Health, source priority, and recovery coaching.",
                                systemImage: "moon.zzz"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            HealthKitSettingsView()
                        } label: {
                            SettingsCardRow(
                                title: "Apple Health Sync",
                                subtitle: "Optional nutrition sharing and labeled activity context.",
                                systemImage: "heart.text.square"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                DashboardSection(title: "Safety") {
                    FitnessCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "cross.case")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(appTheme.colors.warning)
                                .frame(width: 42, height: 42)
                                .background(appTheme.colors.warning.opacity(0.16), in: Circle())

                            Text("This app provides general fitness tracking and training suggestions based on your logged workouts. It is not medical advice. Stop exercising and seek professional advice if you experience pain, dizziness, or symptoms that concern you.")
                                .font(.footnote)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                DashboardSection(title: "Local Data") {
                    FitnessCard(style: .compact, padding: 12) {
                        VStack(spacing: 0) {
                            NavigationLink {
                                BackupExportView()
                            } label: {
                                SettingsInlineRow(title: "Backup & Export", subtitle: "Create local files you can save", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)

                            SettingsDivider()

                            HStack(spacing: 12) {
                                Image(systemName: "icloud")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .frame(width: 36, height: 36)
                                    .background(appTheme.colors.cardBackgroundElevated, in: Circle())

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("iCloud sync planned")
                                        .font(.headline)
                                        .foregroundStyle(appTheme.colors.textPrimary)
                                    Text("Workout data is stored locally with SwiftData. Backup & Export creates local files you can save yourself.")
                                        .font(.caption)
                                        .foregroundStyle(appTheme.colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                        }
                    }
                }

                FitnessCard(style: .compact) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Theme")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .textCase(.uppercase)
                            Text(selectedTheme.displayName)
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                        }

                        Spacer()

                        ZStack {
                            Circle()
                                .fill(selectedTheme.colors.accent)
                                .frame(width: 28, height: 28)
                            Circle()
                                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
                                .frame(width: 42, height: 42)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings-screen")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .coach:
                    CoachContentView()
                }
            }
        }
    }

    private func createProfile() {
        modelContext.insert(UserProfile())
        try? modelContext.save()
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: storedTheme) ?? .black
    }
}

private struct SettingsCardRow: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String
    var showsChevron = true

    var body: some View {
        FitnessCard(style: .compact) {
            HStack(spacing: 12) {
                SettingsRowIcon(systemImage: systemImage)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                Spacer()

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(appTheme.colors.textTertiary)
                }
            }
        }
    }
}

private struct SettingsInlineRow: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(appTheme.colors.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
}

private struct SettingsUtilityTile: View {
    @Environment(\.appTheme) private var appTheme

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        FitnessCard(style: .compact) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsRowIcon(systemImage: systemImage)

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
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        }
    }
}

private struct SettingsRowIcon: View {
    @Environment(\.appTheme) private var appTheme

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(appTheme.colors.accent)
            .frame(width: appTheme.metrics.rowIconSize, height: appTheme.metrics.rowIconSize)
            .background(appTheme.colors.accentSurface, in: Circle())
    }
}

private struct SettingsDivider: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Divider()
            .overlay(appTheme.colors.cardBorder)
            .padding(.leading, 58)
    }
}

private enum SettingsRoute: Hashable {
    case coach
}

private struct ThemeSettingsView: View {
    @Environment(\.appTheme) private var appTheme
    @AppStorage("appTheme") private var storedTheme = AppTheme.black.rawValue
    @AppStorage("appAppearance") private var storedAppearance = AppAppearance.system.rawValue

    private let availableThemes: [AppTheme] = [.black]

    private var selectedTheme: Binding<AppTheme> {
        Binding {
            AppTheme(rawValue: storedTheme) ?? .black
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Colour")
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    FitnessCard(padding: 10) {
                        VStack(spacing: 6) {
                            ForEach(availableThemes) { theme in
                                ThemeOptionRow(
                                    theme: theme,
                                    isSelected: selectedTheme.wrappedValue == theme
                                ) {
                                    selectedTheme.wrappedValue = theme
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance")
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textSecondary)

                    FitnessCard(padding: 10) {
                        HStack(spacing: 8) {
                            ForEach(AppAppearance.allCases) { appearance in
                                AppearanceOptionButton(
                                    appearance: appearance,
                                    isSelected: selectedAppearance.wrappedValue == appearance
                                ) {
                                    selectedAppearance.wrappedValue = appearance
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("theme-settings-screen")
        .onAppear {
            storedTheme = AppTheme.black.rawValue
        }
    }
}

private struct ThemeOptionRow: View {
    @Environment(\.appTheme) private var appTheme

    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(theme.colors.accent)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Circle()
                            .stroke(.white.opacity(0.55), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(themeDescription)
                        .font(.caption)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? theme.colors.accent : appTheme.colors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(isSelected ? theme.colors.accentSurface : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var themeDescription: String {
        switch theme {
        case .appleGreen:
            return "Workout green accents"
        case .red:
            return "Bold red intensity"
        case .purple:
            return "High contrast violet"
        case .orange:
            return "Warm amber energy"
        case .blue:
            return "Cool training blue"
        case .black:
            return "Monochrome black accents"
        }
    }
}

private struct AppearanceOptionButton: View {
    @Environment(\.appTheme) private var appTheme

    let appearance: AppAppearance
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                Text(appearance.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
            .foregroundStyle(isSelected ? appTheme.colors.textPrimary : appTheme.colors.textSecondary)
            .background(
                isSelected ? appTheme.colors.accentSurfaceStrong : appTheme.colors.cardBackgroundElevated,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? appTheme.colors.accent.opacity(0.45) : appTheme.colors.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var systemImage: String {
        switch appearance {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }
}

private struct ProfileEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Bindable var profile: UserProfile
    @State private var activePicker: ProfilePicker?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProfileSummaryCard(profile: profile)
                trainingPreferencesSection
                bodySection
                notesSection
                coachingImpactCard
            }
            .padding()
        }
        .background(appTheme.colors.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(pickerTitle, isPresented: pickerPresented, titleVisibility: .visible) {
            pickerOptions
        }
        .onDisappear {
            profile.updatedAt = .now
            try? modelContext.save()
        }
    }

    private var trainingPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionTitle("Training Preferences")

            FitnessCard(padding: 12) {
                VStack(spacing: 8) {
                    ProfileSettingRow(icon: "target", title: "Goal", subtitle: "Tunes rep targets and progression style.") {
                        pickerButton(profile.goal.displayName, picker: .goal)
                    }

                    ProfileDivider()

                    ProfileSettingRow(icon: "chart.line.uptrend.xyaxis", title: "Experience", subtitle: "Keeps recommendations realistic.") {
                        pickerButton(profile.experienceLevel.displayName, picker: .experience)
                    }

                    ProfileDivider()

                    ProfileSettingRow(icon: "calendar", title: "Preferred split", subtitle: "Your default weekly structure.") {
                        pickerButton(profile.preferredSplitType.displayName, picker: .split)
                    }

                    ProfileDivider()

                    ProfileSettingRow(icon: "number", title: "Training days", subtitle: "Used for weekly consistency targets.") {
                        ProfileStepperControl(value: $profile.trainingDaysPerWeek, range: 1...7)
                    }

                    ProfileDivider()

                    ProfileSettingRow(icon: "calendar.badge.clock", title: "Lifting start", subtitle: "Estimates your training age.") {
                        ProfileDateChip(date: Binding($profile.liftingStartDate, replacingNilWith: .now))
                    }
                }
            }
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionTitle("Body")

            FitnessCard(padding: 12) {
                VStack(spacing: 8) {
                    ProfileSettingRow(icon: "scalemass", title: "Bodyweight", subtitle: "Current tracking weight.") {
                        ProfileBodyweightField(value: $profile.bodyweight, unitText: unitText)
                    }

                    ProfileDivider()

                    ProfileSettingRow(icon: "ruler", title: "Units", subtitle: "Used across workouts and charts.") {
                        pickerButton(unitText, picker: .units)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionTitle("Health & Notes")

            FitnessCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ProfileIcon(systemName: "cross.case")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Injury notes")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                            Text("Tell Coach what to avoid or be cautious with.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                        }
                    }

                    ProfileNotesEditor(text: Binding($profile.injuryNotes, replacingNilWith: ""))

                    if !profile.exercisesToAvoid.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Exercises to avoid")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .textCase(.uppercase)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(profile.exercisesToAvoid, id: \.self) { exercise in
                                    ProfileValueChip(text: exercise)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var coachingImpactCard: some View {
        FitnessCard {
            HStack(alignment: .top, spacing: 12) {
                ProfileIcon(systemName: "sparkles")

                VStack(alignment: .leading, spacing: 5) {
                    Text("How Coach uses this")
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text("Your goal, experience level, and weekly training days help Coach suggest realistic targets and recovery advice.")
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }
            }
        }
    }

    private var unitText: String {
        profile.unitSystem == .metric ? "kg" : "lb"
    }

    private func pickerButton(_ text: String, picker: ProfilePicker) -> some View {
        Button {
            activePicker = picker
        } label: {
            ProfileValueChip(text: text, systemImage: "chevron.down")
        }
        .buttonStyle(.plain)
    }

    private var pickerPresented: Binding<Bool> {
        Binding {
            activePicker != nil
        } set: { isPresented in
            if !isPresented {
                activePicker = nil
            }
        }
    }

    private var pickerTitle: String {
        switch activePicker {
        case .goal:
            return "Goal"
        case .experience:
            return "Experience"
        case .split:
            return "Preferred Split"
        case .units:
            return "Units"
        case .none:
            return "Profile"
        }
    }

    @ViewBuilder
    private var pickerOptions: some View {
        switch activePicker {
        case .goal:
            ForEach(TrainingGoal.allCases) { goal in
                Button(selectionTitle(goal.displayName, isSelected: profile.goal == goal)) {
                    profile.goal = goal
                    activePicker = nil
                }
            }
        case .experience:
            ForEach(ExperienceLevel.allCases) { level in
                Button(selectionTitle(level.displayName, isSelected: profile.experienceLevel == level)) {
                    profile.experienceLevel = level
                    activePicker = nil
                }
            }
        case .split:
            ForEach(SplitType.allCases) { splitType in
                Button(selectionTitle(splitType.displayName, isSelected: profile.preferredSplitType == splitType)) {
                    profile.preferredSplitType = splitType
                    activePicker = nil
                }
            }
        case .units:
            Button(selectionTitle("kg", isSelected: profile.unitSystem == .metric)) {
                profile.unitSystem = .metric
                activePicker = nil
            }
            Button(selectionTitle("lb", isSelected: profile.unitSystem == .imperial)) {
                profile.unitSystem = .imperial
                activePicker = nil
            }
        case .none:
            EmptyView()
        }

        Button("Cancel", role: .cancel) {
            activePicker = nil
        }
    }

    private func selectionTitle(_ title: String, isSelected: Bool) -> String {
        isSelected ? "\(title) (Selected)" : title
    }
}

private enum ProfilePicker {
    case goal
    case experience
    case split
    case units
}

private struct ProfileSummaryCard: View {
    @Environment(\.appTheme) private var appTheme
    let profile: UserProfile

    var body: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ExerciseIconView(iconKey: .genericExercise, size: 54, showBackground: true, isDecorative: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Training Profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .textCase(.uppercase)
                        Text(profile.goal.displayName)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)
                        Text("\(profile.experienceLevel.displayName) · \(profile.preferredSplitType.displayName)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(appTheme.colors.textSecondary)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    ProfileValueChip(text: "\(profile.trainingDaysPerWeek) days/week", systemImage: "calendar")
                    ProfileValueChip(text: profile.unitSystem == .metric ? "kg" : "lb", systemImage: "scalemass")
                    ProfileValueChip(text: shortSplitName, systemImage: "square.grid.2x2")
                }

                Text("Used to tune your targets and weekly recommendations.")
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textSecondary)
            }
        }
    }

    private var shortSplitName: String {
        switch profile.preferredSplitType {
        case .pushPullLegs:
            return "PPL"
        case .upperLower:
            return "Upper/Lower"
        case .fullBody:
            return "Full Body"
        case .broSplit:
            return "Bro Split"
        case .custom:
            return "Custom"
        }
    }
}

private struct ProfileSectionTitle: View {
    @Environment(\.appTheme) private var appTheme
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(appTheme.colors.textSecondary)
    }
}

private struct ProfileSettingRow<Accessory: View>: View {
    @Environment(\.appTheme) private var appTheme

    let icon: String
    let title: String
    let subtitle: String
    let accessory: Accessory

    init(icon: String, title: String, subtitle: String, @ViewBuilder accessory: () -> Accessory) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProfileIcon(systemName: icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            accessory
        }
        .padding(.vertical, 7)
    }
}

private struct ProfileIcon: View {
    @Environment(\.appTheme) private var appTheme
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.headline.weight(.semibold))
            .foregroundStyle(appTheme.colors.accent)
            .frame(width: 36, height: 36)
            .background(appTheme.colors.accentSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(appTheme.colors.accent.opacity(0.2), lineWidth: 1)
            }
    }
}

private struct ProfileValueChip: View {
    @Environment(\.appTheme) private var appTheme

    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(appTheme.colors.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(appTheme.colors.accentSurface, in: Capsule())
        .overlay {
            Capsule()
                .stroke(appTheme.colors.accent.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct ProfileStepperControl: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            stepButton(systemImage: "minus", isDisabled: value <= range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }

            Text("\(value) days")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(appTheme.colors.textPrimary)
                .frame(minWidth: 58)

            stepButton(systemImage: "plus", isDisabled: value >= range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .padding(5)
        .background(appTheme.colors.cardBackgroundElevated, in: Capsule())
        .overlay {
            Capsule()
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
    }

    private func stepButton(systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(isDisabled ? appTheme.colors.textTertiary : appTheme.colors.accent)
                .frame(width: 30, height: 30)
                .background(isDisabled ? appTheme.colors.cardBackground : appTheme.colors.accentSurface, in: Circle())
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
    }
}

private struct ProfileDateChip: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var date: Date

    var body: some View {
        DatePicker("", selection: $date, displayedComponents: .date)
            .labelsHidden()
            .tint(appTheme.colors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(appTheme.colors.accentSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(appTheme.colors.accent.opacity(0.24), lineWidth: 1)
            }
    }
}

private struct ProfileBodyweightField: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var value: Double?
    let unitText: String

    private var text: Binding<String> {
        Binding {
            guard let value else { return "" }
            return value.formatted(.number.precision(.fractionLength(0...1)))
        } set: { newValue in
            value = Double(newValue)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            TextField("Not set", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 58)
                .foregroundStyle(appTheme.colors.accent)

            Text(unitText)
                .foregroundStyle(appTheme.colors.accent)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(appTheme.colors.accentSurface, in: Capsule())
        .overlay {
            Capsule()
                .stroke(appTheme.colors.accent.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct ProfileNotesEditor: View {
    @Environment(\.appTheme) private var appTheme
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("No injury notes added")
                    .font(.subheadline)
                    .foregroundStyle(appTheme.colors.textTertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 14)
            }

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 118)
                .padding(8)
                .foregroundStyle(appTheme.colors.textPrimary)
        }
        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(appTheme.colors.cardBorder, lineWidth: 1)
        }
    }
}

private struct ProfileDivider: View {
    @Environment(\.appTheme) private var appTheme

    var body: some View {
        Rectangle()
            .fill(appTheme.colors.cardBorder)
            .frame(height: 1)
            .padding(.leading, 48)
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

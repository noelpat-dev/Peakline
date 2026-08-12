import SwiftData
import SwiftUI

struct SettingsProfileSnapshot: Sendable {
    let id: UUID
    let goalTitle: String
    let experienceTitle: String
    let trainingDaysPerWeek: Int

    init(_ profile: UserProfile) {
        id = profile.id
        goalTitle = profile.goal.displayName
        experienceTitle = profile.experienceLevel.displayName
        trainingDaysPerWeek = profile.trainingDaysPerWeek
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @AppStorage("appTheme") private var storedTheme = AppTheme.black.rawValue
    @AppStorage("appAppearance") private var storedAppearance = AppAppearance.system.rawValue
    @State private var profile: UserProfile?
    @State private var showingProfileEditor = false
    @State private var didLoadProfile = false

    private let initialProfileSnapshot: SettingsProfileSnapshot?

    init(initialProfileSnapshot: SettingsProfileSnapshot? = nil) {
        self.initialProfileSnapshot = initialProfileSnapshot
    }

    var body: some View {
        NavigationStack {
            FitnessScreen {
                DashboardSection(title: "Profile") {
                    if let profile {
                        NavigationLink {
                            ProfileEditorView(profile: profile)
                        } label: {
                            SettingsCardRow(
                                title: profile.goal.displayName,
                                subtitle: PeaklineText.joinedMetadata([
                                    profile.experienceLevel.displayName,
                                    "\(profile.trainingDaysPerWeek) days/week"
                                ]),
                                systemImage: "person.crop.circle"
                            )
                        }
                        .buttonStyle(PressableCardButtonStyle())
                        .accessibilityIdentifier("settings-profile")
                    } else if let initialProfileSnapshot {
                        Button {
                            openPreparedProfile()
                        } label: {
                            SettingsCardRow(
                                title: initialProfileSnapshot.goalTitle,
                                subtitle: PeaklineText.joinedMetadata([
                                    initialProfileSnapshot.experienceTitle,
                                    "\(initialProfileSnapshot.trainingDaysPerWeek) days/week"
                                ]),
                                systemImage: "person.crop.circle"
                            )
                        }
                        .buttonStyle(PressableCardButtonStyle())
                        .accessibilityIdentifier("settings-profile")
                    } else {
                        Button {
                            createProfile()
                        } label: {
                            SettingsCardRow(
                                title: "Create Profile",
                                subtitle: "Add your goal and training details.",
                                systemImage: "person.crop.circle.badge.plus",
                                showsChevron: false
                            )
                        }
                        .buttonStyle(PressableCardButtonStyle())
                        .accessibilityIdentifier("settings-create-profile")
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
                            .buttonStyle(PeaklineButtonPressStyle())
                            .accessibilityIdentifier("settings-exercise-library")

                            SettingsDivider()

                            NavigationLink {
                                ProgressContentView()
                            } label: {
                                SettingsInlineRow(title: "Progress", subtitle: "Charts, PRs, and lift trends", systemImage: "chart.line.uptrend.xyaxis")
                            }
                            .buttonStyle(PeaklineButtonPressStyle())
                            .accessibilityIdentifier("settings-progress")

                            SettingsDivider()

                            NavigationLink {
                                CoachRouteDestinationView()
                            } label: {
                                SettingsInlineRow(title: "Coach", subtitle: "Targets, warnings, and weekly review", systemImage: "sparkles")
                            }
                            .buttonStyle(PeaklineButtonPressStyle())
                            .accessibilityIdentifier("settings-coach")
                        }
                    }
                }

                DashboardSection(title: "Workout Tools") {
                    NavigationLink {
                        PlateCalculatorView()
                    } label: {
                        SettingsCardRow(
                            title: "Plate Calculator",
                            subtitle: "Calculate metric plates here or beside each live set.",
                            systemImage: "scalemass"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityIdentifier("settings-plate-calculator")
                }

                DashboardSection(title: "Appearance") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsCardRow(
                            title: "Appearance",
                            subtitle: appearanceStatus,
                            systemImage: "paintpalette"
                        )
                    }
                    .buttonStyle(PressableCardButtonStyle())
                    .accessibilityIdentifier("settings-appearance")
                }

                DashboardSection(title: "Apple Health") {
                    FitnessCard(style: .compact, padding: 12) {
                        VStack(spacing: 0) {
                        NavigationLink {
                            SleepSettingsStandaloneView()
                        } label: {
                            SettingsInlineRow(title: "Sleep Settings", subtitle: "Reminders, sources, and recovery coaching", systemImage: "moon.zzz")
                        }
                        .buttonStyle(PeaklineButtonPressStyle())

                        SettingsDivider()

                        NavigationLink {
                            HealthKitSettingsView()
                        } label: {
                            SettingsInlineRow(title: "Apple Health Sync", subtitle: "Nutrition sharing and activity context", systemImage: "heart.text.square")
                        }
                        .buttonStyle(PeaklineButtonPressStyle())
                        }
                    }
                }

                DashboardSection(title: "Safety") {
                    FitnessCard(style: .compact) {
                        HStack(alignment: .top, spacing: 12) {
                            FitnessIconBadge(
                                systemImage: "cross.case",
                                size: 40,
                                tint: appTheme.colors.warning,
                                background: appTheme.colors.warning.opacity(0.14)
                            )

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
                                AccountBackupView()
                            } label: {
                                SettingsInlineRow(title: "Account & Backup", subtitle: "Firebase sign-in, encrypted save, and restore", systemImage: "lock.shield")
                            }
                            .buttonStyle(PeaklineButtonPressStyle())

                            SettingsDivider()

                            NavigationLink {
                                BackupExportView()
                            } label: {
                                SettingsInlineRow(title: "Backup & Export", subtitle: "Create local JSON and CSV files", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PeaklineButtonPressStyle())

                            SettingsDivider()

                            HStack(spacing: 12) {
                                FitnessIconBadge(
                                    systemImage: "externaldrive.badge.person.crop",
                                    size: 36,
                                    tint: appTheme.colors.textSecondary,
                                    background: appTheme.colors.cardBackgroundElevated
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Encrypted backup ready")
                                        .font(.headline)
                                        .foregroundStyle(appTheme.colors.textPrimary)
                                    Text("Peakline stores fast local data with SwiftData and protects a full-app backup in Firebase after you sign in.")
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

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("settings-screen")
            .navigationDestination(isPresented: $showingProfileEditor) {
                if let profile {
                    ProfileEditorView(profile: profile)
                }
            }
        }
        .onAppear {
            guard !didLoadProfile else { return }
            didLoadProfile = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                loadProfile()
            }
        }
    }

    private func createProfile() {
        let newProfile = UserProfile()
        modelContext.insert(newProfile)
        do {
            try modelContext.save()
            profile = newProfile
        } catch {
            modelContext.delete(newProfile)
        }
    }

    private func loadProfile() {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        profile = try? modelContext.fetch(descriptor).first
    }

    private func openPreparedProfile() {
        loadProfile()
        showingProfileEditor = profile != nil
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: storedTheme) ?? .black
    }

    private var selectedAppearance: AppAppearance {
        AppAppearance.launchArgumentOverride
            ?? AppAppearance(rawValue: storedAppearance)
            ?? .system
    }

    private var appearanceStatus: String {
        PeaklineText.joinedMetadata([
            selectedAppearance.displayName,
            selectedTheme.displayName
        ])
    }
}

private struct SettingsCardRow: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String
    let systemImage: String
    var showsChevron = true

    var body: some View {
        FitnessCard(style: .compact) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        SettingsRowIcon(systemImage: systemImage)
                        titleLabel
                        Spacer(minLength: 8)
                        chevron
                    }

                    subtitleLabel
                }
            } else {
                HStack(spacing: 12) {
                    SettingsRowIcon(systemImage: systemImage)

                    VStack(alignment: .leading, spacing: 4) {
                        titleLabel
                        subtitleLabel
                    }

                    Spacer()
                    chevron
                }
            }
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(AppTypography.sectionTitle)
            .foregroundStyle(appTheme.colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subtitleLabel: some View {
        Text(subtitle)
            .font(AppTypography.body)
            .foregroundStyle(appTheme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var chevron: some View {
        if showsChevron {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(appTheme.colors.textTertiary)
                .frame(minWidth: appTheme.metrics.minimumHitTarget, minHeight: appTheme.metrics.minimumHitTarget)
                .accessibilityHidden(true)
        }
    }
}

private struct SettingsInlineRow: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        SettingsRowIcon(systemImage: systemImage)
                        titleLabel
                        Spacer(minLength: 8)
                        chevron
                    }

                    subtitleLabel
                }
            } else {
                HStack(spacing: 12) {
                    SettingsRowIcon(systemImage: systemImage)

                    VStack(alignment: .leading, spacing: 3) {
                        titleLabel
                        subtitleLabel
                    }

                    Spacer()
                    chevron
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    private var titleLabel: some View {
        Text(title)
            .font(AppTypography.sectionTitle)
            .foregroundStyle(appTheme.colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var subtitleLabel: some View {
        Text(subtitle)
            .font(AppTypography.metadata)
            .foregroundStyle(appTheme.colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(appTheme.colors.textTertiary)
            .frame(minWidth: appTheme.metrics.minimumHitTarget, minHeight: appTheme.metrics.minimumHitTarget)
            .accessibilityHidden(true)
    }
}

private struct SettingsRowIcon: View {
    let systemImage: String

    var body: some View {
        FitnessIconBadge(systemImage: systemImage)
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

private struct AppearanceSettingsView: View {
    @Environment(\.appTheme) private var appTheme
    @AppStorage("appTheme") private var storedTheme = AppTheme.black.rawValue
    @AppStorage("appAppearance") private var storedAppearance = AppAppearance.system.rawValue

    private let availableThemes = AppTheme.allCases

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
        FitnessScreen {
            DashboardSection(title: "Accent Colour") {
                FitnessCard(padding: appTheme.metrics.spacing10) {
                    VStack(spacing: appTheme.metrics.spacing6) {
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

            DashboardSection(title: "Mode") {
                FitnessCard(padding: appTheme.metrics.spacing10) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92), spacing: appTheme.metrics.spacing8)],
                        spacing: appTheme.metrics.spacing8
                    ) {
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
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("appearance-settings-screen")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.displayName) accent colour")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("theme-option-\(theme.rawValue)")
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
            return "Adaptive monochrome accents"
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appearance.displayName) appearance")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("appearance-option-\(appearance.rawValue)")
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

    var body: some View {
        FitnessScreen(locksHorizontalScrolling: true) {
            ProfileSummaryCard(profile: profile)
            trainingPreferencesSection
            bodySection
            notesSection
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("profile-editor-screen")
        .onDisappear {
            profile.updatedAt = .now
            try? modelContext.save()
        }
    }

    private var trainingPreferencesSection: some View {
        DashboardSection(title: "Training Profile") {
            FitnessCard(style: .compact, padding: appTheme.metrics.spacing12) {
                VStack(spacing: appTheme.metrics.spacing8) {
                    ProfileSettingRow(icon: "target", title: "Goal", subtitle: "What you are training toward.") {
                        pickerButton(
                            profile.goal.displayName,
                            label: "Goal",
                            identifier: "profile-goal-menu",
                            picker: .goal
                        )
                    }

                    ProfileDivider()

                    ProfileSettingRow(icon: "chart.line.uptrend.xyaxis", title: "Experience", subtitle: "Your self-described lifting experience.") {
                        pickerButton(
                            profile.experienceLevel.displayName,
                            label: "Experience",
                            identifier: "profile-experience-menu",
                            picker: .experience
                        )
                    }

                    ProfileDivider()

                    ProfileSettingRow(icon: "number", title: "Training days", subtitle: "How often you aim to train each week.") {
                        ProfileStepperControl(value: $profile.trainingDaysPerWeek, range: 1...7)
                    }

                    ProfileDivider()

                    ProfileSettingRow(icon: "calendar.badge.clock", title: "Lifting start", subtitle: "An optional date for your profile.") {
                        ProfileDateChip(date: Binding($profile.liftingStartDate, replacingNilWith: .now))
                    }
                }
            }
        }
    }

    private var bodySection: some View {
        DashboardSection(title: "Body") {
            FitnessCard(style: .compact, padding: appTheme.metrics.spacing12) {
                ProfileSettingRow(
                    icon: "scalemass",
                    title: "Bodyweight",
                    subtitle: "Optional profile reference in \(unitText)."
                ) {
                    ProfileBodyweightField(value: $profile.bodyweight, unitText: unitText)
                }
            }
        }
    }

    private var notesSection: some View {
        DashboardSection(title: "Health & Notes") {
            FitnessCard(style: .compact) {
                VStack(alignment: .leading, spacing: appTheme.metrics.spacing12) {
                    HStack(alignment: .top, spacing: 12) {
                        ProfileIcon(systemName: "cross.case")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Injury notes")
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                            Text("Private reference notes. Workouts are not changed automatically.")
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ProfileNotesEditor(text: Binding($profile.injuryNotes, replacingNilWith: ""))

                    if !profile.exercisesToAvoid.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved exercises to avoid")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .textCase(.uppercase)

                            Text("Stored for reference only.")
                                .font(.caption)
                                .foregroundStyle(appTheme.colors.textTertiary)

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

    private var unitText: String {
        profile.unitSystem == .metric ? "kg" : "lb"
    }

    private func pickerButton(
        _ text: String,
        label: String,
        identifier: String,
        picker: ProfilePicker
    ) -> some View {
        Menu {
            pickerOptions(for: picker)
        } label: {
            ProfileValueChip(text: text, systemImage: "chevron.down")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(text)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func pickerOptions(for picker: ProfilePicker) -> some View {
        switch picker {
        case .goal:
            ForEach(TrainingGoal.allCases) { goal in
                Button(selectionTitle(goal.displayName, isSelected: profile.goal == goal)) {
                    profile.goal = goal
                }
                .accessibilityLabel(goal.displayName)
                .accessibilityValue(profile.goal == goal ? "Selected" : "Not selected")
                .accessibilityIdentifier("profile-goal-option-\(goal.rawValue)")
            }
        case .experience:
            ForEach(ExperienceLevel.allCases) { level in
                Button(selectionTitle(level.displayName, isSelected: profile.experienceLevel == level)) {
                    profile.experienceLevel = level
                }
                .accessibilityLabel(level.displayName)
                .accessibilityValue(profile.experienceLevel == level ? "Selected" : "Not selected")
                .accessibilityIdentifier("profile-experience-option-\(level.rawValue)")
            }
        }
    }

    private func selectionTitle(_ title: String, isSelected: Bool) -> String {
        isSelected ? "\(title) (Selected)" : title
    }
}

private enum ProfilePicker {
    case goal
    case experience
}

private struct ProfileSummaryCard: View {
    @Environment(\.appTheme) private var appTheme
    let profile: UserProfile

    var body: some View {
        FitnessCard(style: .compact) {
            HStack(alignment: .center, spacing: appTheme.metrics.spacing12) {
                ProfileIcon(systemName: "person.crop.circle")

                VStack(alignment: .leading, spacing: appTheme.metrics.spacing4) {
                    Text("Profile overview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .textCase(.uppercase)
                    Text(profile.goal.displayName)
                        .font(.headline)
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(profile.experienceLevel.displayName)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                Spacer(minLength: appTheme.metrics.spacing8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profile overview")
        .accessibilityValue("\(profile.goal.displayName), \(profile.experienceLevel.displayName)")
        .accessibilityIdentifier("profile-overview")
    }
}

private struct ProfileSettingRow<Accessory: View>: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    @ViewBuilder
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    inlineLayout
                    stackedLayout
                }
            }
        }
        .padding(.vertical, appTheme.metrics.spacing4)
    }

    private var inlineLayout: some View {
        HStack(alignment: .center, spacing: appTheme.metrics.spacing12) {
            label
                .fixedSize(horizontal: true, vertical: true)

            Spacer(minLength: appTheme.metrics.spacing10)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: appTheme.metrics.spacing10) {
            label

            accessory
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var label: some View {
        HStack(alignment: .top, spacing: appTheme.metrics.spacing12) {
            ProfileIcon(systemName: icon)

            VStack(alignment: .leading, spacing: appTheme.metrics.spacing4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(appTheme.colors.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            .accessibilityHidden(true)
    }
}

private struct ProfileValueChip: View {
    @Environment(\.appTheme) private var appTheme

    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(appTheme.colors.accent)
        .padding(.horizontal, appTheme.metrics.spacing12)
        .frame(minHeight: appTheme.metrics.minimumHitTarget)
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
                .accessibilityLabel("Training days")
                .accessibilityValue(PeaklineText.count(value, singular: "day"))
                .accessibilityIdentifier("profile-training-days-value")

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
                .frame(width: appTheme.metrics.minimumHitTarget, height: appTheme.metrics.minimumHitTarget)
                .background(isDisabled ? appTheme.colors.cardBackground : appTheme.colors.accentSurface, in: Circle())
        }
        .disabled(isDisabled)
        .buttonStyle(.plain)
        .accessibilityLabel(systemImage == "minus" ? "Decrease training days" : "Increase training days")
        .accessibilityValue(PeaklineText.count(value, singular: "day"))
        .accessibilityIdentifier(systemImage == "minus" ? "profile-training-days-decrease" : "profile-training-days-increase")
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
            .frame(minHeight: appTheme.metrics.minimumHitTarget)
            .background(appTheme.colors.accentSurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(appTheme.colors.accent.opacity(0.24), lineWidth: 1)
            }
            .accessibilityLabel("Lifting start")
            .accessibilityValue(date.formatted(date: .abbreviated, time: .omitted))
            .accessibilityIdentifier("profile-lifting-start")
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
                .frame(minWidth: 72, maxWidth: 100, minHeight: appTheme.metrics.minimumHitTarget)
                .foregroundStyle(appTheme.colors.accent)
                .accessibilityLabel("Bodyweight")
                .accessibilityValue(value.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(unitText)" } ?? "Not set")
                .accessibilityIdentifier("profile-bodyweight-field")

            Text(unitText)
                .foregroundStyle(appTheme.colors.accent)
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, appTheme.metrics.spacing12)
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
                .accessibilityLabel("Injury notes")
                .accessibilityValue(text.isEmpty ? "Not set" : text)
                .accessibilityIdentifier("profile-injury-notes")
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
            .padding(.leading, appTheme.metrics.rowIconSize + appTheme.metrics.spacing12)
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

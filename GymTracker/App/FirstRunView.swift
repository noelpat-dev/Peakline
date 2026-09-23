import SwiftData
import SwiftUI

struct FirstRunView: View {
    @Environment(\.appTheme) private var theme
    let start: (SeedDataService.InitialProgramme) -> Void
    let importFinished: () -> Void
    @State private var programme = SeedDataService.InitialProgramme.blank
    @State private var showsImport = false
    @State private var showsDemo = false
    @State private var starting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "mountain.2.fill")
                            .font(.largeTitle).foregroundStyle(theme.colors.accent)
                            .accessibilityHidden(true)
                        Text("Your training. Your data.")
                            .font(.largeTitle.bold())
                        Text("Build a programme and start logging on this device. An account and permissions are optional.")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Starting programme", selection: $programme) {
                            ForEach(SeedDataService.InitialProgramme.allCases) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .pickerStyle(.menu)
                        Text("Templates are editable starting points. They contain no workout history or suggested starting weights.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Start fresh") {
                            guard !starting else { return }
                            starting = true
                            start(programme)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                        .disabled(starting)
                        .accessibilityIdentifier("onboarding-start-fresh")
                        Button("Import my backup") { showsImport = true }
                            .buttonStyle(SecondaryFitnessButtonStyle())
                            .accessibilityIdentifier("onboarding-import")
                    }
                    Button("Try a demo") { showsDemo = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("onboarding-demo")
                    Text("Your records stay local unless you explicitly connect encrypted backup. Optional barcode searches use an external service.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 600)
            }
            .background(theme.colors.backgroundPrimary)
            .navigationTitle("Welcome to Peakline")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showsImport, onDismiss: importFinished) {
            NavigationStack {
                BackupExportView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showsImport = false }
                    } }
            }
        }
        .fullScreenCover(isPresented: $showsDemo) {
            DemoWorkspaceView()
        }
    }
}

/// A deliberately self-contained preview of planning and logging. Its graph
/// contains only a transient database and local view preferences: it never
/// constructs the personal app's account, HealthKit, timer notification, file,
/// or shared warm-cache services.
struct DemoWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var container: ModelContainer?
    @State private var error: String?

    var body: some View {
        Group {
            if let container {
                DemoTrainingView(leave: { dismiss() })
                    .modelContainer(container)
            } else {
                VStack(spacing: 16) {
                    if let error { Text(error) }
                    else { SwiftUI.ProgressView("Preparing demo") }
                    Button("Leave demo") { dismiss() }
                }
                .padding()
            }
        }
        .task {
            guard container == nil else { return }
            do {
                let demo = try PeaklineModelStore.makeContainer(isStoredInMemoryOnly: true)
                try SeedDataService.completeSetup(.fullBody, in: demo.mainContext)
                container = demo
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct DemoTrainingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TrainingSplit.createdAt) private var splits: [TrainingSplit]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var workouts: [WorkoutSession]
    let leave: () -> Void
    @State private var darkAppearance = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Demo · isolated sample data")
                        .font(.headline)
                    Text("Try editing a programme and logging sample sets. Leaving discards this demo; your personal workspace is untouched.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(splits) { split in
                    Section {
                        TextField("Programme name", text: Binding(
                            get: { split.name },
                            set: { split.name = $0; save() }
                        ))
                        ForEach(split.exercises.sorted { $0.orderIndex < $1.orderIndex }) { exercise in
                            HStack {
                                Text(exercise.exerciseNameSnapshot)
                                Spacer()
                                Text("\(exercise.targetSets) × \(exercise.minReps)–\(exercise.maxReps)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let ordered = split.exercises.sorted { $0.orderIndex < $1.orderIndex }
                            for index in offsets { context.delete(ordered[index]) }
                            save()
                        }
                        NavigationLink("Log a demo workout") { DemoLoggerView(split: split) }
                    } header: { Text("Programme") }
                }
                Section("Demo history") {
                    if workouts.isEmpty { Text("No demo workouts yet") }
                    ForEach(workouts) { workout in
                        VStack(alignment: .leading) {
                            Text(workout.splitNameSnapshot)
                            Text("\(workout.exerciseLogs.count) exercises · sample workout")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Demo appearance") {
                    Toggle("Dark appearance", isOn: $darkAppearance)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Try Peakline")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Leave demo", action: leave).accessibilityIdentifier("leave-demo")
            } }
        }
        .preferredColorScheme(darkAppearance ? .dark : .light)
    }

    private func save() {
        do { try context.save() }
        catch { self.error = error.localizedDescription; context.rollback() }
    }
}

private struct DemoLoggerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let split: TrainingSplit
    @State private var weight = 0.0
    @State private var reps = 8
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        Form {
            Section("Sample set") {
                Text(split.exercises.sorted { $0.orderIndex < $1.orderIndex }.first?.exerciseNameSnapshot ?? "Sample exercise")
                TextField("Load (kg)", value: $weight, format: .number)
                    .keyboardType(.decimalPad)
                Stepper("\(reps) reps", value: $reps, in: 1...100)
                Text("Demo values are examples you enter, not recommended training loads.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Save demo workout") { save() }.disabled(saved)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Demo workout")
    }

    private func save() {
        guard !saved, weight.isFinite, weight >= 0 else { return }
        saved = true
        let session = WorkoutSession(splitId: split.id, splitNameSnapshot: split.name, completed: true)
        if let source = split.exercises.sorted(by: { $0.orderIndex < $1.orderIndex }).first {
            let log = ExerciseLog(workoutSessionId: session.id, exerciseId: source.exerciseId,
                                  exerciseNameSnapshot: source.exerciseNameSnapshot, orderIndex: 0,
                                  targetSets: 1, minReps: source.minReps, maxReps: source.maxReps)
            let set = SetLog(exerciseLogId: log.id, setNumber: 1, weight: weight, reps: reps, completed: true)
            set.exerciseLog = log
            log.setLogs = [set]
            log.workoutSession = session
            session.exerciseLogs = [log]
        }
        context.insert(session)
        do { try context.save(); dismiss() }
        catch { self.error = error.localizedDescription; context.rollback(); saved = false }
    }
}

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupExportView: View {
    @Environment(\.appTheme) private var appTheme
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var workouts: [WorkoutSession]

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \TrainingSplit.name)
    private var splits: [TrainingSplit]

    @State private var exportedFile: URL?
    @State private var exportStatus: String?
    @State private var exportError: String?
    @State private var showingArchiveImporter = false
    @State private var showingRestoreConfirmation = false
    @State private var pendingArchiveData: Data?
    @State private var archivePreview: PortableArchivePreview?
    @State private var archivePassphrase = ""

    private let exportService = LocalBackupExportService()
    private let archiveService = PortableArchiveService()

    var body: some View {
        FitnessScreen(
            title: "Backup & Export",
            subtitle: "Create local files for your workout data.",
            systemImage: "square.and.arrow.up"
        ) {
            FitnessCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Local only", systemImage: "lock.fill")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)

                    Text("Exports are written to a temporary local file so you can save or share them yourself. Peakline does not upload this data anywhere.")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                MetricTile(label: "Workouts", value: "\(workouts.count)", caption: "Sessions", systemImage: "calendar")
                MetricTile(label: "Exercises", value: "\(exercises.count)", caption: "Library", systemImage: "dumbbell")
            }

            exportActionCard(
                title: "Export JSON Backup",
                subtitle: "Full local backup with splits, exercise library, workout sessions, exercise logs, sets, targets, ratings, and notes.",
                systemImage: "doc.badge.gearshape",
                action: exportJSON
            )

            exportActionCard(
                title: "Export CSV",
                subtitle: "Readable workout set list for spreadsheets: date, split, mode, exercise, weight, reps, RPE, completion, duration, and rating.",
                systemImage: "tablecells",
                action: exportCSV
            )

            exportActionCard(
                title: "Export Full Workspace Archive",
                subtitle: "Portable local archive of your profile, programmes, workouts, coaching, nutrition, hydration, sleep, templates, and preferences. This file is unencrypted unless you protect it with a passphrase.",
                systemImage: "archivebox",
                action: exportFullArchive
            )
            SecureField("Optional archive passphrase", text: $archivePassphrase)
                .textFieldStyle(.roundedBorder)
                .font(AppTypography.body)

            FitnessCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Restore from archive", systemImage: "arrow.down.doc")
                        .font(AppTypography.sectionTitle)
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text("Peakline previews the archive and asks before replacing this workspace. Older workout-only files are identified separately.")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Choose Archive") { showingArchiveImporter = true }
                        .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }

            if let exportedFile {
                FitnessCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(exportStatus ?? "Export ready", systemImage: "checkmark.circle.fill")
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(appTheme.successColor)

                        Text(exportedFile.lastPathComponent)
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .lineLimit(2)

                        ShareLink(item: exportedFile) {
                            Label("Share Exported File", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                    }
                }
            }

            if let exportError {
                FitnessCard {
                    Label(exportError, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.body)
                        .foregroundStyle(appTheme.dangerColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Backup & Export")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingArchiveImporter,
            allowedContentTypes: [.data, .json],
            allowsMultipleSelection: false
        ) { result in
            handleArchiveSelection(result)
        }
        .confirmationDialog(
            "Replace this workspace?",
            isPresented: $showingRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button(archivePreview?.scope == .workoutOnly ? "Import Workout Data" : "Replace Workspace", role: .destructive) { restoreArchive() }
            Button("Cancel", role: .cancel) { pendingArchiveData = nil; archivePreview = nil }
        } message: {
            if let archivePreview {
                Text(archivePreview.scope == .workoutOnly
                     ? "Workout-only archive with \(archivePreview.counts?.workoutCount ?? 0) sessions. Other local categories will be preserved."
                     : "Full workspace archive with \(archivePreview.counts?.totalRecordCount ?? 0) records. Existing local data, settings, and templates will be replaced.")
            }
        }
    }

    private func exportActionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    Label(title, systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
            }
        }
    }

    private func exportJSON() {
        do {
            exportedFile = try exportService.exportJSON(workouts: workouts, exercises: exercises, splits: splits)
            exportStatus = "JSON backup ready"
            exportError = nil
        } catch {
            exportError = "Could not create JSON backup: \(error.localizedDescription)"
        }
    }

    private func exportCSV() {
        do {
            exportedFile = try exportService.exportCSV(workouts: workouts)
            exportStatus = "CSV export ready"
            exportError = nil
        } catch {
            exportError = "Could not create CSV export: \(error.localizedDescription)"
        }
    }

    private func exportFullArchive() {
        do {
            let data = try archiveService.makeFullArchive(
                in: modelContext,
                passphrase: archivePassphrase.isEmpty ? nil : archivePassphrase
            )
            exportedFile = try archiveService.writeArchive(data)
            exportStatus = archivePassphrase.isEmpty ? "Unencrypted full archive ready" : "Protected full archive ready"
            exportError = nil
        } catch {
            exportError = "Could not create full archive: \(error.localizedDescription)"
        }
    }

    private func handleArchiveSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let preview = (try? archiveService.preview(data, passphrase: archivePassphrase.isEmpty ? nil : archivePassphrase)) ?? archiveService.previewLegacy(data)
            pendingArchiveData = data
            archivePreview = preview
            showingRestoreConfirmation = true
            exportError = nil
        } catch {
            exportError = "Could not read archive: \(error.localizedDescription)"
        }
    }

    private func restoreArchive() {
        guard let pendingArchiveData else { return }
        do {
            _ = try archiveService.importArchive(
                from: pendingArchiveData,
                into: modelContext,
                replaceExisting: archivePreview?.scope == .fullWorkspace,
                passphrase: archivePassphrase.isEmpty ? nil : archivePassphrase
            )
            exportStatus = "Workspace restored"
            exportError = nil
        } catch {
            exportError = "Could not restore archive: \(error.localizedDescription)"
        }
        self.pendingArchiveData = nil
        archivePreview = nil
    }
}

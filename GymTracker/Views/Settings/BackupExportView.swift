import SwiftData
import SwiftUI

struct BackupExportView: View {
    @Environment(\.appTheme) private var appTheme

    @Query(sort: \WorkoutSession.date, order: .reverse)
    private var workouts: [WorkoutSession]

    @Query(sort: \Exercise.name)
    private var exercises: [Exercise]

    @Query(sort: \TrainingSplit.name)
    private var splits: [TrainingSplit]

    @State private var exportedFile: URL?
    @State private var exportStatus: String?
    @State private var exportError: String?

    private let exportService = LocalBackupExportService()

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
}

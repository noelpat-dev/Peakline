import SwiftData
import SwiftUI

struct AccountBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var readiness: AccountReadiness = .needsSignIn
    @State private var latestMetadata: FullAppBackupMetadata?
    @State private var backupPassphrase = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showingRestoreConfirmation = false

    private let accountService = FirebaseAccountService()
    private let backupCoordinator = BackupCoordinator()

    var body: some View {
        FitnessScreen(
            title: "Account & Backup",
            subtitle: "Firebase account, encrypted backup, and durable restore.",
            systemImage: "lock.shield"
        ) {
            accountStatusCard
            encryptedBackupCard

            if let statusMessage {
                FitnessCard {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.successColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let errorMessage {
                FitnessCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.dangerColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Account & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .alert("Restore encrypted backup?", isPresented: $showingRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                Task { await restoreCloudBackup() }
            }
        } message: {
            Text("This replaces the current local Peakline data with the latest Firebase backup. Export a JSON backup first if you want a separate safety copy.")
        }
    }

    private var accountStatusCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(readiness.title, systemImage: readiness.isReady ? "checkmark.shield.fill" : "person.crop.circle.badge.exclamationmark")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(readiness.message)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label(isWorking ? "Checking" : "Refresh", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .disabled(isWorking)

                    Button(role: .destructive) {
                        signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .disabled(isWorking || !readiness.isReady)
                }
            }
        }
    }

    private var encryptedBackupCard: some View {
        FitnessCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Encrypted Firebase Backup", systemImage: "externaldrive.badge.person.crop")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(appTheme.colors.textPrimary)

                Text(cloudBackupDescription)
                    .font(AppTypography.body)
                    .foregroundStyle(appTheme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("Backup passphrase", text: $backupPassphrase)
                    .textContentType(.password)
                    .accessibilityIdentifier("account-backup-passphrase")
                    .padding(12)
                    .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))
                    .disabled(isWorking || !readiness.isReady)

                HStack(spacing: 10) {
                    Button {
                        Task { await saveCloudBackup() }
                    } label: {
                        Label(isWorking ? "Working" : "Save Now", systemImage: "lock.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .disabled(isWorking || !readiness.isReady)

                    Button {
                        showingRestoreConfirmation = true
                    } label: {
                        Label("Restore", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .disabled(isWorking || latestMetadata == nil || !readiness.isReady)
                }
            }
        }
    }

    private var cloudBackupDescription: String {
        guard let latestMetadata else {
            return "No encrypted Firebase backup was found for this account. Save one before deleting or reinstalling the app."
        }

        let date = latestMetadata.createdAt.formatted(date: .abbreviated, time: .shortened)
        return "Last saved \(date) with \(latestMetadata.counts.workoutCount) workouts, \(latestMetadata.counts.foodLogCount) food logs, \(latestMetadata.counts.sleepCount) sleep sessions, and \(latestMetadata.counts.hydrationCount) hydration entries."
    }

    private func refresh() async {
        isWorking = true
        defer { isWorking = false }

        readiness = await accountService.readiness()
        guard readiness.isReady else {
            latestMetadata = nil
            return
        }

        switch await backupCoordinator.latestMetadata() {
        case .available(let metadata):
            latestMetadata = metadata
            errorMessage = nil
        case .noBackup:
            latestMetadata = nil
            errorMessage = nil
        case .unavailable(let message), .failed(let message):
            latestMetadata = nil
            errorMessage = message
        }
    }

    private func saveCloudBackup() async {
        isWorking = true
        defer { isWorking = false }

        switch await backupCoordinator.saveLatestBackup(in: modelContext, passphrase: backupPassphrase) {
        case .saved(let metadata):
            latestMetadata = metadata
            statusMessage = "Saved encrypted backup with \(metadata.counts.totalRecordCount) records."
            errorMessage = nil
        case .keptExistingBackup(let metadata):
            latestMetadata = metadata
            statusMessage = "Kept existing Firebase backup because the current local store has no user data."
            errorMessage = nil
        case .passphraseRequired:
            errorMessage = "Enter your backup passphrase to save this encrypted backup."
        case .unavailable(let message), .failed(let message):
            errorMessage = message
        }
    }

    private func restoreCloudBackup() async {
        isWorking = true
        defer { isWorking = false }

        switch await backupCoordinator.restoreLatestBackup(in: modelContext, replaceExisting: true, passphrase: backupPassphrase) {
        case .restored(let summary):
            statusMessage = "Restored \(summary.counts.totalRecordCount) records from Firebase."
            errorMessage = nil
            await refresh()
        case .skippedNoBackup:
            errorMessage = "No Firebase backup was found."
        case .skippedStoreNotEmpty:
            errorMessage = "Current local data is not empty. Confirm restore before replacing it."
        case .passphraseRequired:
            errorMessage = "Enter the backup passphrase you used when saving this backup."
        case .unavailable(let message), .failed(let message):
            errorMessage = message
        }
    }

    private func signOut() {
        do {
            if let account = accountService.currentRecord() {
                try? KeychainBackupEncryptionKeyCache(accountIdentifier: account.userIdentifier).delete()
            }
            try accountService.signOut()
            latestMetadata = nil
            statusMessage = "Signed out of Firebase backup."
            errorMessage = nil
            Task { await refresh() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

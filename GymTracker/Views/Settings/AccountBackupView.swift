import FirebaseCore
import SwiftData
import SwiftUI

struct AccountBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme

    @State private var readiness: AccountReadiness = .needsSignIn
    @State private var latestMetadata: FullAppBackupMetadata?
    @State private var backupPassphrase = ""
    @State private var accountEmail = ""
    @State private var accountPassword = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showingRestoreConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var backupConnected = false

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
        .alert("Delete backup account and cloud copy?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("Your local Peakline data stays on this device. The remote backup is removed first, then the account is deleted. You will need your account password.")
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

                if readiness.isReady && !backupConnected {
                    Button {
                        Task { await connectBackup() }
                    } label: {
                        Label("Connect This Workspace for Backup", systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryFitnessButtonStyle())
                    .disabled(isWorking)
                }

                if !readiness.isReady {
                    TextField("Account email", text: $accountEmail)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .padding(12)
                        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))
                    SecureField("Account password", text: $accountPassword)
                        .textContentType(.password)
                        .padding(12)
                        .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))
                    HStack(spacing: 10) {
                        Button("Sign In") { Task { await signIn() } }
                            .buttonStyle(PrimaryFitnessButtonStyle())
                            .disabled(isWorking)
                        Button("Create Account") { Task { await createAccount() } }
                            .buttonStyle(SecondaryFitnessButtonStyle())
                            .disabled(isWorking)
                    }
                    Button("Forgot password?") { Task { await recoverPassword() } }
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(appTheme.colors.accent)
                }

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

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Account & Cloud Backup", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .disabled(isWorking || !readiness.isReady || !backupConnected)
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

        do {
            let workspace = try WorkspaceService.metadata(in: modelContext)
            backupConnected = workspace.backupProjectID != nil && workspace.backupUID != nil
        } catch { backupConnected = false }

        switch await backupCoordinator.latestMetadata(in: modelContext) {
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
        case .savedWithCredentialWarning(let metadata, let warning):
            latestMetadata = metadata
            statusMessage = "Saved encrypted backup. Keychain cache warning: (warning)"
            errorMessage = nil
        case .skippedUnchanged(let metadata):
            latestMetadata = metadata
            statusMessage = "Backup is unchanged; the existing encrypted copy was kept."
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

    private func connectBackup() async {
        guard let account = accountService.currentRecord(),
              let projectID = FirebaseApp.app()?.options.projectID else {
            errorMessage = "Firebase is not configured or no account is signed in."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try WorkspaceService.bindBackup(projectID: projectID, uid: account.userIdentifier, in: modelContext)
            backupConnected = true
            statusMessage = "This local workspace is connected to the signed-in backup account."
            errorMessage = nil
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    private func signIn() async {
        await performAccountAction {
            try await accountService.signIn(email: accountEmail, password: accountPassword)
            return "Signed in. Review the backup connection before saving local data."
        }
    }

    private func createAccount() async {
        await performAccountAction {
            try await accountService.createAccount(email: accountEmail, password: accountPassword)
            return "Account created. Review the backup connection before saving local data."
        }
    }

    private func recoverPassword() async {
        do {
            try await accountService.sendPasswordReset(email: accountEmail)
            statusMessage = "Password reset instructions sent if that account exists."
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func performAccountAction(_ action: () async throws -> String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            statusMessage = try await action()
            errorMessage = nil
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await accountService.deleteAccountAndRemoteBackup(password: accountPassword)
            latestMetadata = nil
            try WorkspaceService.disconnectBackup(in: modelContext)
            backupConnected = false
            statusMessage = "Account and encrypted cloud backup deleted. Local data remains on this device."
            errorMessage = nil
            await refresh()
        } catch { errorMessage = error.localizedDescription }
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
            try WorkspaceService.disconnectBackup(in: modelContext)
            backupConnected = false
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

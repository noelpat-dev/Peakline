import SwiftData
import SwiftUI
import UIKit

struct AccountGateView: View {
    @Environment(\.appTheme) private var appTheme

    let readiness: AccountReadiness
    @Binding var email: String
    @Binding var password: String
    @Binding var backupPassphrase: String
    let errorMessage: String?
    let isWorking: Bool
    let retry: () -> Void
    let continueWithoutBackup: () -> Void
    let signIn: () -> Void
    let createAccount: () -> Void

    var body: some View {
        ZStack {
            appTheme.colors.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(appTheme.colors.accent)
                        .frame(width: 74, height: 74)
                        .background(appTheme.colors.accentSurface, in: Circle())

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Protect your Peakline data")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(appTheme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Create or sign in to a free Firebase-backed account. Your full backup is encrypted before it leaves this iPhone.")
                            .font(.body)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    FitnessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(readiness.title, systemImage: readinessIcon)
                                .font(.headline)
                                .foregroundStyle(appTheme.colors.textPrimary)
                            Text(readiness.message)
                                .font(.subheadline)
                                .foregroundStyle(appTheme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if isFirebaseMissing {
                        FitnessCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Local-only mode", systemImage: "iphone")
                                    .font(.headline)
                                    .foregroundStyle(appTheme.colors.textPrimary)
                                Text("You can keep using Peakline on this iPhone now. Add Firebase setup later to save encrypted backups before deleting or reinstalling the app.")
                                    .font(.subheadline)
                                    .foregroundStyle(appTheme.colors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(12)
                                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))

                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .padding(12)
                                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))

                            SecureField("Backup passphrase", text: $backupPassphrase)
                                .textContentType(.newPassword)
                                .padding(12)
                                .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))
                        }
                        .disabled(isWorking)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(appTheme.dangerColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isFirebaseMissing {
                        Button(action: continueWithoutBackup) {
                            Label("Continue Local Only", systemImage: "iphone")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryFitnessButtonStyle())
                        .disabled(isWorking)
                    } else {
                        HStack(spacing: 10) {
                            Button(action: signIn) {
                                Label(isWorking ? "Signing In" : "Sign In", systemImage: "person.crop.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryFitnessButtonStyle())
                            .disabled(isWorking)

                            Button(action: createAccount) {
                                Label("Create", systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SecondaryFitnessButtonStyle())
                            .disabled(isWorking)
                        }
                    }

                    Button(action: retry) {
                        Label(isWorking ? "Checking" : "Retry", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryFitnessButtonStyle())
                    .disabled(isWorking)
                }
                .padding(24)
            }
        }
        .accessibilityIdentifier("startup-account-gate")
        .peaklineKeyboardDismissal()
    }

    private var isFirebaseMissing: Bool {
        if case .firebaseNotConfigured = readiness { return true }
        return false
    }

    private var readinessIcon: String {
        switch readiness {
        case .ready:
            return "checkmark.shield.fill"
        case .firebaseNotConfigured:
            return "externaldrive.badge.exclamationmark"
        default:
            return "person.crop.circle.badge.exclamationmark"
        }
    }
}

struct CloudBackupRestorePromptView: View {
    @Environment(\.appTheme) private var appTheme

    let metadata: FullAppBackupMetadata
    @Binding var passphrase: String
    let errorMessage: String?
    let isWorking: Bool
    let restore: () -> Void
    let skip: () -> Void

    var body: some View {
        ZStack {
            appTheme.colors.backgroundPrimary.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(appTheme.colors.accent)
                    .frame(width: 74, height: 74)
                    .background(appTheme.colors.accentSurface, in: Circle())

                VStack(alignment: .leading, spacing: 8) {
                    Text("Restore your Peakline backup?")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("An encrypted Firebase backup was found before local starter data loaded.")
                        .font(.body)
                        .foregroundStyle(appTheme.colors.textSecondary)
                }

                FitnessCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Last saved \(metadata.createdAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundStyle(appTheme.colors.textPrimary)
                        Text("\(metadata.counts.workoutCount) workouts, \(metadata.counts.foodLogCount) food logs, \(metadata.counts.sleepCount) sleep sessions, and \(metadata.counts.hydrationCount) hydration entries.")
                            .font(.subheadline)
                            .foregroundStyle(appTheme.colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SecureField("Backup passphrase", text: $passphrase)
                    .textContentType(.password)
                    .padding(12)
                    .background(appTheme.colors.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: appTheme.metrics.radius8, style: .continuous))
                    .disabled(isWorking)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(appTheme.dangerColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: restore) {
                    Label(isWorking ? "Restoring" : "Restore Backup", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFitnessButtonStyle())
                .disabled(isWorking)

                Button(action: skip) {
                    Text("Start Fresh")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryFitnessButtonStyle())
                .disabled(isWorking)
            }
            .padding(24)
        }
        .accessibilityIdentifier("startup-restore-prompt")
        .peaklineKeyboardDismissal()
    }
}

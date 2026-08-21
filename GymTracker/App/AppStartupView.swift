import SwiftData
import SwiftUI
import UIKit

struct AppStartupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTheme) private var appTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var coordinator = AppStartupCoordinator()
    @StateObject private var presentation = StartupPresentationCoordinator()
    @State private var splashOpacity = 1.0
    @State private var splashScale = 1.0
    @State private var email = ""
    @State private var password = ""
    @State private var backupPassphrase = ""
    @State private var signInError: String?
    @State private var isWorking = false
    #if DEBUG
    @State private var performanceAcceptanceSummary = PerformanceAcceptanceState.summary
    private let performanceAcceptanceTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    #endif

    private let accountService = FirebaseAccountService()

    var body: some View {
        ZStack {
            phaseContent

            if presentation.isOverlayMounted {
                PeaklineSplashView(
                    stageText: coordinator.stageText,
                    showsProgress: presentation.showsSlowProgress,
                    animatesWordmark: presentation.animatesWordmark && !reduceMotion
                )
                .opacity(splashOpacity)
                .scaleEffect(splashScale)
                .zIndex(10)
                .contentShape(Rectangle())
                .allowsHitTesting(true)
            }
        }
        .task {
            presentation.start()
            await coordinator.start(in: modelContext)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch coordinator.phase {
        case .branding, .checkingAccount, .checkingBackup, .preparingLocalData, .warmingScreens:
            appTheme.colors.backgroundPrimary
                .ignoresSafeArea()
                .accessibilityHidden(true)
        case .accountRequired(let readiness):
            AccountGateView(
                readiness: readiness,
                email: $email,
                password: $password,
                backupPassphrase: $backupPassphrase,
                errorMessage: signInError,
                isWorking: isWorking,
                retry: {
                    resumeAfterInteraction()
                    Task {
                        await coordinator.retry(in: modelContext)
                        interruptPresentationIfNeeded()
                    }
                },
                continueWithoutBackup: {
                    resumeAfterInteraction()
                    Task {
                        await coordinator.continueWithoutBackup(in: modelContext)
                        interruptPresentationIfNeeded()
                    }
                },
                signIn: { Task { await authenticate(createAccount: false) } },
                createAccount: { Task { await authenticate(createAccount: true) } }
            )
            .onAppear {
                presentation.interrupt(reason: "account")
            }
        case .restorePrompt(let metadata):
            CloudBackupRestorePromptView(
                metadata: metadata,
                passphrase: $backupPassphrase,
                errorMessage: coordinator.restoreError,
                isWorking: isWorking,
                restore: { Task { await restoreBackup() } },
                skip: {
                    resumeAfterInteraction()
                    Task {
                        await coordinator.skipRestore(in: modelContext)
                        interruptPresentationIfNeeded()
                    }
                }
            )
            .onAppear {
                presentation.interrupt(reason: "restore")
            }
        case .ready(let snapshot):
            readyContent(snapshot)
        case .recoverableFailure(let message, let canContinueOffline):
            startupStatusView(
                title: "Peakline could not finish loading",
                message: message,
                actionTitle: "Try Again",
                action: {
                    resumeAfterInteraction()
                    Task {
                        await coordinator.retry(in: modelContext)
                        interruptPresentationIfNeeded()
                    }
                },
                secondaryActionTitle: canContinueOffline ? "Continue Offline" : nil,
                secondaryAction: canContinueOffline
                    ? {
                        resumeAfterInteraction()
                        Task {
                            await coordinator.continueOfflineAfterFailure(in: modelContext)
                            interruptPresentationIfNeeded()
                        }
                    }
                    : nil
            )
            .onAppear {
                presentation.interrupt(reason: "error")
            }
        }
    }

    private func readyContent(_ snapshot: StartupSnapshotBundle) -> some View {
        RootTabView(
            startupSnapshot: snapshot,
            startupRevealComplete: presentation.isRevealComplete
        )
        .accessibilityIdentifier("startup-critical-ready")
        #if DEBUG
        .accessibilityValue(performanceAcceptanceSummary)
        .onReceive(performanceAcceptanceTimer) { _ in
            guard PerformanceAcceptanceState.isEnabled else { return }
            performanceAcceptanceSummary = PerformanceAcceptanceState.summary
        }
        #endif
        .allowsHitTesting(presentation.isRevealComplete)
        .accessibilityHidden(!presentation.isRevealComplete)
        .task(id: snapshot.preparedAt) {
            guard presentation.beginReveal() else { return }
            await Task.yield()

            let duration = StartupPresentationTiming.current.revealDuration
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: duration)
                    : .easeInOut(duration: duration)
            ) {
                splashOpacity = 0
                splashScale = reduceMotion ? 1 : 1.015
            }

            try? await Task.sleep(for: .seconds(duration))
            presentation.finishReveal()
        }
    }

    private func resumeAfterInteraction() {
        splashOpacity = 1
        splashScale = 1
        presentation.resumeAfterInteraction()
    }

    private func interruptPresentationIfNeeded() {
        switch coordinator.phase {
        case .accountRequired:
            presentation.interrupt(reason: "account")
        case .restorePrompt:
            presentation.interrupt(reason: "restore")
        case .recoverableFailure:
            presentation.interrupt(reason: "error")
        case .branding, .checkingAccount, .checkingBackup, .preparingLocalData, .warmingScreens, .ready:
            break
        }
    }

    @ViewBuilder
    private func startupStatusView(
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            appTheme.colors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .tint(appTheme.colors.accent)
                    .opacity(action == nil ? 1 : 0)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(appTheme.colors.textPrimary)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(appTheme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(PrimaryFitnessButtonStyle())
                }

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(SecondaryFitnessButtonStyle())
                }
            }
            .padding()
        }
        .accessibilityIdentifier("startup-error")
    }

    private func authenticate(createAccount: Bool) async {
        isWorking = true
        defer { isWorking = false }
        signInError = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            signInError = "Enter your email and password."
            return
        }
        guard backupPassphrase.count >= 8 else {
            signInError = "Use a backup passphrase with at least 8 characters."
            return
        }

        do {
            if createAccount {
                _ = try await accountService.createAccount(email: trimmedEmail, password: password)
            } else {
                _ = try await accountService.signIn(email: trimmedEmail, password: password)
            }
            resumeAfterInteraction()
            await coordinator.retry(in: modelContext)
            interruptPresentationIfNeeded()
        } catch {
            signInError = error.localizedDescription
        }
    }

    private func restoreBackup() async {
        isWorking = true
        defer { isWorking = false }

        guard backupPassphrase.count >= 8 else {
            coordinator.restoreError = "Enter the backup passphrase you used when saving this backup."
            return
        }

        resumeAfterInteraction()
        await coordinator.restoreBackup(in: modelContext, passphrase: backupPassphrase)
        if coordinator.restoreError != nil {
            presentation.interrupt(reason: "restore_failed")
        }
    }
}

import FirebaseAuth
import FirebaseCore
import Foundation

struct FirebaseAccountRecord: Codable, Equatable {
    let userIdentifier: String
    let email: String?
    let signedInAt: Date
}

enum AccountReadiness: Equatable {
    case ready(FirebaseAccountRecord)
    case needsSignIn
    case firebaseNotConfigured
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .ready:
            return "Account ready"
        case .needsSignIn:
            return "Account required"
        case .firebaseNotConfigured:
            return "Firebase setup needed"
        case .failed:
            return "Account check failed"
        }
    }

    var message: String {
        switch self {
        case .ready(let record):
            if let email = record.email, !email.isEmpty {
                return "Signed in as \(email). Your encrypted backup can be saved to Firebase."
            }
            return "Signed in. Your encrypted backup can be saved to Firebase."
        case .needsSignIn:
            return "Create or sign in to a free Peakline backup account before using the app."
        case .firebaseNotConfigured:
            return "Add your Firebase project's GoogleService-Info.plist to enable free account backup."
        case .failed(let message):
            return message
        }
    }
}

enum FirebaseBootstrap {
    static func configureIfPossible() {
        guard hasConfigurationFile else { return }
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    static var isConfigured: Bool {
        hasConfigurationFile && FirebaseApp.app() != nil
    }

    private static var hasConfigurationFile: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }
}

struct FirebaseAccountService {
    func currentRecord() -> FirebaseAccountRecord? {
        guard FirebaseBootstrap.isConfigured,
              let user = Auth.auth().currentUser else {
            return nil
        }
        return FirebaseAccountRecord(
            userIdentifier: user.uid,
            email: user.email,
            signedInAt: Date()
        )
    }

    func readiness() async -> AccountReadiness {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore")
            || ProcessInfo.processInfo.arguments.contains("-SkipAccountGate") {
            return .ready(FirebaseAccountRecord(userIdentifier: "ui-test-user", email: "ui-test@peakline.local", signedInAt: .distantPast))
        }
#endif

        guard FirebaseBootstrap.isConfigured else {
            return .firebaseNotConfigured
        }

        guard let user = Auth.auth().currentUser else {
            return .needsSignIn
        }

        return .ready(FirebaseAccountRecord(
            userIdentifier: user.uid,
            email: user.email,
            signedInAt: Date()
        ))
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> FirebaseAccountRecord {
        guard FirebaseBootstrap.isConfigured else {
            throw FirebaseAccountError.notConfigured
        }
        let result = try await signInResult(email: email, password: password)
        return FirebaseAccountRecord(
            userIdentifier: result.user.uid,
            email: result.user.email,
            signedInAt: Date()
        )
    }

    @discardableResult
    func createAccount(email: String, password: String) async throws -> FirebaseAccountRecord {
        guard FirebaseBootstrap.isConfigured else {
            throw FirebaseAccountError.notConfigured
        }
        let result = try await createUserResult(email: email, password: password)
        return FirebaseAccountRecord(
            userIdentifier: result.user.uid,
            email: result.user.email,
            signedInAt: Date()
        )
    }

    func signOut() throws {
        guard FirebaseBootstrap.isConfigured else { return }
        try Auth.auth().signOut()
    }

    /// Sends a password reset without exposing the address or Firebase error
    /// details to logs. A reset does not unlock an independently protected
    /// backup passphrase.
    func sendPasswordReset(email: String) async throws {
        guard FirebaseBootstrap.isConfigured else { throw FirebaseAccountError.notConfigured }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw FirebaseAccountError.invalidEmail }
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().sendPasswordReset(withEmail: address) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    /// Deletes the remote backup descendants before deleting authentication.
    /// This is deliberately idempotent: missing documents are successful and
    /// authentication is removed only after the remote cleanup has completed.
    func deleteAccountAndRemoteBackup(password: String) async throws {
        guard FirebaseBootstrap.isConfigured else { throw FirebaseAccountError.notConfigured }
        guard let user = Auth.auth().currentUser else { throw FirebaseAccountError.notSignedIn }
        guard !password.isEmpty else { throw FirebaseAccountError.passwordRequired }

        let credential = EmailAuthProvider.credential(withEmail: user.email ?? "", password: password)
        _ = try await reauthenticate(user: user, credential: credential)
        try await requestRemoteBackupDeletion(for: user)
        try await deleteUser(user)
    }

    private func reauthenticate(user: User, credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            user.reauthenticate(with: credential) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: FirebaseAccountError.missingAuthResult) }
            }
        }
    }

    private func deleteUser(_ user: User) async throws {
        try await withCheckedThrowingContinuation { continuation in
            user.delete { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func requestRemoteBackupDeletion(for user: User) async throws {
        guard let projectID = FirebaseApp.app()?.options.projectID,
              let endpoint = URL(string: "https://us-central1-\(projectID).cloudfunctions.net/deleteBackup") else {
            throw FirebaseAccountError.remoteCleanupFailed
        }
        let token = try await user.getIDToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": ["confirm": true]])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FirebaseAccountError.remoteCleanupFailed
        }
    }

    private func signInResult(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: FirebaseAccountError.missingAuthResult)
                }
            }
        }
    }

    private func createUserResult(email: String, password: String) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: FirebaseAccountError.missingAuthResult)
                }
            }
        }
    }
}

enum FirebaseAccountError: LocalizedError, Equatable {
    case notConfigured
    case missingAuthResult
    case invalidEmail
    case notSignedIn
    case passwordRequired
    case remoteCleanupFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase is not configured. Add GoogleService-Info.plist from your Firebase project."
        case .missingAuthResult:
            return "Firebase did not return an account result."
        case .invalidEmail:
            return "Enter the email address for your Peakline account."
        case .notSignedIn:
            return "Sign in to manage your Peakline backup account."
        case .passwordRequired:
            return "Enter your account password to confirm deletion."
        case .remoteCleanupFailed:
            return "Peakline could not verify remote backup cleanup. Your account was kept."
        }
    }
}

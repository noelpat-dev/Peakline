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

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase is not configured. Add GoogleService-Info.plist from your Firebase project."
        case .missingAuthResult:
            return "Firebase did not return an account result."
        }
    }
}

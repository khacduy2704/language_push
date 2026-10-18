import FirebaseCore
import FirebaseAuth
import Foundation

enum FirebaseRegistration {
    static func validate(_ values: [String: Any], bundleID: String) throws {
        guard values["BUNDLE_ID"] as? String == bundleID else {
            throw RegistrationError.bundleMismatch
        }
        for key in ["GOOGLE_APP_ID", "API_KEY", "PROJECT_ID", "GCM_SENDER_ID"] {
            guard let value = values[key] as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RegistrationError.invalidConfiguration
            }
        }
    }

    enum RegistrationError: LocalizedError {
        case bundleMismatch
        case invalidConfiguration
        var errorDescription: String? {
            switch self {
            case .bundleMismatch:
                return AppLocalization.text("The Firebase configuration belongs to another bundle identifier. Register this native app separately.")
            case .invalidConfiguration:
                return AppLocalization.text("The Firebase configuration is missing required values. Download it again from Firebase.")
            }
        }
    }
}

@MainActor
final class FirebaseAuthenticationClient: AuthenticationClient {
    var accountChanged: ((Account?) -> Void)?
    private let auth: Auth
    private var listener: AuthStateDidChangeListenerHandle?

    var currentAccount: Account? { Self.account(auth.currentUser) }

    init() {
        auth = Auth.auth()
        listener = auth.addStateDidChangeListener { [weak self] _, user in
            let account = Self.account(user)
            Task { @MainActor [weak self] in self?.accountChanged?(account) }
        }
    }

    deinit {
        if let listener { auth.removeStateDidChangeListener(listener) }
    }

    static func prepare() -> AuthController {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PUSH_LANGUAGE_TEST_DATABASE_ID"] != nil {
            return AuthController(client: nil, setupMessage: "Firebase setup is required for this native app.")
        }
        #endif
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else {
            return AuthController(client: nil, setupMessage: "Add a GoogleService-Info.plist registered for this native app's bundle identifier.")
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let bundleID = Bundle.main.bundleIdentifier else {
                throw FirebaseRegistration.RegistrationError.invalidConfiguration
            }
            try FirebaseRegistration.validate(values, bundleID: bundleID)
            guard let options = FirebaseOptions(contentsOfFile: path) else {
                throw FirebaseRegistration.RegistrationError.invalidConfiguration
            }
            if FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
            return AuthController(client: FirebaseAuthenticationClient())
        } catch {
            return AuthController(client: nil, setupMessage: error.localizedDescription)
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            _ = try await auth.signIn(withEmail: email, password: password)
        } catch { throw Self.mapped(error) }
    }

    func signUp(email: String, password: String) async throws {
        do {
            _ = try await auth.createUser(withEmail: email, password: password)
        } catch { throw Self.mapped(error) }
    }

    func signOut() throws {
        do { try auth.signOut() } catch { throw Self.mapped(error) }
    }

    private static func account(_ user: User?) -> Account? {
        user.map { Account(uid: $0.uid, email: $0.email, displayName: $0.displayName) }
    }

    private static func mapped(_ error: Error) -> Error {
        let nsError = error as NSError
        let key: String
        switch AuthErrorCode(rawValue: nsError.code) {
        case .invalidEmail: key = "Please enter a valid email address."
        case .wrongPassword, .userNotFound, .invalidCredential: key = "Incorrect email or password."
        case .emailAlreadyInUse: key = "This email is already registered."
        case .weakPassword: key = "Password must be at least 6 characters."
        case .networkError: key = "Could not connect to authentication. Check your connection and retry."
        case .tooManyRequests: key = "Too many authentication attempts. Please try again later."
        case .operationNotAllowed: key = "Enable Email/Password sign-in in Firebase Authentication."
        case .userDisabled: key = "This account is disabled."
        default:
            return NSError(domain: "NativeAuthentication", code: nsError.code, userInfo: [
                NSLocalizedDescriptionKey: AppLocalization.format("Authentication failed. %@", nsError.localizedDescription)
            ])
        }
        return NSError(domain: "NativeAuthentication", code: nsError.code, userInfo: [
            NSLocalizedDescriptionKey: AppLocalization.text(key)
        ])
    }
}

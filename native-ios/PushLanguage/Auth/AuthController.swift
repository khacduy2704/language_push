import Combine
import Foundation

struct Account: Equatable {
    let uid: String
    let email: String?
    let displayName: String?
}

@MainActor
protocol AuthenticationClient: AnyObject {
    var accountChanged: ((Account?) -> Void)? { get set }
    var currentAccount: Account? { get }
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String) async throws
    func signOut() throws
}

enum AuthenticationError: LocalizedError {
    case invalidEmail
    case weakPassword
    case passwordMismatch
    case setupRequired

    var errorDescription: String? {
        switch self {
        case .invalidEmail: return AppLocalization.text("Please enter a valid email address.")
        case .weakPassword: return AppLocalization.text("Password must be at least 6 characters.")
        case .passwordMismatch: return AppLocalization.text("Passwords do not match.")
        case .setupRequired: return AppLocalization.text("Firebase setup is required for this native app.")
        }
    }
}

@MainActor
final class AuthController: ObservableObject {
    @Published private(set) var account: Account?
    @Published private(set) var busy = false
    @Published private(set) var errorMessage: String?
    let setupMessage: String?
    private let client: AuthenticationClient?

    init(client: AuthenticationClient?, setupMessage: String? = nil) {
        self.client = client
        self.setupMessage = setupMessage
        account = client?.currentAccount
        client?.accountChanged = { [weak self] in self?.account = $0 }
    }

    var configured: Bool { client != nil }

    func submit(email: String, password: String, confirmation: String, creating: Bool) async {
        guard !busy else { return }
        errorMessage = nil
        busy = true
        defer { busy = false }
        do {
            guard let client else { throw AuthenticationError.setupRequired }
            let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.validEmail(email) else { throw AuthenticationError.invalidEmail }
            guard password.count >= 6 else { throw AuthenticationError.weakPassword }
            if creating {
                guard password == confirmation else { throw AuthenticationError.passwordMismatch }
                try await client.signUp(email: email, password: password)
            } else {
                try await client.signIn(email: email, password: password)
            }
            account = client.currentAccount
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        guard !busy else { return }
        errorMessage = nil
        do {
            guard let client else { throw AuthenticationError.setupRequired }
            try client.signOut()
            account = client.currentAccount
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func validEmail(_ value: String) -> Bool {
        value.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}

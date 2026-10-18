import XCTest
@testable import PushLanguage

@MainActor
final class AuthenticationTests: XCTestCase {
    private final class Client: AuthenticationClient {
        var accountChanged: ((Account?) -> Void)?
        var currentAccount: Account?
        var calls: [(String, String, Bool)] = []
        var error: Error?
        var held = false
        var continuation: CheckedContinuation<Void, Never>?

        func signIn(email: String, password: String) async throws {
            calls.append((email, password, false))
            if held { await withCheckedContinuation { continuation = $0 } }
            if let error { throw error }
            currentAccount = Account(uid: "test-id", email: email, displayName: nil)
            accountChanged?(currentAccount)
        }
        func signUp(email: String, password: String) async throws {
            calls.append((email, password, true))
            if let error { throw error }
            currentAccount = Account(uid: "created-id", email: email, displayName: nil)
            accountChanged?(currentAccount)
        }
        func signOut() throws {
            if let error { throw error }
            currentAccount = nil
            accountChanged?(nil)
        }
    }

    override func setUp() async throws {
        AppLocalization.language = .english
    }

    func testSignInTrimsEmailButPreservesPasswordAndObservesAccount() async {
        let client = Client()
        let controller = AuthController(client: client)
        await controller.submit(email: " person@example.com\n", password: " secret ", confirmation: "", creating: false)
        XCTAssertEqual(client.calls.count, 1)
        XCTAssertEqual(client.calls.first?.0, "person@example.com")
        XCTAssertEqual(client.calls.first?.1, " secret ")
        XCTAssertEqual(controller.account?.uid, "test-id")
        XCTAssertFalse(controller.busy)
        XCTAssertNil(controller.errorMessage)
        controller.signOut()
        XCTAssertNil(controller.account)
        client.accountChanged?(Account(uid: "external", email: nil, displayName: "name"))
        XCTAssertEqual(controller.account?.uid, "external")
    }

    func testCreateAndValidationDoNotCallBackendWithInvalidInput() async {
        let client = Client()
        let controller = AuthController(client: client)
        for (email, password, confirmation) in [
            ("invalid", "123456", "123456"),
            ("a@b.com", "123", "123"),
            ("a@b.com", "123456", "different")
        ] {
            await controller.submit(email: email, password: password, confirmation: confirmation, creating: true)
            XCTAssertNotNil(controller.errorMessage)
            XCTAssertTrue(client.calls.isEmpty)
            XCTAssertFalse(controller.busy)
        }
        await controller.submit(email: "a@b.com", password: "123456", confirmation: "123456", creating: true)
        XCTAssertEqual(client.calls.first?.2, true)
        XCTAssertEqual(controller.account?.uid, "created-id")
    }

    func testMissingSetupFailsExplicitlyWithoutCreatingAccount() async {
        let controller = AuthController(client: nil, setupMessage: "setup")
        XCTAssertFalse(controller.configured)
        await controller.submit(email: "a@b.com", password: "123456", confirmation: "", creating: false)
        XCTAssertEqual(controller.errorMessage, "Firebase setup is required for this native app.")
        XCTAssertNil(controller.account)
        controller.signOut()
        XCTAssertNotNil(controller.errorMessage)
    }

    func testBackendErrorsRetryAndSignOutFailurePreservesAccount() async {
        let client = Client()
        client.error = NSError(domain: "TestAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offline"])
        let controller = AuthController(client: client)
        await controller.submit(email: "a@b.com", password: "123456", confirmation: "", creating: false)
        XCTAssertEqual(controller.errorMessage, "Offline")
        XCTAssertNil(controller.account)
        client.error = nil
        await controller.submit(email: "a@b.com", password: "123456", confirmation: "", creating: false)
        let account = controller.account
        XCTAssertNotNil(account)
        client.error = NSError(domain: "TestAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot sign out"])
        controller.signOut()
        XCTAssertEqual(controller.account, account)
        XCTAssertEqual(controller.errorMessage, "Cannot sign out")
    }

    func testBusySubmissionCannotStartDuplicateOperation() async {
        let client = Client()
        client.held = true
        let controller = AuthController(client: client)
        let first = Task {
            await controller.submit(email: "a@b.com", password: "123456", confirmation: "", creating: false)
        }
        while client.continuation == nil { await Task.yield() }
        XCTAssertTrue(controller.busy)
        await controller.submit(email: "a@b.com", password: "123456", confirmation: "", creating: false)
        controller.signOut()
        XCTAssertEqual(client.calls.count, 1)
        client.continuation?.resume()
        await first.value
        XCTAssertFalse(controller.busy)
    }

    func testFirebaseRegistrationRejectsFlutterBundleAndMissingFields() throws {
        let bundleID = "com.example.pushLanguage"
        var values: [String: Any] = [
            "BUNDLE_ID": bundleID, "GOOGLE_APP_ID": "registered-app",
            "API_KEY": "test-key", "PROJECT_ID": "test-project", "GCM_SENDER_ID": "123"
        ]
        XCTAssertNoThrow(try FirebaseRegistration.validate(values, bundleID: bundleID))
        values["BUNDLE_ID"] = "com.example.pushLanguage27"
        XCTAssertThrowsError(try FirebaseRegistration.validate(values, bundleID: bundleID))
        values["BUNDLE_ID"] = bundleID
        for key in ["API_KEY", "PROJECT_ID", "GOOGLE_APP_ID", "GCM_SENDER_ID"] {
            var missing = values
            missing[key] = " "
            XCTAssertThrowsError(try FirebaseRegistration.validate(missing, bundleID: bundleID))
        }
    }

    func testEnglishAndVietnameseValidationAndSetupMessages() async {
        defer { AppLocalization.language = .english }
        AppLocalization.language = .vietnamese
        XCTAssertEqual(AuthenticationError.invalidEmail.localizedDescription, "Vui lòng nhập địa chỉ email hợp lệ.")
        XCTAssertEqual(AuthenticationError.passwordMismatch.localizedDescription, "Mật khẩu không khớp.")
        let controller = AuthController(client: nil)
        await controller.submit(email: "", password: "", confirmation: "", creating: false)
        XCTAssertEqual(controller.errorMessage, "Cần cấu hình Firebase cho ứng dụng gốc này.")
    }
}

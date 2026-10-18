import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject private var auth: AuthController
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        Form {
            Picker("Account action", selection: $creating) {
                Text("Sign In").tag(false)
                Text("Sign Up").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("authMode")
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .accessibilityIdentifier("authEmail")
            SecureField("Password", text: $password)
                .textContentType(creating ? .newPassword : .password)
                .accessibilityIdentifier("authPassword")
            if creating {
                SecureField("Confirm password", text: $confirmation)
                    .textContentType(.newPassword)
                    .accessibilityIdentifier("authConfirmation")
            }
            if let error = auth.errorMessage {
                Text(error).foregroundColor(.red).accessibilityIdentifier("authError")
            }
            if auth.busy { ProgressView("Signing in...") }
            Button(LocalizedStringKey(creating ? "Create Account" : "Sign In")) {
                Task {
                    await auth.submit(email: email, password: password, confirmation: confirmation, creating: creating)
                    if auth.account != nil { dismiss() }
                }
            }
            .accessibilityIdentifier("authSubmit")
            Text("Google and Apple sign-in will be added in a later step.")
                .font(.footnote).foregroundColor(.secondary)
        }
        .disabled(auth.busy)
        .navigationTitle(LocalizedStringKey(creating ? "Create Account" : "Sign In"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            password = ""
            confirmation = ""
        }
    }
}

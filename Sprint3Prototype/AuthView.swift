//
//  AuthView.swift
//  Sprint3Prototype
//
//  Created by Ayane on 10/18/25.
//

import SwiftUI
import FirebaseAuth

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Int = 0 // 0 = Sign In, 1 = Sign Up

    // Sign in fields
    @State private var signInEmail: String = ""
    @State private var signInPassword: String = ""
    @State private var signInError: String? = nil
    @State private var isSigningIn: Bool = false

    // Sign up fields
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var signUpEmail: String = ""
    @State private var signUpPassword: String = ""
    @State private var signUpConfirm: String = ""
    @State private var signUpError: String? = nil
    @State private var isSigningUp: Bool = false
    @State private var verificationSent: Bool = false

    // MARK: - Live validation computed properties
    private var emailTrimmed: String { signUpEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var emailIsValid: Bool { emailTrimmed.hasSuffix("@gatech.edu") }

    private var passwordLengthOK: Bool { signUpPassword.count >= 6 }
    private var passwordHasUpper: Bool { signUpPassword.rangeOfCharacter(from: .uppercaseLetters) != nil }
    private var passwordHasLower: Bool { signUpPassword.rangeOfCharacter(from: .lowercaseLetters) != nil }
    private var passwordHasDigit: Bool { signUpPassword.rangeOfCharacter(from: .decimalDigits) != nil }
    private var passwordHasSpecial: Bool {
        let specials = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\\\",.<>/?`~")
        return signUpPassword.rangeOfCharacter(from: specials) != nil
    }
    private var passwordValidAll: Bool { passwordLengthOK && passwordHasUpper && passwordHasLower && passwordHasDigit && passwordHasSpecial }
    private var passwordsMatch: Bool { !signUpConfirm.isEmpty && signUpPassword == signUpConfirm }

    private func requiredLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Text("*").foregroundColor(.red)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Auth", selection: $selection) {
                    Text("Sign In").tag(0)
                    Text("Sign Up").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                if selection == 0 {
                    signInForm
                } else {
                    signUpForm
                }

                Spacer()
            }
            .padding()
            .navigationTitle(selection == 0 ? "Sign In" : "Sign Up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var signInForm: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("GT email", text: $signInEmail)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $signInPassword)
                    .textFieldStyle(.roundedBorder)
            }
            if let err = signInError { Text(err).foregroundColor(.red).font(.caption) }
            Button(action: handleSignIn) {
                HStack {
                    if isSigningIn { ProgressView() }
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn || signInEmail.isEmpty || signInPassword.isEmpty)

            Button("Forgot password?") {
                let email = signInEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !email.isEmpty else { signInError = "Enter your GT email to reset password"; return }
                Auth.auth().sendPasswordReset(withEmail: email) { error in
                    if let error = error { signInError = error.localizedDescription } else { signInError = "Password reset sent (if account exists)." }
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private var signUpForm: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    requiredLabel("First name")
                    TextField("George", text: $firstName).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    requiredLabel("Last name")
                    TextField("Burdell", text: $lastName).textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                requiredLabel("GT email")
                TextField("name@gatech.edu", text: $signUpEmail)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(.roundedBorder)
                if !signUpEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: emailIsValid ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(emailIsValid ? .green : .red)
                        Text(emailIsValid ? "Looks good!" : "Please use a @gatech.edu email")
                            .font(.caption)
                            .foregroundColor(emailIsValid ? .secondary : .red)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                requiredLabel("Password")
                SecureField("Password", text: $signUpPassword).textFieldStyle(.roundedBorder)
                if !signUpPassword.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { validationIcon(passwordLengthOK); Text("At least 6 characters").font(.caption) }
                        HStack { validationIcon(passwordHasUpper); Text("1 uppercase letter").font(.caption) }
                        HStack { validationIcon(passwordHasLower); Text("1 lowercase letter").font(.caption) }
                        HStack { validationIcon(passwordHasDigit); Text("1 number").font(.caption) }
                        HStack { validationIcon(passwordHasSpecial); Text("1 special character (!@#$...) ").font(.caption) }
                    }
                    .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                requiredLabel("Confirm password")
                SecureField("Confirm password", text: $signUpConfirm).textFieldStyle(.roundedBorder)
                if !signUpConfirm.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(passwordsMatch ? .green : .red)
                        Text(passwordsMatch ? "Passwords match" : "Passwords do not match")
                            .font(.caption).foregroundColor(passwordsMatch ? .secondary : .red)
                    }
                }
            }

            if let err = signUpError { Text(err).foregroundColor(.red).font(.caption) }
            if verificationSent {
                VStack(spacing: 8) {
                    Text("Verification email sent. Please check your GT email and click the link to verify your account.")
                        .font(.caption)
                    HStack(spacing: 12) {
                        Button("Resend verification") { resendVerification() }
                        Button("I verified") { checkVerified() }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button(action: handleSignUp) {
                    HStack {
                        if isSigningUp { ProgressView() }
                        Text("Create account")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSigningUp || firstName.isEmpty || lastName.isEmpty || !emailIsValid || !passwordValidAll || !passwordsMatch)
            }
        }
    }

    private func handleSignIn() {
        signInError = nil
        isSigningIn = true
        appState.signIn(email: signInEmail, password: signInPassword) { error in
            DispatchQueue.main.async {
                isSigningIn = false
                if let error = error {
                    signInError = error.localizedDescription
                } else {
                    dismiss()
                }
            }
        }
    }

    private func handleSignUp() {
        signUpError = nil
        if !signUpEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix("@gatech.edu") {
            signUpError = "Please use a @gatech.edu email"
            return
        }
        if signUpPassword != signUpConfirm {
            signUpError = "Passwords do not match"
            return
        }
        isSigningUp = true
        appState.signUp(firstName: firstName, lastName: lastName, email: signUpEmail, password: signUpPassword) { error in
            DispatchQueue.main.async {
                isSigningUp = false
                if let error = error {
                    signUpError = error.localizedDescription
                } else {
                    verificationSent = true
                }
            }
        }
    }

    private func resendVerification() {
        appState.resendVerification { error in
            DispatchQueue.main.async {
                if let error = error { signUpError = error.localizedDescription } else { signUpError = "Verification sent." }
            }
        }
    }

    private func checkVerified() {
        appState.refreshVerificationStatus { verified, error in
            DispatchQueue.main.async {
                if let error = error { signUpError = error.localizedDescription; return }
                if verified {
                    dismiss()
                } else {
                    signUpError = "Account not verified yet. Please click the verification link in your email."
                }
            }
        }
    }

    @ViewBuilder
    private func validationIcon(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundColor(ok ? .green : .red)
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View {
        AuthView().environmentObject(AppState())
    }
}

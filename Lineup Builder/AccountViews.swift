//
//  AccountViews.swift
//  Lineup Builder
//
//  Settings › Account and the sign-in sheet (Merge 0). Signing in is optional:
//  signed out, the app works exactly as before.
//

import AuthenticationServices
import SwiftUI

// MARK: - Settings section

struct AccountSection: View {
    @EnvironmentObject private var account: AccountManager
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteError: String?

    var body: some View {
        Section {
            if account.isSignedIn {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AccountLabel.title(email: account.email, name: account.name))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(AccountLabel.subtitle(methods: account.methods, email: account.email))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Button("Sign Out") { confirmingSignOut = true }
                    .confirmationDialog("Sign out on this device?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { Task { await account.signOut() } }
                    } message: {
                        Text("You can sign back in anytime.")
                    }

                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    HStack {
                        Text("Delete Account")
                        if deleting { Spacer(); ProgressView() }
                    }
                }
                .disabled(deleting)
                .alert("Delete your account?", isPresented: $confirmingDelete) {
                    Button("Delete Account", role: .destructive) { delete() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(account.methods.contains(.apple)
                         ? "This erases your sign-in and everything saved to it online, on every device. Apple will ask you to confirm. This can't be undone."
                         : "This erases your sign-in and everything saved to it online, on every device. This can't be undone.")
                }
                .alert("Couldn't delete the account", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(deleteError ?? "")
                }
            } else if account.isLoaded {
                // A push inside Settings' own NavigationStack: a sheet hung on a
                // List section (and a plain Button row) can silently do nothing.
                NavigationLink {
                    SignInView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign In")
                            Text("Optional. One account for iPhone, iPad and the web.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Account")
        } footer: {
            if !account.isSignedIn && account.isLoaded {
                Text("Your teams stay on this device whether or not you sign in.")
            }
        }
    }

    private func delete() {
        deleting = true
        Task {
            do {
                try await account.deleteAccount()
            } catch {
                // Backing out of Apple's sheet is a cancel, not a failure.
                if let message = AuthErrorWording.message(for: (error as? ASAuthorizationError)?.code == .canceled ? "cancel" : error.localizedDescription) {
                    deleteError = message
                }
            }
            deleting = false
        }
    }
}

// MARK: - Sign-in sheet

struct SignInView: View {
    @EnvironmentObject private var account: AccountManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Mode { case signIn, create, reset }
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var appleNonce = ""
    @FocusState private var focused: Field?
    private enum Field { case email, password }

    var body: some View {
        ScrollView {
                VStack(spacing: 20) {
                    Text(mode == .reset
                         ? "Enter your email and we'll send a link to choose a new password."
                         : "Use the same account on iPhone, iPad and app.stackthelineup.com.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if mode != .reset {
                        providerButtons
                        orDivider
                    }
                    emailForm

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let notice {
                        Label(notice, systemImage: "envelope.badge")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        .navigationTitle(mode == .create ? "Create Account" : mode == .reset ? "Reset Password" : "Sign In")
        .navigationBarTitleDisplayMode(.inline)
        // Signed in: back to Settings, which now shows the account.
        .onChange(of: account.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
    }

    // MARK: Apple and Google

    private var providerButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                appleNonce = SignInNonce.random()
                request.requestedScopes = [.fullName, .email]
                request.nonce = SignInNonce.sha256(appleNonce)
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    run { try await account.signInWithApple(authorization, rawNonce: appleNonce) }
                case .failure(let failure):
                    if (failure as? ASAuthorizationError)?.code != .canceled {
                        error = AuthErrorWording.message(for: failure.localizedDescription)
                    }
                }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(busy)

            Button {
                run { try await account.signInWithGoogle() }
            } label: {
                HStack(spacing: 8) {
                    Image("GoogleG")
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text("Continue with Google")
                        .font(.system(size: 17, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.12))
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.45, green: 0.47, blue: 0.46), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private var orDivider: some View {
        HStack {
            Rectangle().frame(height: 0.5).foregroundStyle(.quaternary)
            Text("or").font(.footnote).foregroundStyle(.secondary)
            Rectangle().frame(height: 0.5).foregroundStyle(.quaternary)
        }
    }

    // MARK: Email

    private var emailForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused, equals: .email)
                .submitLabel(mode == .reset ? .send : .next)
                .onSubmit { if mode == .reset { submit() } else { focused = .password } }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            if mode != .reset {
                SecureField(mode == .create ? "Password (at least 8 characters)" : "Password", text: $password)
                    .textContentType(mode == .create ? .newPassword : .password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }

            Button(action: submit) {
                Group {
                    if busy { ProgressView().tint(.white) }
                    else { Text(mode == .create ? "Create Account" : mode == .reset ? "Send Reset Link" : "Sign In") }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .disabled(busy || !canSubmit)

            HStack {
                if mode == .signIn {
                    Button("Forgot password?") { switchTo(.reset) }
                    Spacer()
                    Button("Create account") { switchTo(.create) }
                } else {
                    Button("Back to sign in") { switchTo(.signIn) }
                    Spacer()
                }
            }
            .font(.footnote)
        }
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        guard trimmedEmail.contains("@") else { return false }
        return mode == .reset || (mode == .create ? password.count >= 8 : !password.isEmpty)
    }

    private func switchTo(_ next: Mode) {
        mode = next
        error = nil
        notice = nil
    }

    private func submit() {
        guard canSubmit, !busy else { return }
        let email = trimmedEmail
        let password = password
        switch mode {
        case .signIn:
            run { try await account.signIn(email: email, password: password) }
        case .create:
            run {
                if try await !account.signUp(email: email, password: password) {
                    notice = "Check your email to confirm your account, then sign in here."
                    mode = .signIn
                }
            }
        case .reset:
            run {
                try await account.sendPasswordReset(email: email)
                notice = "If \(email) has an account, a reset link is on its way. It opens in your browser."
                mode = .signIn
            }
        }
    }

    /// Runs one sign-in step with the spinner on and the error shown in coach terms.
    private func run(_ step: @escaping () async throws -> Void) {
        busy = true
        error = nil
        notice = nil
        Task {
            do {
                try await step()
            } catch {
                self.error = AuthErrorWording.message(for: error.localizedDescription)
            }
            busy = false
        }
    }
}

#Preview("Sign in") {
    NavigationStack {
        SignInView()
    }
    .environmentObject(AccountManager.shared)
}

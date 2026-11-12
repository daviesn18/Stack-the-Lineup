//
//  AccountManager.swift
//  Lineup Builder
//
//  Optional sign-in (Merge 0): Sign in with Apple, Sign in with Google, or
//  email + password, all onto the same Supabase account the web app uses.
//  Nothing in the app requires it; signed out, everything works on the device
//  as before.
//
//  Account deletion revokes the Sign in with Apple token first (Apple requires
//  it once an app offers deletion): a fresh Apple authorization code goes to
//  the apple-revoke Edge Function, which revokes it with Apple's key, then
//  delete_account erases the account and everything it owns.
//

import AuthenticationServices
import Combine
import GoogleSignIn
import Supabase
import TelemetryDeck
import UIKit

@MainActor
final class AccountManager: ObservableObject {
    static let shared = AccountManager()

    /// The signed-in coach, or nil when signed out.
    @Published private(set) var user: User?
    /// False until the stored session has been read at launch.
    @Published private(set) var isLoaded = false

    private var listener: Task<Void, Never>?

    /// Nonisolated to avoid the iOS 26.0-26.3 isolated-deinit crash; see
    /// AutoFillNLConstraintService's deinit.
    nonisolated deinit {}

    var isSignedIn: Bool { user != nil }
    var email: String? { user?.email }

    var methods: [SignInMethod] {
        guard let user else { return [] }
        let providers = user.appMetadata["providers"]?.arrayValue?.compactMap(\.stringValue) ?? []
        return SignInMethod.from(providers: providers, primary: user.appMetadata["provider"]?.stringValue)
    }

    // MARK: - Session

    /// Starts following the session. Call once, at launch.
    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard let self else { return }
                self.apply(session?.user)
                if event == .initialSession { self.isLoaded = true }
            }
        }
    }

    private func apply(_ user: User?) {
        self.user = user
        CoachContext.set("account", user == nil ? "device_only" : "signed_in")
        // Same user ID as the web (the Supabase account ID), so one coach is one
        // TelemetryDeck user across iPhone, iPad and web. TelemetryDeck hashes it.
        // Signed out falls back to the default per-device ID.
        TelemetryDeck.updateDefaultUserID(to: user?.id.uuidString.lowercased())
    }

    // MARK: - Sign in

    /// Finishes Sign in with Apple from the system button. `rawNonce` is the
    /// value whose SHA-256 went into the request (SignInNonce).
    func signInWithApple(_ authorization: ASAuthorization, rawNonce: String) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AccountError.message("Apple didn't send back a sign-in token. Try again.")
        }
        try await supabase.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
            provider: .apple, idToken: idToken, nonce: rawNonce))
        // Apple shares the name only on the very first sign-in, so keep it.
        if let name = credential.fullName,
           case let formatted = PersonNameComponentsFormatter().string(from: name), !formatted.isEmpty {
            _ = try? await supabase.auth.update(user: UserAttributes(data: ["full_name": .string(formatted)]))
        }
        Analytics.signal("account.signedIn", parameters: ["method": "apple"])
    }

    func signInWithGoogle() async throws {
        guard let presenter = Self.topViewController() else {
            throw AccountError.message("Couldn't open Google sign-in. Try again.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: SupabaseConfig.googleIOSClientID)
        let rawNonce = SignInNonce.random()
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: SignInNonce.sha256(rawNonce))
        guard let idToken = result.user.idToken?.tokenString else {
            throw AccountError.message("Google didn't send back a sign-in token. Try again.")
        }
        try await supabase.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
            provider: .google, idToken: idToken, accessToken: result.user.accessToken.tokenString, nonce: rawNonce))
        Analytics.signal("account.signedIn", parameters: ["method": "google"])
    }

    func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
        Analytics.signal("account.signedIn", parameters: ["method": "email"])
    }

    /// Returns true when the account is ready now, false when the coach must
    /// confirm their email first (the link opens the web app; then they sign in here).
    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await supabase.auth.signUp(email: email, password: password, redirectTo: SupabaseConfig.webAppURL)
        Analytics.signal("account.signedUp", parameters: ["method": "email", "needsConfirmation": response.session == nil ? "true" : "false"])
        return response.session != nil
    }

    /// Emails a reset link; it opens the web app's Choose a password page.
    func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: SupabaseConfig.webAppURL)
    }

    // MARK: - Sign out and delete

    func signOut() async {
        GIDSignIn.sharedInstance.signOut()
        // Local scope: this device only, like the web's Sign out.
        try? await supabase.auth.signOut(scope: .local)
        Analytics.signal("account.signedOut")
    }

    /// Revokes Sign in with Apple (when the account uses it), then erases the
    /// account and everything it owns. Stops before deleting if the revoke fails,
    /// so a coach is never left with an Apple link to an account that's gone.
    func deleteAccount() async throws {
        if methods.contains(.apple) {
            let credential = try await AppleReauthorizer().authorize()
            guard let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) else {
                throw AccountError.message("Apple didn't confirm. Nothing was deleted.")
            }
            do {
                try await supabase.functions.invoke("apple-revoke", options: FunctionInvokeOptions(body: ["authorization_code": code]))
            } catch {
                throw AccountError.message("Couldn't disconnect Sign in with Apple, so nothing was deleted. Try again in a moment.")
            }
        }
        try await supabase.rpc("delete_account").execute()
        Analytics.signal("account.deleted")
        GIDSignIn.sharedInstance.signOut()
        try? await supabase.auth.signOut(scope: .local)
    }

    // MARK: - URLs

    /// Google's sign-in can return through the app's URL scheme. True when it
    /// was Google's, so ContentView doesn't treat it as a deep link or a file.
    func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

nonisolated enum AccountError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

// MARK: - Apple re-authorization (for deletion)

/// Asks Apple for a fresh authorization, whose one-time code the apple-revoke
/// function exchanges and revokes. Used only when deleting an account.
final class AppleReauthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    /// Nonisolated to avoid the iOS 26.0-26.3 isolated-deinit crash.
    nonisolated deinit {}

    func authorize() async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    // Apple calls these on the main thread.
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        MainActor.assumeIsolated {
            if let credential { continuation?.resume(returning: credential) }
            else { continuation?.resume(throwing: AccountError.message("Apple didn't confirm. Nothing was deleted.")) }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        MainActor.assumeIsolated {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

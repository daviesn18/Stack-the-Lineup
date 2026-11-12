//
//  AccountSupport.swift
//  Lineup Builder
//
//  Pure pieces of sign-in (Merge 0), kept free of UI and network so the unit
//  tests can cover them: the nonce Apple and Google sign the ID token with,
//  how a coach signed in, the wording of auth errors, and the coach-type
//  parameters every analytics signal carries.
//

import CryptoKit
import Foundation
import Synchronization

// MARK: - Nonce

/// Apple and Google put SHA-256(raw) into the ID token; Supabase is given the
/// raw value and checks it hashes to the same thing. That ties the token to
/// this one sign-in, so a stolen token can't be replayed.
nonisolated enum SignInNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Sign-in method

/// How a coach signs in, shown in Settings so "I used Google last time" is easy
/// to see. One account can have several (Supabase links Google and a confirmed
/// email that share an address).
nonisolated enum SignInMethod: String, CaseIterable, Sendable {
    case apple, google, email

    var label: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .email: "Email"
        }
    }

    /// From Supabase's `app_metadata.providers` (falling back to `provider`),
    /// in a fixed order, unknown providers dropped.
    static func from(providers: [String], primary: String?) -> [SignInMethod] {
        let names = Set((providers.isEmpty ? [primary].compactMap { $0 } : providers).map { $0.lowercased() })
        return allCases.filter { names.contains($0.rawValue) }
    }

    /// "Apple", "Apple and Google", "Apple, Google and Email".
    static func describe(_ methods: [SignInMethod]) -> String {
        let labels = methods.map(\.label)
        switch labels.count {
        case 0: return "Email"
        case 1: return labels[0]
        default: return labels.dropLast().joined(separator: ", ") + " and " + labels.last!
        }
    }
}

// MARK: - Error wording

nonisolated enum AuthErrorWording {
    /// A coach-facing sentence for a Supabase auth error message, or nil when
    /// there's nothing to say (the coach cancelled).
    static func message(for raw: String) -> String? {
        let text = raw.lowercased()
        if text.contains("cancel") { return nil }
        if text.contains("invalid login credentials") {
            return "That email and password don't match. Check both, or reset your password."
        }
        if text.contains("email not confirmed") {
            return "Confirm your email first: open the link we sent you, then sign in here."
        }
        if text.contains("signups not allowed") || text.contains("signup_disabled") || (text.contains("sign-ups") && text.contains("disabled")) {
            return "New accounts aren't open yet. If you were invited, sign in with the email address the invite went to."
        }
        if text.contains("user already registered") {
            return "There's already an account with that email. Sign in instead, or reset your password."
        }
        if text.contains("password should be at least") || text.contains("weak password") {
            return "Choose a longer password: at least 8 characters."
        }
        if text.contains("rate limit") || text.contains("too many") {
            return "Too many tries in a row. Wait a minute, then try again."
        }
        if text.contains("network") || text.contains("offline") || text.contains("internet") {
            return "Couldn't reach the server. Check your connection and try again."
        }
        return "Something went wrong: \(raw)"
    }
}

// MARK: - Coach context for analytics

/// The coach-type parameters every signal carries, named as on the web
/// (web/src/data/analytics.ts): platform (ios / ipados), account
/// (signed_in / device_only) and tier (pro / free). Set from the main actor,
/// read from wherever a signal is sent.
nonisolated enum CoachContext {
    private static let state = Mutex<[String: String]>(["account": "device_only"])

    static func set(_ key: String, _ value: String?) {
        state.withLock { $0[key] = value }
    }

    static var parameters: [String: String] {
        state.withLock { $0 }
    }

    /// A signal's own parameters win over the shared ones.
    static func merged(with own: [String: String]) -> [String: String] {
        parameters.merging(own) { _, signalValue in signalValue }
    }
}

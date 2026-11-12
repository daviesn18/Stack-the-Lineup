//
//  SupabaseConfig.swift
//  Lineup Builder
//
//  The one Supabase client (Merge 0: accounts; later merges: team data).
//
//  Debug builds talk to staging, Release builds (TestFlight, App Store) to
//  production. The keys here are the PUBLISHABLE keys: public by design, the
//  same ones the web app ships. Row-level security decides what a coach can
//  read or write. The secret / service-role keys never belong in the app.
//
//  The session is stored in the Keychain (the SDK's default on iOS), never in
//  UserDefaults. Widgets and App Intents don't read it.
//

import Foundation
import Supabase

nonisolated enum SupabaseConfig {
    #if DEBUG
    static let url = URL(string: "https://juzecenqlehzdlobvptd.supabase.co")!   // staging
    static let publishableKey = "sb_publishable_1eN9lQR2kDk2UZT4cf-CwQ_0pZJDjgC"
    static let environment = "staging"
    #else
    static let url = URL(string: "https://vxfuoqfjcrzfvbdgxnyo.supabase.co")!   // production
    static let publishableKey = "sb_publishable_-CvjNNug5pP_2hF_Kt6QjA_IPzMoXLp"
    static let environment = "production"
    #endif

    /// The "Stack the Lineup iOS" OAuth client in Google Cloud (Web 2b). Its
    /// reversed form is a URL scheme in Lineup-Builder-Info.plist.
    static let googleIOSClientID = "106946912827-6u1uasehdk6tpoldies28t77760ppshd.apps.googleusercontent.com"

    /// Where email confirmation and password-reset links land: the web app's
    /// /auth/confirm page (see web/supabase/templates). iOS needs no deep link.
    static let webAppURL = URL(string: "https://app.stackthelineup.com")!
}

/// `nonisolated` so background App Intents can reach it later without hopping
/// to the main actor; SupabaseClient is Sendable.
nonisolated let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.publishableKey,
    options: SupabaseClientOptions(
        // Report the stored session at launch without waiting for a refresh;
        // the SDK refreshes it in the background (and signs out if it can't).
        auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
    )
)

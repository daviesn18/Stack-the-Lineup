//
//  AccountPro.swift
//  Lineup Builder
//
//  Pro recorded on the coach's account: bought on the web, or on iPhone under
//  another Apple ID, and written to public.entitlements by the
//  revenuecat-webhook Edge Function (or granted by hand). PurchaseManager
//  grants Pro when either StoreKit or this says so.
//
//  The last answer is cached on the device, so Pro works offline and on a cold
//  launch before the network answers, and so background App Intents (which
//  can't wait on a fetch) see it too. The cache belongs to one account: it's
//  dropped at sign-out and whenever a different account signs in.
//

import Foundation
import Supabase
import os

nonisolated enum AccountPro {
    struct Snapshot: Codable, Equatable, Sendable {
        /// Lower-cased Supabase user ID this answer belongs to.
        var userID: String
        var isPro: Bool
        /// When Pro ends; nil = never (lifetime, or a hand grant).
        var expiresAt: Date?
        /// Where it was bought: app_store, stripe, promotional… (nil when not Pro).
        var store: String?

        func grantsPro(at now: Date) -> Bool {
            isPro && (expiresAt.map { $0 > now } ?? true)
        }
    }

    private static let key = "stl.accountPro"

    /// Whether the cached account answer grants Pro right now. Honors
    /// `expiresAt`, so a lapsed web subscription stops even offline.
    static func cachedGrantsPro(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        cached(defaults: defaults)?.grantsPro(at: now) ?? false
    }

    static func cached(defaults: UserDefaults = .standard) -> Snapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot?, defaults: UserDefaults = .standard) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Drops a cached answer that isn't this account's (nil = signed out), so
    /// one coach's Pro never carries over to the next person on the device.
    static func forget(unlessBelongingTo userID: String?, defaults: UserDefaults = .standard) {
        if let cached = cached(defaults: defaults), cached.userID != userID {
            save(nil, defaults: defaults)
        }
    }

    private struct Row: Decodable {
        let isPro: Bool
        let expiresAt: Date?
        let store: String?

        enum CodingKeys: String, CodingKey {
            case isPro = "is_pro"
            case expiresAt = "expires_at"
            case store
        }
    }

    /// Reads the signed-in coach's row (row-level security returns only theirs).
    /// nil when it couldn't be read, e.g. offline: keep whatever is cached.
    static func fetch(userID: String) async -> Snapshot? {
        do {
            // Not `store`: production gets that column only at the cutover, and
            // asking for a column that isn't there fails the whole read. A
            // missing key decodes as nil.
            let rows: [Row] = try await supabase.from("entitlements")
                .select("is_pro, expires_at")
                .limit(1)
                .execute()
                .value
            let row = rows.first
            return Snapshot(userID: userID, isPro: row?.isPro ?? false, expiresAt: row?.expiresAt, store: row?.store)
        } catch {
            Log.purchase.error("Account Pro read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

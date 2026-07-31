import Foundation
import SwiftUI
import Combine

// MARK: - STLRoute
//
// Where a deep link or an App Intent wants the app to land.
//
// Before this existed, `.onOpenURL` mapped EVERY stackthelineup:// URL to the
// Lineup tab and the iPad ignored it entirely, so the widget's link was the only
// thing the scheme could express. Spotlight results and OpenPlayerIntent need to
// address a specific player or game, on both device idioms.

nonisolated enum STLRoute: Equatable, Hashable {
    case players
    case lineup
    case positions
    case history
    /// Open a specific player. Switches teams first if they're on another roster.
    case player(UUID)
    /// Open a specific archived game.
    case gameLog(UUID)
    /// Make a team active without targeting anything inside it.
    case team(UUID)

    /// The tab this route lives on. Entity routes resolve to their host tab.
    var tab: Tab {
        switch self {
        case .players, .player:   return .players
        case .lineup:             return .lineup
        case .positions:          return .positions
        case .history, .gameLog:  return .history
        case .team:               return .lineup
        }
    }

    /// Idiom-independent tab identity. iPhone maps this to its `Int` tag and iPad
    /// to its `DetailTab`, so route handling doesn't have to know which is on screen.
    enum Tab {
        case players, lineup, positions, history

        /// Tag values in iPhoneTabView's TabView.
        var iPhoneTag: Int {
            switch self {
            case .players:   return 0
            case .lineup:    return 1
            case .positions: return 2
            case .history:   return 3
            }
        }
    }

    // MARK: - URL Parsing

    static let scheme = "stackthelineup"

    /// Parses a `stackthelineup://` URL.
    ///
    /// Accepts `stackthelineup://<host>` and `stackthelineup://<host>/<uuid>`.
    /// Returns nil for a foreign scheme so the caller can fall through to the
    /// existing .stlteam / .stlroster file-import handling.
    ///
    /// Unrecognized hosts fall back to `.lineup` — that preserves the shipped
    /// home screen widget's `stackthelineup://lineup` behavior and means an older
    /// widget build can never dead-end on a route this version doesn't know.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        let host = (url.host() ?? "").lowercased()
        let identifier = url.pathComponents
            .first { $0 != "/" }
            .flatMap { UUID(uuidString: $0) }

        switch host {
        case "players":  self = .players
        case "lineup":   self = .lineup
        case "positions": self = .positions
        case "history":
            self = identifier.map { .gameLog($0) } ?? .history
        case "player":
            guard let identifier else { return nil }
            self = .player(identifier)
        case "team":
            guard let identifier else { return nil }
            self = .team(identifier)
        default:
            self = .lineup
        }
    }

    /// The canonical URL for this route. Used by App Intents and Spotlight so the
    /// links they hand the system stay in sync with what `init(url:)` accepts.
    var url: URL? {
        switch self {
        case .players:            return URL(string: "\(Self.scheme)://players")
        case .lineup:             return URL(string: "\(Self.scheme)://lineup")
        case .positions:          return URL(string: "\(Self.scheme)://positions")
        case .history:            return URL(string: "\(Self.scheme)://history")
        case .player(let id):     return URL(string: "\(Self.scheme)://player/\(id.uuidString)")
        case .gameLog(let id):    return URL(string: "\(Self.scheme)://history/\(id.uuidString)")
        case .team(let id):       return URL(string: "\(Self.scheme)://team/\(id.uuidString)")
        }
    }
}

// MARK: - Spotlight Selection

extension STLRoute {

    /// Resolves the identifier Spotlight hands back when a coach taps an indexed
    /// entity result.
    ///
    /// Two things make this necessary rather than optional. Conforming an entity
    /// to `IndexedEntity` gets it *listed* in Spotlight, but tapping the result
    /// only launches the app — it lands on whatever was last on screen, which
    /// reads as the feature being broken. And `URLRepresentableEntity`, which
    /// looks like it should cover this, does not: verified on iOS 26.5, adding
    /// `urlRepresentation` changed nothing about tap-through. The
    /// `CSSearchableItemActionType` activity is the path that actually fires.
    ///
    /// The identifier's encoding belongs to AppIntents and is undocumented, so
    /// rather than pattern-match a shape Apple can change, pull out any UUID it
    /// contains and check it against rosters we actually hold. An id that matches
    /// nothing returns nil instead of guessing.
    static func fromSpotlightIdentifier(_ identifier: String,
                                        playerIDs: Set<UUID>,
                                        teamIDs: Set<UUID>) -> STLRoute? {
        for candidate in uuids(in: identifier) {
            if playerIDs.contains(candidate) { return .player(candidate) }
            if teamIDs.contains(candidate)   { return .team(candidate) }
        }
        return nil
    }

    /// Every UUID-shaped substring, in order. A sliding window rather than a
    /// regex: `UUID(uuidString:)` is already the exact validator, and identifiers
    /// are a few dozen characters long.
    static func uuids(in text: String) -> [UUID] {
        let characters = Array(text)
        let width = 36
        guard characters.count >= width else { return [] }

        return (0...(characters.count - width)).compactMap { start in
            UUID(uuidString: String(characters[start..<(start + width)]))
        }
    }
}

// MARK: - AppRouter
//
// Carries a route from whatever produced it (URL open, App Intent, Spotlight tap)
// to the view hierarchy that's currently on screen.
//
// iPhone and iPad keep entirely separate navigation state — an `Int` tab tag vs.
// a `DetailTab` enum, neither aware of the other. Both observe this object and
// map the route onto their own selection, so producers never have to care which
// idiom is running.

@MainActor
final class AppRouter: ObservableObject {

    /// App Intents declared in the app target run inside the app's own process,
    /// so `perform()` can set a route here directly — but it may run *before*
    /// ContentView exists on a cold launch, which is the common case for Siri and
    /// Spotlight. A shared instance is what lets the request outlive that gap:
    /// whichever hierarchy appears next drains it via consumePendingRoute().
    static let shared = AppRouter()

    /// A route plus a nonce. The nonce makes every request a distinct value so
    /// `.onChange` fires even when the same route is requested twice in a row —
    /// asking Siri for the same player twice should navigate both times.
    struct Request: Equatable {
        let route: STLRoute
        let nonce: UUID
        let createdAt: Date

        init(_ route: STLRoute, createdAt: Date = Date()) {
            self.route = route
            self.nonce = UUID()
            self.createdAt = createdAt
        }

        /// Requests are never cleared after handling (see `request`), so the last
        /// one lingers indefinitely. A view hierarchy appearing for the first time
        /// — a second iPad window, say — would otherwise drain a route the coach
        /// asked for an hour ago and yank the new window somewhere unexpected.
        ///
        /// Only consulted on a first-ever drain. The cold-launch case this window
        /// exists to protect is milliseconds old, so the bound is generous.
        var isFresh: Bool { Date().timeIntervalSince(createdAt) < 60 }
    }

    /// Set by producers, observed by both navigation hierarchies. Deliberately
    /// not cleared after handling: consumers key off the changing nonce, and
    /// clearing would race the two observers against each other.
    @Published var request: Request?

    func route(to route: STLRoute) {
        request = Request(route)
    }

    // MARK: - Staged Auto-Fill
    //
    // FillLineupIntent computes a fill against the on-disk team (via
    // TeamStorage) but must not write it back itself: when the app is already
    // running, LineupStore holds the authoritative in-memory copy and a write
    // behind its back is stomped by the next store.save(). So the intent stages
    // the finished lineup here and ContentView — which owns the store — applies
    // it. Same handoff shape as a route, for the same cold-launch reason.

    /// A finished Auto-Fill waiting for the store to apply it.
    ///
    /// Equatable on the nonce alone: every staged fill is a distinct event, and
    /// comparing outcomes would force Equatable onto Lineup for no benefit.
    struct PendingFill: Equatable {
        static func == (lhs: PendingFill, rhs: PendingFill) -> Bool {
            lhs.nonce == rhs.nonce
        }

        /// The team the fill was computed against. Applied by id rather than to
        /// whatever happens to be active, so "fill the Tigers lineup" can't land
        /// on the wrong roster.
        let teamID: UUID
        let outcome: AutoFillOutcome
        let nonce: UUID
        let createdAt: Date

        init(teamID: UUID, outcome: AutoFillOutcome, createdAt: Date = Date()) {
            self.teamID = teamID
            self.outcome = outcome
            self.nonce = UUID()
            self.createdAt = createdAt
        }

        /// See `Request.isFresh` — same reasoning, and a stale fill is worse:
        /// it would overwrite a lineup the coach has edited since.
        var isFresh: Bool { Date().timeIntervalSince(createdAt) < 60 }
    }

    @Published var pendingFill: PendingFill?

    func stageFill(_ outcome: AutoFillOutcome, teamID: UUID) {
        pendingFill = PendingFill(teamID: teamID, outcome: outcome)
    }

    // MARK: - Paywall
    //
    // A Pro-gated intent can't just throw and stop. `openAppWhenRun = true`
    // brings the app forward whether perform() succeeds or fails, so a thrown
    // error leaves a non-Pro coach staring at whatever tab they left open with
    // no explanation — the same dead end as a Spotlight result that opens the
    // app and goes nowhere. Asking Siri to auto-fill should do what tapping the
    // bolt button does: show the paywall.
    //
    // Deliberately not an STLRoute case: routes round-trip through
    // `stackthelineup://` URLs, and a paywall nobody navigated to is not
    // something an arbitrary link should be able to summon.

    /// No nonce or freshness window here, unlike Request and PendingFill:
    /// `.sheet(item:)` writes nil back on dismiss, so a request can't be
    /// replayed and can't go stale.
    struct PaywallRequest: Identifiable, Equatable {
        let id = UUID()
        /// Attribution string for PaywallView, e.g. "intent_fill_lineup".
        let source: String
    }

    @Published var paywallRequest: PaywallRequest?

    func requestPaywall(source: String) {
        paywallRequest = PaywallRequest(source: source)
    }

    /// Returns false when the URL isn't ours, so the caller can fall through to
    /// the .stlteam / .stlroster file-import paths.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let parsed = STLRoute(url: url) else { return false }
        route(to: parsed)
        return true
    }
}

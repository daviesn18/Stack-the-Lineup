import os
import AppIntents
import CoreSpotlight
import Foundation

// MARK: - PlayerEntity
//
// A roster player as Siri, Shortcuts and Spotlight see them.
//
// Flattened from `Player` rather than wrapping it: the entity carries the team
// name so a result can say which roster it came from, and it must stay a plain
// Sendable value that survives being handed to the system and returned to us in
// a later process. Only the `id` is authoritative — everything else is a display
// snapshot, and callers re-read the live Player through the store by id.

nonisolated struct PlayerEntity: AppEntity, IndexedEntity, URLRepresentableEntity {

    let id: UUID
    let firstName: String
    let lastName: String
    let jerseyNumber: String
    /// The roster this player belongs to. A multi-team coach can have the same
    /// child on two rosters as two separate Player records; each is its own entity.
    let teamID: UUID
    let teamName: String
    /// Positions the coach marked as a strength. Used for Spotlight keywords so
    /// "Tigers pitcher" can find someone — not for any lineup decision.
    let strengths: [FieldPositionAppEnum]

    var name: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }

    var displayNameWithNumber: String {
        jerseyNumber.isEmpty ? name : "#\(jerseyNumber) \(name)"
    }

    // MARK: - AppEntity

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Player")

    static let defaultQuery = PlayerEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayNameWithNumber)",
            subtitle: teamName.isEmpty ? nil : "\(teamName)",
            image: .init(systemName: "person.fill")
        )
    }

    // MARK: - URLRepresentableEntity
    //
    // Conforming to IndexedEntity alone gets a player *listed* in Spotlight, but
    // tapping the result only launches the app — it lands on whatever tab was
    // last open, which reads as the feature being broken. This is what makes the
    // result actually open the player.
    //
    // Points at the same `stackthelineup://player/<uuid>` link the widget scheme
    // already uses, so Spotlight tap-through runs through STLRoute and the
    // cold-launch drain in ContentView rather than a second routing path.
    // STLRouteTests' round-trip test covers the format on the parsing side.

    static let urlRepresentation: URLRepresentation = "stackthelineup://player/\(.id)"

    // MARK: - IndexedEntity

    /// Spotlight matches the query against keywords as well as the title, so this
    /// is what makes "12", "number 12" and "Tigers" find a player whose displayed
    /// title is just their name.
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = displayNameWithNumber
        set.contentDescription = teamName.isEmpty ? nil : teamName

        var keywords: [String] = [firstName, lastName, name]
        if !jerseyNumber.isEmpty {
            keywords.append(jerseyNumber)
            keywords.append("number \(jerseyNumber)")
            keywords.append("#\(jerseyNumber)")
        }
        if !teamName.isEmpty { keywords.append(teamName) }
        keywords.append(contentsOf: strengths.map(\.displayName))
        set.keywords = keywords.filter { !$0.isEmpty }

        return set
    }

    // MARK: - Construction

    init(_ player: Player, team: Team) {
        self.id           = player.id
        self.firstName    = player.firstName
        self.lastName     = player.lastName
        self.jerseyNumber = player.number
        self.teamID       = team.id
        self.teamName     = team.name
        self.strengths    = player.positionPreferences
            .filter { $0.value == .strength }
            .keys
            .map(FieldPositionAppEnum.init)
            .sorted { $0.displayName < $1.displayName }
    }

    /// Test seam — lets the ranking tests build entities without a Team.
    init(id: UUID = UUID(), firstName: String, lastName: String, jerseyNumber: String = "",
         teamID: UUID = UUID(), teamName: String = "", strengths: [FieldPositionAppEnum] = []) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.jerseyNumber = jerseyNumber
        self.teamID = teamID
        self.teamName = teamName
        self.strengths = strengths
    }
}

// MARK: - Roster Snapshot

extension PlayerEntity {
    /// Every player on every team, each paired with the roster they came from.
    ///
    /// Deliberately not limited to the active team. `ContentView.applyRoute`
    /// switches to the owning team before opening a player, so a hit on another
    /// roster resolves correctly — and a coach running a spring and a fall team
    /// searching a name expects to find them either way. The team name in the
    /// subtitle is what disambiguates two same-named results.
    static func allFromStorage() -> [PlayerEntity] {
        TeamStorage.loadTeamsForReading().teams.flatMap { team in
            team.players.map { PlayerEntity($0, team: team) }
        }
    }
}

// MARK: - Search
//
// Split out from the query so the ranking rules can be tested without touching
// UserDefaults. Siri hands over a transcribed string with no structure, so the
// scoring below is the whole of "did the coach mean this player".

nonisolated enum PlayerSearch {

    /// Case- and diacritic-insensitive, whitespace-trimmed.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Players matching `query`, best match first. An empty query returns everyone,
    /// which is what Shortcuts' parameter picker wants.
    static func matches(query rawQuery: String, in players: [PlayerEntity]) -> [PlayerEntity] {
        let query = normalize(rawQuery)
        guard !query.isEmpty else { return players.sorted { $0.name < $1.name } }

        // "number 12" and "#12" both mean the jersey. Siri transcribes the spoken
        // form; Spotlight passes the typed one.
        let jerseyQuery = query
            .replacingOccurrences(of: "number", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespaces)

        return players
            .compactMap { player -> (player: PlayerEntity, score: Int)? in
                guard let score = score(player, query: query, jerseyQuery: jerseyQuery) else { return nil }
                return (player, score)
            }
            .sorted { ($0.score, $0.player.name) < ($1.score, $1.player.name) }
            .map(\.player)
    }

    /// Lower is better. nil means no match at all.
    private static func score(_ player: PlayerEntity, query: String, jerseyQuery: String) -> Int? {
        let name   = normalize(player.name)
        let first  = normalize(player.firstName)
        let last   = normalize(player.lastName)
        let jersey = normalize(player.jerseyNumber)
        let team   = normalize(player.teamName)

        if name == query || first == query || last == query { return 0 }
        if !jersey.isEmpty, jersey == jerseyQuery { return 1 }
        if first.hasPrefix(query) || last.hasPrefix(query) || name.hasPrefix(query) { return 2 }
        if name.contains(query) { return 3 }
        // Team name matches last: "Tigers" should list the roster, but never
        // outrank a coach who actually said a player's name.
        if !team.isEmpty, team.contains(query) { return 4 }
        return nil
    }
}

// MARK: - PlayerEntityQuery

nonisolated struct PlayerEntityQuery: EntityQuery, EntityStringQuery {

    func entities(for identifiers: [UUID]) async throws -> [PlayerEntity] {
        let wanted = Set(identifiers)
        // Preserve the caller's requested order — Shortcuts relies on it.
        let byID = Dictionary(
            PlayerEntity.allFromStorage()
                .filter { wanted.contains($0.id) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return identifiers.compactMap { byID[$0] }
    }

    func entities(matching string: String) async throws -> [PlayerEntity] {
        let roster = PlayerEntity.allFromStorage()
        let hits = PlayerSearch.matches(query: string, in: roster)
        // Counts are public; the spoken name is not — it's whatever Siri
        // transcribed of a child's name. `roster: 0` is the answer to "why
        // didn't it find anyone": the install has no players, so no query can
        // match. That looks identical to a resolution failure from the outside.
        Log.intents.info(
            "Player lookup: roster \(roster.count, privacy: .public), matches \(hits.count, privacy: .public), query \(string)"
        )
        return hits
    }

    /// What Shortcuts shows before the coach types anything. The active roster
    /// first, since that's the team they're working on today.
    func suggestedEntities() async throws -> [PlayerEntity] {
        let (teams, activeTeam) = TeamStorage.loadTeamsForReading()
        // Rank rather than a bare equality predicate — `sorted` requires a strict
        // weak ordering and misbehaves given anything less.
        let rank = { (team: Team) in team.id == activeTeam?.id ? 0 : 1 }
        let ordered = teams.sorted { rank($0) < rank($1) }
        return ordered.flatMap { team in
            team.players
                .sorted { $0.firstName < $1.firstName }
                .map { PlayerEntity($0, team: team) }
        }
    }
}

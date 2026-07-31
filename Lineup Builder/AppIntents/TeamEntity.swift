import AppIntents
import CoreSpotlight
import Foundation

// MARK: - TeamEntity
//
// A roster as Siri, Shortcuts and Spotlight see it. Same flattening rationale as
// PlayerEntity: only `id` is authoritative, the rest is a display snapshot.
//
// Carries the roster size and game count because those are the two things that
// make a Spotlight result useful at a glance — and because Phase 3's recap intent
// takes a TeamEntity parameter and will want them for disambiguation dialog.

nonisolated struct TeamEntity: AppEntity, IndexedEntity, URLRepresentableEntity {

    let id: UUID
    let name: String
    let playerCount: Int
    let gameCount: Int

    /// Falls back to the same placeholder the widget uses, so an unnamed team
    /// never surfaces as a blank Spotlight row.
    var displayName: String { name.isEmpty ? "My Team" : name }

    // MARK: - AppEntity

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Team")

    static let defaultQuery = TeamEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(playerCount) players",
            image: .init(systemName: "person.3.fill")
        )
    }

    // MARK: - URLRepresentableEntity
    //
    // See the note on PlayerEntity — without this a Spotlight tap only launches
    // the app instead of switching to the team.

    static let urlRepresentation: URLRepresentation = "stackthelineup://team/\(.id)"

    // MARK: - IndexedEntity

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.title = displayName
        set.contentDescription = "\(playerCount) players · \(gameCount) games"
        set.keywords = [displayName, "team", "roster", "lineup"]
        return set
    }

    // MARK: - Construction

    init(_ team: Team) {
        self.id          = team.id
        self.name        = team.name
        self.playerCount = team.players.count
        self.gameCount   = team.gameLogs.count
    }

    /// Test seam.
    init(id: UUID = UUID(), name: String, playerCount: Int = 0, gameCount: Int = 0) {
        self.id = id
        self.name = name
        self.playerCount = playerCount
        self.gameCount = gameCount
    }
}

extension TeamEntity {
    static func allFromStorage() -> [TeamEntity] {
        TeamStorage.loadTeamsForReading().teams.map(TeamEntity.init)
    }
}

// MARK: - TeamEntityQuery

nonisolated struct TeamEntityQuery: EntityQuery, EntityStringQuery {

    func entities(for identifiers: [UUID]) async throws -> [TeamEntity] {
        let wanted = Set(identifiers)
        let byID = Dictionary(
            TeamEntity.allFromStorage()
                .filter { wanted.contains($0.id) }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return identifiers.compactMap { byID[$0] }
    }

    func entities(matching string: String) async throws -> [TeamEntity] {
        TeamSearch.matches(query: string, in: TeamEntity.allFromStorage())
    }

    /// Most coaches have exactly one team, so listing all of them is the whole
    /// picker. The active team leads.
    func suggestedEntities() async throws -> [TeamEntity] {
        let (teams, activeTeam) = TeamStorage.loadTeamsForReading()
        let rank = { (team: Team) in team.id == activeTeam?.id ? 0 : 1 }
        return teams.sorted { rank($0) < rank($1) }.map(TeamEntity.init)
    }
}

// MARK: - Search

nonisolated enum TeamSearch {

    static func matches(query rawQuery: String, in teams: [TeamEntity]) -> [TeamEntity] {
        let query = PlayerSearch.normalize(rawQuery)
        guard !query.isEmpty else { return teams }

        return teams
            .compactMap { team -> (team: TeamEntity, score: Int)? in
                let name = PlayerSearch.normalize(team.displayName)
                if name == query        { return (team, 0) }
                if name.hasPrefix(query) { return (team, 1) }
                if name.contains(query)  { return (team, 2) }
                return nil
            }
            .sorted { ($0.score, $0.team.displayName) < ($1.score, $1.team.displayName) }
            .map(\.team)
    }
}

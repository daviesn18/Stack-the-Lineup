import AppIntents
import Foundation

// MARK: - GameLogEntity
//
// An archived game, addressable from Shortcuts and from Siri disambiguation.
//
// Deliberately **not** `IndexedEntity`, unlike PlayerEntity and TeamEntity.
// Indexing something in Spotlight is a promise that tapping the result goes
// somewhere, and that takes a `CSSearchableItemActionType` handler per type
// (see the Phase 1 notes). Games are also the one thing a coach searches by
// *when*, not by name, which Spotlight is poor at. If we index them later,
// index and tap-through ship together or not at all.

nonisolated struct GameLogEntity: AppEntity {

    let id: UUID
    let opponent: String
    let gameDate: Date
    let inningsPlayed: Int
    let teamID: UUID
    let teamName: String

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Game")
    static let defaultQuery = GameLogEntityQuery()

    /// "vs Rangers" — or just the date when the opponent was never entered,
    /// which is common for scrimmages.
    var displayName: String {
        opponent.isEmpty ? "Game on \(GameRecap.datePhrase(gameDate))" : "vs \(opponent)"
    }

    var displayRepresentation: DisplayRepresentation {
        // The subtitle carries the date because that's the only thing that
        // distinguishes two games against the same opponent — which is exactly
        // the case a disambiguation prompt exists to resolve.
        DisplayRepresentation(
            title: "\(displayName)",
            subtitle: "\(Self.subtitleFormatter.string(from: gameDate)) · \(teamName)",
            image: .init(systemName: "sportscourt.fill")
        )
    }

    private static let subtitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    init(_ log: GameLog, team: Team) {
        self.id = log.id
        self.opponent = log.opponent
        self.gameDate = log.gameDate
        self.inningsPlayed = log.inningsPlayed
        self.teamID = team.id
        self.teamName = TeamEntity(team).displayName
    }
}

// MARK: - Query

nonisolated struct GameLogEntityQuery: EntityQuery {

    func entities(for identifiers: [UUID]) async throws -> [GameLogEntity] {
        let all = GameLogEntity.allFromStorage()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    /// Most recent first, active team first. A coach picking a game from
    /// Shortcuts is almost always reaching for the last one they played.
    func suggestedEntities() async throws -> [GameLogEntity] {
        Array(GameLogEntity.allFromStorage().prefix(20))
    }
}

extension GameLogEntity {

    /// Every archived game across every team, newest first, with the active
    /// team's games ahead of other teams' games from the same day.
    static func allFromStorage() -> [GameLogEntity] {
        let (teams, activeTeam) = TeamStorage.loadTeamsForReading()
        return teams
            .flatMap { team in team.gameLogs.map { GameLogEntity($0, team: team) } }
            .sorted { lhs, rhs in
                if lhs.gameDate != rhs.gameDate { return lhs.gameDate > rhs.gameDate }
                let lhsActive = lhs.teamID == activeTeam?.id
                let rhsActive = rhs.teamID == activeTeam?.id
                if lhsActive != rhsActive { return lhsActive }
                return lhs.opponent < rhs.opponent
            }
    }
}

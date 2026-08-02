import AppIntents
import CoreSpotlight
import Foundation
import os

// MARK: - STLSpotlightIndexer
//
// Publishes players and teams to the on-device Spotlight index so searching a
// child's name from the home screen finds them.
//
// Called from two places: app launch, and the tail of LineupStore.saveLocalOnly().
// The save hook matters more than it looks — save() fires on every position drag,
// so an unconditional reindex would hammer CoreSpotlight throughout a game. The
// signature check below is what keeps it to roster edits only.

nonisolated enum STLSpotlightIndexer {

    /// Remembers the last roster shape that was successfully indexed.
    ///
    /// An actor rather than a static var: this is touched from the detached task
    /// in saveLocalOnly() and from launch, and the read-then-write has to be
    /// atomic or two concurrent saves can both decide to skip.
    private actor SignatureStore {
        private var lastIndexed: Int?

        func needsIndexing(_ signature: Int) -> Bool { lastIndexed != signature }

        /// Recorded only after a full successful pass. If indexing throws partway
        /// the signature stays stale, so the next save retries instead of leaving
        /// Spotlight empty until the roster happens to change again.
        func recordSuccess(_ signature: Int) { lastIndexed = signature }
    }

    private static let signatures = SignatureStore()

    // MARK: - Entry Points

    /// Reads the roster from storage. Use at launch, where there is no snapshot
    /// already in hand.
    static func reindexIfNeeded() async {
        await reindexIfNeeded(teams: TeamStorage.loadTeamsForReading().teams)
    }

    /// Uses a snapshot the caller already holds, avoiding a second decode of the
    /// teams blob on the save path.
    static func reindexIfNeeded(teams: [Team]) async {
        let players = teams.flatMap { team in team.players.map { PlayerEntity($0, team: team) } }
        let teamEntities = teams.map(TeamEntity.init)

        let signature = signature(players: players, teams: teamEntities)
        guard await signatures.needsIndexing(signature) else { return }

        let index = CSSearchableIndex.default()
        do {
            // Delete-then-index rather than a plain upsert: upserting alone would
            // leave a removed player searchable forever. The window where the
            // index is empty is sub-millisecond and only opens on a roster edit.
            try await index.deleteAppEntities(ofType: PlayerEntity.self)
            try await index.deleteAppEntities(ofType: TeamEntity.self)
            try await index.indexAppEntities(players)
            try await index.indexAppEntities(teamEntities)
            await signatures.recordSuccess(signature)
        } catch {
            Log.spotlight.error("Spotlight reindex failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Change Detection

    /// Hashes exactly what the index displays, and nothing else. Inning
    /// assignments, schedule changes and pitch counts are all excluded, so an
    /// in-game editing session never triggers a reindex — but the game *count*
    /// is included, because it appears in a team's Spotlight subtitle and would
    /// otherwise sit stale until an unrelated roster edit refreshed it.
    private static func signature(players: [PlayerEntity], teams: [TeamEntity]) -> Int {
        var hasher = Hasher()
        for player in players {
            hasher.combine(player.id)
            hasher.combine(player.firstName)
            hasher.combine(player.lastName)
            hasher.combine(player.jerseyNumber)
            hasher.combine(player.teamName)
            hasher.combine(player.strengths.map(\.rawValue))
        }
        for team in teams {
            hasher.combine(team.id)
            hasher.combine(team.displayName)
            hasher.combine(team.playerCount)
            hasher.combine(team.gameCount)
        }
        return hasher.finalize()
    }
}

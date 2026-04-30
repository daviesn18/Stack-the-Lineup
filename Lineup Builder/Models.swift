import Foundation
import SwiftUI
import Combine

// MARK: - PDF Types

enum PDFType {
    case battingOrder
    case coachesGuide
}

struct PDFDocument: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
}

// MARK: - Positions

enum FieldPosition: String, CaseIterable, Codable, Sendable {
    case pitcher = "P"
    case catcher = "C"
    case firstBase = "1B"
    case secondBase = "2B"
    case shortstop = "SS"
    case thirdBase = "3B"
    case leftField = "LF"
    case centerField = "CF"
    case rightField = "RF"
    case bench = "Bench"
    case absent = "ABS"

    nonisolated var displayName: String {
        switch self {
        case .pitcher: return "Pitcher"
        case .catcher: return "Catcher"
        case .firstBase: return "1st Base"
        case .secondBase: return "2nd Base"
        case .thirdBase: return "3rd Base"
        case .shortstop: return "Shortstop"
        case .leftField: return "Left Field"
        case .centerField: return "Center Field"
        case .rightField: return "Right Field"
        case .bench: return "Bench"
        case .absent: return "Absent"
        }
    }

    nonisolated var isInfield: Bool {
        switch self {
        case .pitcher, .catcher, .firstBase, .secondBase, .thirdBase, .shortstop:
            return true
        default:
            return false
        }
    }

    nonisolated var isOutfield: Bool {
        switch self {
        case .leftField, .centerField, .rightField:
            return true
        default:
            return false
        }
    }

    nonisolated var isBench: Bool { self == .bench }

    /// True for the ABS position — player is present in lineup but not on field for this inning.
    nonisolated var isAbsent: Bool { self == .absent }

    /// True for any position that does not count as a fielding inning (bench or absent).
    nonisolated var isNonFielding: Bool { self == .bench || self == .absent }

    /// Solid fill color used for position badges in live editing UI (Positions tab,
    /// position picker). Centralizes the color rules so views don't need to
    /// recompute them. NOTE: this is the live-editing palette — historical/archived
    /// surfaces (Game Log Detail) intentionally use `.secondary` for bench rather
    /// than gray, so they keep their own helper.
    nonisolated var badgeColor: Color {
        if isAbsent { return Color(.systemGray2) }
        if isBench { return .gray }
        if isInfield { return .blue }
        return .green
    }

    nonisolated static var fieldPositions: [FieldPosition] {
        allCases.filter { $0 != .bench && $0 != .absent }
    }

    nonisolated static var infieldPositions: [FieldPosition] {
        allCases.filter { $0.isInfield }
    }

    nonisolated static var outfieldPositions: [FieldPosition] {
        allCases.filter { $0.isOutfield }
    }
}

// MARK: - Position Preference Tier

enum PositionPreferenceTier: String, Codable, CaseIterable, Sendable {
    case strength  = "Strength"
    case capable   = "Capable"
    case emergency = "Emergency"
    case never     = "Never"

    nonisolated var displayName: String { rawValue }

    nonisolated var color: Color {
        switch self {
        case .strength:  return .green
        case .capable:   return .blue
        case .emergency: return .orange
        case .never:     return .red
        }
    }

    // Custom decode: unknown raw values (e.g. old "Primary"/"Secondary" from
    // a previous build) silently decode as nil rather than throwing and
    // taking down the entire Player array with them.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let value = PositionPreferenceTier(rawValue: raw) {
            self = value
        } else {
            // Map legacy names forward; anything else falls to .capable as a safe default
            switch raw {
            case "Primary":   self = .strength
            case "Secondary": self = .capable
            default:          self = .capable
            }
        }
    }
}

// MARK: - Player

struct Player: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var firstName: String
    var lastName: String
    var number: String
    var leagueAge: Int? = nil
    var positionPreferences: [FieldPosition: PositionPreferenceTier] = [:]

    nonisolated var displayName: String { "\(firstName) \(lastName)" }
    nonisolated var displayNameWithNumber: String {
        number.isEmpty ? displayName : "#\(number) \(firstName) \(lastName)"
    }
    nonisolated var shortName: String {
        let initial = lastName.first.map { String($0) } ?? ""
        return initial.isEmpty ? firstName : "\(firstName) \(initial)."
    }

    // Explicit memberwise init — required because defining init(from:) below
    // suppresses the compiler-synthesized memberwise initializer.
    init(id: UUID = UUID(), firstName: String, lastName: String, number: String,
         leagueAge: Int? = nil,
         positionPreferences: [FieldPosition: PositionPreferenceTier] = [:]) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.number = number
        self.leagueAge = leagueAge
        self.positionPreferences = positionPreferences
    }

    // Custom decode: if positionPreferences fails for any reason (e.g. schema
    // change, unrecognized keys), fall back to [:] so the player still loads.
    // firstName, lastName, number are load-bearing — if those fail, propagate.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id        = try container.decode(UUID.self, forKey: .id)
        firstName = try container.decode(String.self, forKey: .firstName)
        lastName  = try container.decode(String.self, forKey: .lastName)
        number    = try container.decode(String.self, forKey: .number)
        leagueAge = try container.decodeIfPresent(Int.self, forKey: .leagueAge)
        positionPreferences = (try? container.decodeIfPresent(
            [FieldPosition: PositionPreferenceTier].self,
            forKey: .positionPreferences
        )) ?? [:]
    }
}

// MARK: - Inning Assignment

struct InningAssignment: Codable, Sendable {
    var assignments: [UUID: FieldPosition] = [:]

    mutating func assign(player: Player, position: FieldPosition) {
        assignments[player.id] = position
    }

    mutating func removeAssignment(for player: Player) {
        assignments.removeValue(forKey: player.id)
    }

    nonisolated func position(for player: Player) -> FieldPosition? {
        assignments[player.id]
    }

    nonisolated func player(at position: FieldPosition, in players: [Player]) -> Player? {
        guard let pid = assignments.first(where: { $0.value == position })?.key else { return nil }
        return players.first(where: { $0.id == pid })
    }
}

// MARK: - Lineup Status

/// Soft status indicating whether a coach considers the lineup locked in.
/// Finalized reverts silently to Draft on any lineup mutation.
enum LineupStatus: String, Codable, Sendable {
    case draft
    case finalized
}

// MARK: - Lineup

struct Lineup: Codable, Sendable {
    /// Number of innings in a standard game. Hardcoded for now — when v2.4 ships
    /// configurable league rules, this becomes a per-team value on FairPlayConfig
    /// and call sites read from `team.fairPlayConfig.inningCount` instead.
    /// Until then, this constant is the single source of truth.
    static let inningCount = 7

    var gameDate: Date = Date()
    var opponent: String = ""
    var battingOrder: [UUID] = []
    var innings: [InningAssignment] = Array(repeating: InningAssignment(), count: Lineup.inningCount)
    var absentPlayerIDs: Set<UUID> = []
    /// Soft status — Draft by default. Finalized is a coach-set signal that the
    /// lineup is locked in. Any mutation to positions, batting order, or game info
    /// silently reverts this to .draft via revertToDraftIfFinalized() in LineupStore.
    var status: LineupStatus = .draft

    // Explicit memberwise init so views can construct a Lineup() directly.
    init(
        gameDate: Date = Date(),
        opponent: String = "",
        battingOrder: [UUID] = [],
        innings: [InningAssignment] = Array(repeating: InningAssignment(), count: Lineup.inningCount),
        absentPlayerIDs: Set<UUID> = [],
        status: LineupStatus = .draft
    ) {
        self.gameDate        = gameDate
        self.opponent        = opponent
        self.battingOrder    = battingOrder
        self.innings         = innings
        self.absentPlayerIDs = absentPlayerIDs
        self.status          = status
    }

    // Custom decode: every field uses decodeIfPresent with a safe default so
    // that adding new fields (e.g. `status`) never breaks decoding of data
    // written by an older build that didn't include that key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gameDate        = (try? c.decode(Date.self,               forKey: .gameDate))        ?? Date()
        opponent        = (try? c.decode(String.self,             forKey: .opponent))        ?? ""
        battingOrder    = (try? c.decode([UUID].self,             forKey: .battingOrder))    ?? []
        innings         = (try? c.decode([InningAssignment].self, forKey: .innings))         ?? Array(repeating: InningAssignment(), count: Lineup.inningCount)
        absentPlayerIDs = (try? c.decode(Set<UUID>.self,          forKey: .absentPlayerIDs)) ?? []
        // status is new in 2.2 — old data won't have this key, default to .draft
        status          = (try? c.decode(LineupStatus.self,       forKey: .status))          ?? .draft
    }

    mutating func toggleAbsent(player: Player) {
        if absentPlayerIDs.contains(player.id) {
            absentPlayerIDs.remove(player.id)
        } else {
            absentPlayerIDs.insert(player.id)
            battingOrder.removeAll { $0 == player.id }
            for i in 0..<innings.count {
                innings[i].removeAssignment(for: player)
            }
        }
    }

    nonisolated func isAbsent(_ player: Player) -> Bool {
        absentPlayerIDs.contains(player.id)
    }

    nonisolated func activePlayers(from players: [Player]) -> [Player] {
        players.filter { !absentPlayerIDs.contains($0.id) }
    }

    nonisolated func playersWithoutInfield(players: [Player]) -> [Player] {
        activePlayers(from: players).filter { player in
            !innings.contains(where: { $0.position(for: player)?.isInfield == true })
        }
    }

    nonisolated func playersWithoutOutfield(players: [Player]) -> [Player] {
        activePlayers(from: players).filter { player in
            !innings.contains(where: { $0.position(for: player)?.isOutfield == true })
        }
    }

    nonisolated func duplicatePositionErrors(inning: Int) -> [FieldPosition] {
        let assignment = innings[inning]
        let fieldAssignments = assignment.assignments.values.filter { !$0.isBench && !$0.isAbsent }
        var seen = Set<FieldPosition>()
        var duplicates = Set<FieldPosition>()
        for pos in fieldAssignments {
            if seen.contains(pos) { duplicates.insert(pos) }
            seen.insert(pos)
        }
        return Array(duplicates)
    }

    nonisolated func openPositions(inning: Int, players: [Player]) -> [FieldPosition] {
        let active = activePlayers(from: players)
        guard !active.isEmpty else { return [] }
        let assignment = innings[inning]
        // ABS counts as "filled" for that slot — it's intentional, not an open position
        let filledPositions = Set(assignment.assignments.values.filter { !$0.isAbsent })
        return FieldPosition.fieldPositions.filter { !filledPositions.contains($0) }
    }

    nonisolated func hasConsecutiveBench(player: Player, assigningBenchToInning inningIndex: Int) -> Bool {
        if inningIndex > 0 && innings[inningIndex - 1].position(for: player) == .bench { return true }
        if inningIndex < Lineup.inningCount - 1 && innings[inningIndex + 1].position(for: player) == .bench { return true }
        return false
    }

    /// True if the player is already assigned to bench in two adjacent innings anywhere
    /// in the lineup. Observational — checks existing assignments. Distinct from
    /// hasConsecutiveBench(player:assigningBenchToInning:), which is predictive
    /// ("would assigning bench here create a back-to-back").
    nonisolated func hasBackToBackBench(player: Player) -> Bool {
        (0..<Lineup.inningCount - 1).contains { i in
            innings[i].position(for: player) == .bench &&
            innings[i + 1].position(for: player) == .bench
        }
    }

    /// All active (non-absent) players currently in a back-to-back bench situation.
    /// Used by all game-wide fair play warning surfaces.
    nonisolated func playersWithBackToBackBench(from players: [Player]) -> [Player] {
        activePlayers(from: players).filter { hasBackToBackBench(player: $0) }
    }

    /// True when the active lineup is finalized AND its game date is before today.
    /// Used by the archive nudge in ContentView and the History tab's
    /// "ready to archive" empty-state branch in GameLogsView. Centralized so
    /// both surfaces stay in lock-step if the rule ever changes (e.g., grace
    /// period for late-night games).
    nonisolated var isPastAndFinalized: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let gameDay = Calendar.current.startOfDay(for: gameDate)
        return status == .finalized && gameDay < today
    }

    /// Returns active (non-absent) players who have fewer than 4 fielding innings assigned
    /// across all 7 innings. Only fires when all 7 innings are fully planned (i.e., every
    /// active player has an assignment in every inning). Absent-position innings are exempt
    /// from the minimum — they don't count for or against the player's fielding total.
    /// Players who have any innings marked ABS are fully exempt from this rule.
    nonisolated func playersUnderFieldingMinimum(players: [Player], minimumInnings: Int = 4) -> [Player] {
        let active = activePlayers(from: players)
        guard !active.isEmpty else { return [] }

        return active.filter { player in
            // Players with any ABS inning are exempt from the 4-inning minimum
            let hasAbsentInning = innings.contains { $0.position(for: player)?.isAbsent == true }
            if hasAbsentInning { return false }

            let fieldingCount = innings.filter { inning in
                guard let pos = inning.position(for: player) else { return false }
                return !pos.isNonFielding
            }.count
            return fieldingCount < minimumInnings
        }
    }

    nonisolated func orderedPlayers(from players: [Player]) -> [Player] {
        battingOrder
            .filter { !absentPlayerIDs.contains($0) }
            .compactMap { id in players.first(where: { $0.id == id }) }
    }

    /// Active players in batting-order sequence, falling back to active players in
    /// roster order when no batting order is set. Used by the Positions tab and
    /// summary grid so they never render empty after a coach adds players but
    /// before they've built a batting order.
    nonisolated func displayPlayers(from players: [Player]) -> [Player] {
        let active = activePlayers(from: players)
        let ordered = orderedPlayers(from: active)
        return ordered.isEmpty ? active : ordered
    }
}

// MARK: - PlayerSnapshot
// Freezes player identity at archive time so historical logs remain accurate
// even if a player is later renamed or deleted from the active roster.

struct PlayerSnapshot: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var firstName: String
    var lastName: String
    var number: String

    nonisolated var displayName: String { "\(firstName) \(lastName)" }

    init(from player: Player) {
        self.id = player.id
        self.firstName = player.firstName
        self.lastName = player.lastName
        self.number = player.number
    }
}

// MARK: - GameLog
// A fully self-contained snapshot of a completed game.

struct GameLog: Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var gameDate: Date
    var opponent: String
    var inningsPlayed: Int                   // 1–7, confirmed by coach at archive time
    var battingOrder: [UUID]
    var innings: [InningAssignment]          // Always 7 entries stored
    var playerSnapshot: [PlayerSnapshot]     // Roster frozen at archive time
    var archivedAt: Date = Date()

    nonisolated var playedInnings: [InningAssignment] {
        Array(innings.prefix(inningsPlayed))
    }

    nonisolated func snapshot(for id: UUID) -> PlayerSnapshot? {
        playerSnapshot.first { $0.id == id }
    }
}

// MARK: - Season Stats
// Computed client-side before every AI call.

struct PlayerSeasonStats: Codable, Sendable {
    var playerID: UUID
    var playerName: String
    var posCounts: [String: Int]
    var gamesPlayed: Int
    var totalInnings: Int
    var benchInnings: Int
    var neverPlayed: [String]
    var infieldInnings: Int
    var outfieldInnings: Int
    var positionGaps: [String]
    var neverPositionRawValues: [String]
}

struct SeasonStats: Codable, Sendable {
    var players: [PlayerSeasonStats]
    var gameCount: Int
    var dateRange: String
}

// MARK: - Team

struct Team: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "0000FF"
    var players: [Player] = []
    var lineup: Lineup = Lineup()
    var gameLogs: [GameLog] = []
    var createdAt: Date = Date()

    var color: Color {
        get { Color(hex: colorHex) ?? .blue }
        set { colorHex = newValue.toHex() ?? "0000FF" }
    }
}

// MARK: - Store

class LineupStore: ObservableObject {

    // MARK: - Published State
    @Published var teams: [Team] = []
    @Published var activeTeamID: UUID?

    // MARK: - Active Team Accessor
    var activeTeam: Team {
        get {
            teams.first { $0.id == activeTeamID } ?? teams.first ?? Team()
        }
        set {
            if let idx = teams.firstIndex(where: { $0.id == newValue.id }) {
                teams[idx] = newValue
            }
        }
    }

    // MARK: - Passthrough Vars
    // These keep existing views working without changes for now.
    var players: [Player]   { activeTeam.players }
    var lineup: Lineup      { activeTeam.lineup }
    var gameLogs: [GameLog] { activeTeam.gameLogs }
    var teamName: String    { activeTeam.name }
    var teamColor: Color    { activeTeam.color }

    // MARK: - Constants
    private let teamsKey      = "stl_teams"
    private let activeTeamKey = "stl_active_team_id"
    private let maxGameLogs   = 20

    // MARK: - Init
    init() { load() }

    // MARK: - Persistence

    func save() {
        let snapshot = teams
        let activeID = activeTeamID?.uuidString

        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(snapshot) else { return }

            // Write to UserDefaults on main thread
            await MainActor.run {
                UserDefaults.standard.set(data, forKey: "stl_teams")
                if let id = activeID {
                    UserDefaults.standard.set(id, forKey: "stl_active_team_id")
                }
            }

            // Write to iCloud KV store off main thread — synchronize() must
            // not be called on the main thread per Apple documentation.
            let icloud = NSUbiquitousKeyValueStore.default
            if data.count < 800_000 {
                icloud.set(data, forKey: "stl_teams")
                if let id = activeID { icloud.set(id, forKey: "stl_active_team_id") }
                icloud.synchronize()
            } else {
                print("⚠️ Teams blob exceeds iCloud KV safety threshold. Storing locally only.")
            }
        }
    }

    func load() {
        applyStoredData()

        // Register for iCloud change notifications so updates from other
        // devices are applied as soon as they arrive.
        // Guard against duplicate observers on re-load.
        NotificationCenter.default.removeObserver(
            self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidUpdate),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )

        // Request a sync from iCloud in the background. If iCloud data
        // arrives after init (common on first launch on a new device),
        // the didChangeExternallyNotification will fire and applyStoredData()
        // will be called again automatically.
        Task.detached(priority: .utility) {
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// Reads from iCloud KV store (preferred) then UserDefaults (fallback)
    /// and applies the decoded data to the store. Safe to call multiple times.
    ///
    /// SAFETY RULE: if storage contains data but it fails to decode, we return
    /// early without touching `teams`. This prevents a decode failure from
    /// cascading into migrateOrCreateDefaultTeam() which would overwrite iCloud
    /// with an empty team.
    private func applyStoredData() {
        let icloud = NSUbiquitousKeyValueStore.default
        let decoder = JSONDecoder()

        let teamsData = icloud.data(forKey: teamsKey) ?? UserDefaults.standard.data(forKey: teamsKey)

        if let data = teamsData {
            if let decoded = try? decoder.decode([Team].self, from: data) {
                // Happy path — data exists and decoded cleanly.
                teams = decoded
            } else {
                // Data exists but failed to decode (e.g. schema mismatch).
                // DO NOT fall through to migration — that would overwrite iCloud
                // with an empty team. Leave teams as-is and wait for a future
                // successful sync or manual recovery.
                print("⚠️ stl_teams data exists but failed to decode. Aborting load to protect existing data.")
                return
            }
        }
        // If teamsData is nil, fall through to migration — this is a genuine first launch.

        let savedID = icloud.string(forKey: activeTeamKey)
                      ?? UserDefaults.standard.string(forKey: activeTeamKey)
        if let idString = savedID, let uuid = UUID(uuidString: idString) {
            activeTeamID = uuid
        }

        if teams.isEmpty {
            migrateOrCreateDefaultTeam()
        } else if activeTeamID == nil || !teams.contains(where: { $0.id == activeTeamID }) {
            activeTeamID = teams.first?.id
        }

        // If the stored game date is in the past and the lineup is still a draft,
        // reset it to today. A finalized lineup keeps its date so the archive
        // nudge can fire correctly.
        let today = Calendar.current.startOfDay(for: Date())
        let storedDate = Calendar.current.startOfDay(for: activeTeam.lineup.gameDate)
        if storedDate < today && activeTeam.lineup.status == .draft {
            activeTeam.lineup.gameDate = Date()
        }
    }

    @objc private func iCloudDidUpdate(_ notification: Notification) {
        DispatchQueue.main.async { self.applyStoredData() }
    }

    // MARK: - Migration

    private func migrateOrCreateDefaultTeam() {
        let decoder = JSONDecoder()
        var migratedTeam = Team()

        let oldPlayers = UserDefaults.standard.data(forKey: "lineup_builder_players")
            .flatMap { try? decoder.decode([Player].self, from: $0) }
        let oldLineup = UserDefaults.standard.data(forKey: "lineup_builder_lineup")
            .flatMap { try? decoder.decode(Lineup.self, from: $0) }
        let oldLogs = UserDefaults.standard.data(forKey: "lineup_builder_game_logs")
            .flatMap { try? decoder.decode([GameLog].self, from: $0) }
        let oldName = UserDefaults.standard.string(forKey: "lineup_builder_team_name") ?? ""
        let oldColorData = UserDefaults.standard.data(forKey: "lineup_builder_team_color")
        let oldColor = oldColorData
            .flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: $0) }
            .map { Color($0) }

        migratedTeam.players  = oldPlayers ?? []
        migratedTeam.lineup   = oldLineup  ?? Lineup()
        migratedTeam.gameLogs = oldLogs    ?? []
        migratedTeam.name     = oldName
        if let color = oldColor { migratedTeam.color = color }

        teams = [migratedTeam]
        activeTeamID = migratedTeam.id

        // SAFETY: only persist — and only clear old keys — if we actually found
        // legacy data worth migrating. An empty migration result means this is a
        // true first launch. In that case, skip save() here; it will fire naturally
        // when the coach first adds a player or sets their team name. Calling save()
        // on an empty team would write an empty blob to iCloud, potentially
        // overwriting valid data on another device that hasn't synced yet.
        let didMigrate = !migratedTeam.players.isEmpty
                      || !migratedTeam.gameLogs.isEmpty
                      || !migratedTeam.name.isEmpty

        if didMigrate {
            save()
            ["lineup_builder_players", "lineup_builder_lineup",
             "lineup_builder_game_logs", "lineup_builder_team_name",
             "lineup_builder_team_color"].forEach {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }
    }

    // MARK: - Lineup Status

    /// Silently reverts lineup status to .draft if it is currently .finalized.
    /// Called at the top of any mutation that changes positions, batting order,
    /// or game info — so coaches always know Finalized means "no changes since I locked it."
    private func revertToDraftIfFinalized() {
        if activeTeam.lineup.status == .finalized {
            activeTeam.lineup.status = .draft
            Analytics.signal("lineup.reverted_to_draft", parameters: ["trigger": "edit"])
        }
    }

    /// Marks the active lineup as finalized. Soft status only — editing remains possible
    /// and will automatically revert back to draft.
    func finalizeLineup() {
        activeTeam.lineup.status = .finalized
        save()
        Analytics.signal("lineup.finalized")
    }

    /// Reopens a finalized lineup, setting status back to draft.
    func reopenLineup() {
        activeTeam.lineup.status = .draft
        save()
        Analytics.signal("lineup.reopened")
    }

    // MARK: - Game Log Operations

    func archiveCurrentLineup(inningsPlayed: Int) {
        let snapshot = activeTeam.players.map { PlayerSnapshot(from: $0) }

        let log = GameLog(
            gameDate: activeTeam.lineup.gameDate,
            opponent: activeTeam.lineup.opponent,
            inningsPlayed: max(1, min(Lineup.inningCount, inningsPlayed)),
            battingOrder: activeTeam.lineup.battingOrder,
            innings: activeTeam.lineup.innings,
            playerSnapshot: snapshot
        )

        activeTeam.gameLogs.insert(log, at: 0)
        if activeTeam.gameLogs.count > maxGameLogs {
            activeTeam.gameLogs = Array(activeTeam.gameLogs.prefix(maxGameLogs))
        }

        clearPositions()
        save()
    }

    func deleteGameLog(id: UUID) {
        activeTeam.gameLogs.removeAll { $0.id == id }
        save()
    }

    func insertDebugGameLog(_ log: GameLog) {
        activeTeam.gameLogs.insert(log, at: 0)
        if activeTeam.gameLogs.count > maxGameLogs {
            activeTeam.gameLogs = Array(activeTeam.gameLogs.prefix(maxGameLogs))
        }
        save()
    }

    // MARK: - Player Operations

    func addPlayer(_ player: Player) {
        activeTeam.players.append(player)
        // Automatically add to bottom of batting order
        if !activeTeam.lineup.battingOrder.contains(player.id) {
            activeTeam.lineup.battingOrder.append(player.id)
        }
        save()
    }

    func updatePlayer(_ player: Player) {
        if let idx = activeTeam.players.firstIndex(where: { $0.id == player.id }) {
            activeTeam.players[idx] = player
            save()
        }
    }

    func deletePlayer(at offsets: IndexSet) {
        let idsToRemove = offsets.map { activeTeam.players[$0].id }
        activeTeam.players.remove(atOffsets: offsets)
        activeTeam.lineup.battingOrder.removeAll { idsToRemove.contains($0) }
        for i in 0..<activeTeam.lineup.innings.count {
            for id in idsToRemove {
                activeTeam.lineup.innings[i].assignments.removeValue(forKey: id)
            }
        }
        save()
    }

    // MARK: - Lineup Operations

    func assignPosition(player: Player, inning: Int, position: FieldPosition) {
        revertToDraftIfFinalized()
        if !position.isBench,
           let occupant = activeTeam.lineup.innings[inning].player(at: position, in: activeTeam.players),
           occupant.id != player.id {
            activeTeam.lineup.innings[inning].removeAssignment(for: occupant)
        }
        activeTeam.lineup.innings[inning].assign(player: player, position: position)
        save()
    }

    func removeAssignment(player: Player, inning: Int) {
        revertToDraftIfFinalized()
        activeTeam.lineup.innings[inning].removeAssignment(for: player)
        save()
    }

    func clearPositions() {
        revertToDraftIfFinalized()
        activeTeam.lineup.innings = Array(repeating: InningAssignment(), count: Lineup.inningCount)
        save()
    }

    func clearBattingOrder() {
        revertToDraftIfFinalized()
        activeTeam.lineup.battingOrder = []
        save()
    }

    func clearAll() {
        revertToDraftIfFinalized()
        activeTeam.lineup.innings = Array(repeating: InningAssignment(), count: Lineup.inningCount)
        activeTeam.lineup.battingOrder = []
        save()
    }

    func clearAllPlayers() {
        activeTeam.players = []
        activeTeam.lineup = Lineup()
        save()
    }

    // MARK: - Lineup Field Helpers (called from LineupView)

    func updateGameDate(_ date: Date) {
        revertToDraftIfFinalized()
        activeTeam.lineup.gameDate = date
        save()
    }

    func updateOpponent(_ opponent: String) {
        revertToDraftIfFinalized()
        activeTeam.lineup.opponent = opponent
        save()
    }

    func moveBattingOrder(from: IndexSet, to: Int) {
        revertToDraftIfFinalized()
        activeTeam.lineup.battingOrder.move(fromOffsets: from, toOffset: to)
        save()
    }

    func addToBattingOrder(player: Player) {
        revertToDraftIfFinalized()
        activeTeam.lineup.battingOrder.append(player.id)
        save()
    }

    func toggleAbsent(player: Player) {
        revertToDraftIfFinalized()
        let wasAbsent = activeTeam.lineup.isAbsent(player)
        activeTeam.lineup.toggleAbsent(player: player)
        // If player just became available, add to bottom of batting order
        if wasAbsent && !activeTeam.lineup.isAbsent(player) {
            if !activeTeam.lineup.battingOrder.contains(player.id) {
                activeTeam.lineup.battingOrder.append(player.id)
            }
        }
        save()
    }

    // MARK: - Team Name / Color (called from PlayersView)

    func updateTeamName(_ name: String) {
        activeTeam.name = name
        save()
    }

    func updateTeamColor(_ color: Color) {
        activeTeam.color = color
        save()
    }

    // MARK: - Team Management

    func addTeam(name: String, color: Color = .blue) {
        var newTeam = Team()
        newTeam.name = name
        newTeam.color = color
        teams.append(newTeam)
        activeTeamID = newTeam.id
        Analytics.signal("team.created", parameters: ["teamCount": "\(teams.count)"])
        save()
    }

    func deleteTeam(id: UUID) {
        guard teams.count > 1 else { return }
        teams.removeAll { $0.id == id }
        if activeTeamID == id {
            activeTeamID = teams.first?.id
        }
        Analytics.signal("team.deleted", parameters: ["remainingTeams": "\(teams.count)"])
        save()
    }

    func switchTeam(to id: UUID) {
        guard teams.contains(where: { $0.id == id }) else { return }
        activeTeamID = id
        Analytics.signal("team.switched", parameters: ["teamCount": "\(teams.count)"])
        save()
    }
}

// MARK: - Color Hex Helpers

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized
        guard hexSanitized.count == 6, let intVal = UInt64(hexSanitized, radix: 16) else { return nil }
        let r = Double((intVal & 0xFF0000) >> 16) / 255.0
        let g = Double((intVal & 0x00FF00) >> 8) / 255.0
        let b = Double(intVal & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

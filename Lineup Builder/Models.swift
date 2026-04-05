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

// MARK: - Player

struct Player: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var firstName: String
    var lastName: String
    var number: String

    nonisolated var displayName: String { "\(firstName) \(lastName)" }
    nonisolated var displayNameWithNumber: String {
        number.isEmpty ? displayName : "#\(number) \(firstName) \(lastName)"
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

// MARK: - Lineup

struct Lineup: Codable, Sendable {
    var gameDate: Date = Date()
    var opponent: String = ""
    var battingOrder: [UUID] = []
    var innings: [InningAssignment] = Array(repeating: InningAssignment(), count: 7)
    var absentPlayerIDs: Set<UUID> = []

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
        if inningIndex < 6 && innings[inningIndex + 1].position(for: player) == .bench { return true }
        return false
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
    var posCounts: [String: Int]       // FieldPosition.rawValue → inning count
    var gamesPlayed: Int
    var totalInnings: Int
    var benchInnings: Int
    var neverPlayed: [String]          // Positions with count == 0
    var infieldInnings: Int
    var outfieldInnings: Int
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

            await MainActor.run {
                UserDefaults.standard.set(data, forKey: "stl_teams")
                if let id = activeID {
                    UserDefaults.standard.set(id, forKey: "stl_active_team_id")
                }

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
    }

    func load() {
        NSUbiquitousKeyValueStore.default.synchronize()
        let icloud = NSUbiquitousKeyValueStore.default
        let decoder = JSONDecoder()

        let teamsData = icloud.data(forKey: teamsKey) ?? UserDefaults.standard.data(forKey: teamsKey)
        if let data = teamsData, let decoded = try? decoder.decode([Team].self, from: data) {
            teams = decoded
        }

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidUpdate),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
    }

    @objc private func iCloudDidUpdate(_ notification: Notification) {
        DispatchQueue.main.async { self.load() }
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
        save()

        ["lineup_builder_players", "lineup_builder_lineup",
         "lineup_builder_game_logs", "lineup_builder_team_name",
         "lineup_builder_team_color"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    // MARK: - Game Log Operations

    func archiveCurrentLineup(inningsPlayed: Int) {
        let snapshot = activeTeam.players.map { PlayerSnapshot(from: $0) }

        let log = GameLog(
            gameDate: activeTeam.lineup.gameDate,
            opponent: activeTeam.lineup.opponent,
            inningsPlayed: max(1, min(7, inningsPlayed)),
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

    // MARK: - Player Operations

    func addPlayer(_ player: Player) {
        activeTeam.players.append(player)
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
        if !position.isBench,
           let occupant = activeTeam.lineup.innings[inning].player(at: position, in: activeTeam.players),
           occupant.id != player.id {
            activeTeam.lineup.innings[inning].removeAssignment(for: occupant)
        }
        activeTeam.lineup.innings[inning].assign(player: player, position: position)
        save()
    }

    func removeAssignment(player: Player, inning: Int) {
        activeTeam.lineup.innings[inning].removeAssignment(for: player)
        save()
    }

    func clearPositions() {
        activeTeam.lineup.innings = Array(repeating: InningAssignment(), count: 7)
        save()
    }

    func clearBattingOrder() {
        activeTeam.lineup.battingOrder = []
        save()
    }

    func clearAll() {
        activeTeam.lineup.innings = Array(repeating: InningAssignment(), count: 7)
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
        activeTeam.lineup.gameDate = date
        save()
    }

    func updateOpponent(_ opponent: String) {
        activeTeam.lineup.opponent = opponent
        save()
    }

    func moveBattingOrder(from: IndexSet, to: Int) {
        activeTeam.lineup.battingOrder.move(fromOffsets: from, toOffset: to)
        save()
    }

    func addToBattingOrder(player: Player) {
        activeTeam.lineup.battingOrder.append(player.id)
        save()
    }

    func toggleAbsent(player: Player) {
        activeTeam.lineup.toggleAbsent(player: player)
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

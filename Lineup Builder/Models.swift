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

enum FieldPosition: String, CaseIterable, Codable {
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

    var displayName: String {
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
        }
    }

    var isInfield: Bool {
        switch self {
        case .pitcher, .catcher, .firstBase, .secondBase, .thirdBase, .shortstop:
            return true
        default:
            return false
        }
    }

    var isOutfield: Bool {
        switch self {
        case .leftField, .centerField, .rightField:
            return true
        default:
            return false
        }
    }

    var isBench: Bool { self == .bench }

    static var fieldPositions: [FieldPosition] {
        allCases.filter { $0 != .bench }
    }

    static var infieldPositions: [FieldPosition] {
        allCases.filter { $0.isInfield }
    }

    static var outfieldPositions: [FieldPosition] {
        allCases.filter { $0.isOutfield }
    }
}

// MARK: - Player

struct Player: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var firstName: String
    var lastName: String
    var number: String

    var displayName: String { "\(firstName) \(lastName)" }
    var displayNameWithNumber: String {
        number.isEmpty ? displayName : "#\(number) \(firstName) \(lastName)"
    }
}

// MARK: - Inning Assignment

struct InningAssignment: Codable {
    var assignments: [UUID: FieldPosition] = [:]

    mutating func assign(player: Player, position: FieldPosition) {
        assignments[player.id] = position
    }

    mutating func removeAssignment(for player: Player) {
        assignments.removeValue(forKey: player.id)
    }

    func position(for player: Player) -> FieldPosition? {
        assignments[player.id]
    }

    func player(at position: FieldPosition, in players: [Player]) -> Player? {
        guard let pid = assignments.first(where: { $0.value == position })?.key else { return nil }
        return players.first(where: { $0.id == pid })
    }
}

// MARK: - Lineup

struct Lineup: Codable {
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

    func isAbsent(_ player: Player) -> Bool {
        absentPlayerIDs.contains(player.id)
    }

    func activePlayers(from players: [Player]) -> [Player] {
        players.filter { !absentPlayerIDs.contains($0.id) }
    }

    func playersWithoutInfield(players: [Player]) -> [Player] {
        activePlayers(from: players).filter { player in
            !innings.contains(where: { $0.position(for: player)?.isInfield == true })
        }
    }

    func playersWithoutOutfield(players: [Player]) -> [Player] {
        activePlayers(from: players).filter { player in
            !innings.contains(where: { $0.position(for: player)?.isOutfield == true })
        }
    }

    func duplicatePositionErrors(inning: Int) -> [FieldPosition] {
        let assignment = innings[inning]
        let fieldAssignments = assignment.assignments.values.filter { !$0.isBench }
        var seen = Set<FieldPosition>()
        var duplicates = Set<FieldPosition>()
        for pos in fieldAssignments {
            if seen.contains(pos) { duplicates.insert(pos) }
            seen.insert(pos)
        }
        return Array(duplicates)
    }

    func openPositions(inning: Int, players: [Player]) -> [FieldPosition] {
        let active = activePlayers(from: players)
        guard !active.isEmpty else { return [] }
        let assignment = innings[inning]
        let filledPositions = Set(assignment.assignments.values)
        return FieldPosition.fieldPositions.filter { !filledPositions.contains($0) }
    }

    func hasConsecutiveBench(player: Player, assigningBenchToInning inningIndex: Int) -> Bool {
        if inningIndex > 0 && innings[inningIndex - 1].position(for: player) == .bench { return true }
        if inningIndex < 6 && innings[inningIndex + 1].position(for: player) == .bench { return true }
        return false
    }

    func orderedPlayers(from players: [Player]) -> [Player] {
        battingOrder
            .filter { !absentPlayerIDs.contains($0) }
            .compactMap { id in players.first(where: { $0.id == id }) }
    }
}

// MARK: - PlayerSnapshot
// Freezes player identity at archive time so historical logs remain accurate
// even if a player is later renamed or deleted from the active roster.

struct PlayerSnapshot: Identifiable, Codable, Equatable {
    var id: UUID
    var firstName: String
    var lastName: String
    var number: String

    var displayName: String { "\(firstName) \(lastName)" }

    init(from player: Player) {
        self.id = player.id
        self.firstName = player.firstName
        self.lastName = player.lastName
        self.number = player.number
    }
}

// MARK: - GameLog
// A fully self-contained snapshot of a completed game.

struct GameLog: Identifiable, Codable {
    var id: UUID = UUID()
    var gameDate: Date
    var opponent: String
    var inningsPlayed: Int                   // 1–7, confirmed by coach at archive time
    var battingOrder: [UUID]
    var innings: [InningAssignment]          // Always 7 entries stored
    var playerSnapshot: [PlayerSnapshot]     // Roster frozen at archive time
    var archivedAt: Date = Date()

    var playedInnings: [InningAssignment] {
        Array(innings.prefix(inningsPlayed))
    }

    func snapshot(for id: UUID) -> PlayerSnapshot? {
        playerSnapshot.first { $0.id == id }
    }
}

// MARK: - Season Stats
// Computed client-side before every AI call.

struct PlayerSeasonStats: Codable {
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

struct SeasonStats: Codable {
    var players: [PlayerSeasonStats]
    var gameCount: Int
    var dateRange: String
}

// MARK: - Store

class LineupStore: ObservableObject {
    @Published var players: [Player] = []
    @Published var lineup: Lineup = Lineup()
    @Published var gameLogs: [GameLog] = []
    @Published var teamName: String = "" {
        didSet { saveTeamName() }
    }
    @Published var teamColor: Color = .blue {
        didSet { saveTeamColor() }
    }

    private let playersKey    = "lineup_builder_players"
    private let lineupKey     = "lineup_builder_lineup"
    private let teamNameKey   = "lineup_builder_team_name"
    private let teamColorKey  = "lineup_builder_team_color"
    private let gameLogsKey   = "lineup_builder_game_logs"
    private let maxGameLogs   = 20

    // Static versions for use inside Task.detached closures
    private static let staticPlayersKey  = "lineup_builder_players"
    private static let staticLineupKey   = "lineup_builder_lineup"
    private static let staticGameLogsKey = "lineup_builder_game_logs"

    init() {
        load()
    }

    // MARK: - Persistence

    func save() {
        // Capture values to encode — safe to do on main thread
        let playersSnapshot = players
        let lineupSnapshot = lineup

        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()

            let playersData = try? encoder.encode(playersSnapshot)
            let lineupData = try? encoder.encode(lineupSnapshot)

            await MainActor.run {
                if let data = playersData {
                    UserDefaults.standard.set(data, forKey: Self.staticPlayersKey)
                }
                if let data = lineupData {
                    UserDefaults.standard.set(data, forKey: Self.staticLineupKey)
                }

                let icloud = NSUbiquitousKeyValueStore.default
                if let data = playersData { icloud.set(data, forKey: Self.staticPlayersKey) }
                if let data = lineupData  { icloud.set(data, forKey: Self.staticLineupKey) }
                icloud.synchronize()
            }
        }
    }

    private func saveGameLogs() {
        let logsSnapshot = gameLogs

        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(logsSnapshot) else { return }

            await MainActor.run {
                UserDefaults.standard.set(data, forKey: Self.staticGameLogsKey)

                let icloud = NSUbiquitousKeyValueStore.default
                if data.count < 800_000 {
                    icloud.set(data, forKey: Self.staticGameLogsKey)
                    icloud.synchronize()
                } else {
                    print("⚠️ GameLogs: encoded size \(data.count) bytes exceeds iCloud KV safety threshold. Storing locally only.")
                }
            }
        }
    }

    private func saveTeamName() {
        UserDefaults.standard.set(teamName, forKey: teamNameKey)
        NSUbiquitousKeyValueStore.default.set(teamName, forKey: teamNameKey)
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    private func saveTeamColor() {
        let colorData = try? NSKeyedArchiver.archivedData(withRootObject: UIColor(teamColor), requiringSecureCoding: false)
        UserDefaults.standard.set(colorData, forKey: teamColorKey)
        if let data = colorData {
            NSUbiquitousKeyValueStore.default.set(data, forKey: teamColorKey)
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    func load() {
        let decoder = JSONDecoder()

        NSUbiquitousKeyValueStore.default.synchronize()
        let icloud = NSUbiquitousKeyValueStore.default

        let playersData = icloud.data(forKey: playersKey) ?? UserDefaults.standard.data(forKey: playersKey)
        if let data = playersData, let decoded = try? decoder.decode([Player].self, from: data) {
            players = decoded
        }

        let lineupData = icloud.data(forKey: lineupKey) ?? UserDefaults.standard.data(forKey: lineupKey)
        if let data = lineupData, let decoded = try? decoder.decode(Lineup.self, from: data) {
            lineup = decoded
        }

        let logsData = icloud.data(forKey: gameLogsKey) ?? UserDefaults.standard.data(forKey: gameLogsKey)
        if let data = logsData, let decoded = try? decoder.decode([GameLog].self, from: data) {
            gameLogs = decoded
        }

        let savedTeamName = icloud.string(forKey: teamNameKey) ?? UserDefaults.standard.string(forKey: teamNameKey) ?? ""
        teamName = savedTeamName

        let colorData = icloud.data(forKey: teamColorKey) ?? UserDefaults.standard.data(forKey: teamColorKey)
        if let data = colorData,
           let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
            teamColor = Color(uiColor)
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

    // MARK: - Game Log Operations

    /// Archives the current lineup as a GameLog, then clears defensive positions
    /// while preserving the batting order for the next game.
    func archiveCurrentLineup(inningsPlayed: Int) {
        let snapshot = players.map { PlayerSnapshot(from: $0) }

        let log = GameLog(
            gameDate: lineup.gameDate,
            opponent: lineup.opponent,
            inningsPlayed: max(1, min(7, inningsPlayed)),
            battingOrder: lineup.battingOrder,
            innings: lineup.innings,
            playerSnapshot: snapshot
        )

        gameLogs.insert(log, at: 0)

        // Enforce 20-game cap — oldest games are removed automatically
        if gameLogs.count > maxGameLogs {
            gameLogs = Array(gameLogs.prefix(maxGameLogs))
        }

        saveGameLogs()

        // Clear positions only — batting order is preserved per PRD
        clearPositions()
    }

    func deleteGameLog(id: UUID) {
        gameLogs.removeAll { $0.id == id }
        saveGameLogs()
    }

    // MARK: - Player Operations

    func addPlayer(_ player: Player) {
        players.append(player)
        save()
    }

    func updatePlayer(_ player: Player) {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index] = player
            save()
        }
    }

    func deletePlayer(at offsets: IndexSet) {
        let idsToRemove = offsets.map { players[$0].id }
        players.remove(atOffsets: offsets)
        lineup.battingOrder.removeAll { idsToRemove.contains($0) }
        for i in 0..<lineup.innings.count {
            for id in idsToRemove {
                lineup.innings[i].assignments.removeValue(forKey: id)
            }
        }
        save()
    }

    // MARK: - Lineup Clear Options

    func clearPositions() {
        lineup.innings = Array(repeating: InningAssignment(), count: 7)
        save()
    }

    func clearBattingOrder() {
        lineup.battingOrder = []
        save()
    }

    func clearAll() {
        lineup.innings = Array(repeating: InningAssignment(), count: 7)
        lineup.battingOrder = []
        save()
    }

    func clearAllPlayers() {
        players = []
        lineup = Lineup()
        save()
    }
}

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
    case leftCenterField = "LCF"
    case centerField = "CF"
    case rightCenterField = "RCF"
    case rightField = "RF"
    case bench = "Bench"
    case absent = "ABS"

    // Safe decode: unknown raw values (e.g. from a future build decoded by an
    // older one, or vice versa) fall back to bench rather than crashing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FieldPosition(rawValue: raw) ?? .bench
    }

    nonisolated var displayName: String {
        switch self {
        case .pitcher: return "Pitcher"
        case .catcher: return "Catcher"
        case .firstBase: return "1st Base"
        case .secondBase: return "2nd Base"
        case .thirdBase: return "3rd Base"
        case .shortstop: return "Shortstop"
        case .leftField: return "Left Field"
        case .leftCenterField: return "Left Center"
        case .centerField: return "Center Field"
        case .rightCenterField: return "Right Center"
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
        case .leftField, .leftCenterField, .centerField, .rightCenterField, .rightField:
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

// MARK: - League Ruleset

/// The league format a team plays under. Stored on FairPlayConfig.
/// In v2.4 this is informational only — it persists the coach's selection
/// but does not auto-apply rule presets yet. Preset application ships in
/// v2.5 alongside the pitch count engine, which depends on league ruleset.
enum LeagueRuleset: String, Codable, CaseIterable, Sendable {
    case littleLeague = "Little League"
    case calRipken    = "Cal Ripken"
    case babeRuth     = "Babe Ruth"
    case custom       = "Custom"

    nonisolated var displayName: String { rawValue }
}

// MARK: - Pitching Config

/// Age bracket for pitch count rule lookup. Covers all rec-ball divisions up to 16.
/// No bracket above 16 — out of scope for the recreational youth target audience.
enum PitchingAgeBracket: String, Codable, CaseIterable, Sendable {
    case u8  = "7-8"
    case u10 = "9-10"
    case u12 = "11-12"
    case u14 = "13-14"
    case u16 = "15-16"

    nonisolated var displayName: String { rawValue }

    /// Returns the bracket that applies to a given league age, or nil if out of range.
    static func bracket(for age: Int) -> PitchingAgeBracket? {
        switch age {
        case ...8:  return .u8
        case 9...10: return .u10
        case 11...12: return .u12
        case 13...14: return .u14
        case 15...16: return .u16
        default:    return nil
        }
    }
}

/// Rest day thresholds and daily pitch maximum for a single age bracket.
/// Upper tiers are optional — the 7-8 bracket has no 3 or 4 rest day tier.
struct PitchingLimits: Codable, Sendable {
    /// Maximum pitches allowed in a single game for this age group.
    var dailyMax: Int
    /// Minimum pitches thrown that require 1 day of rest. 0 = no threshold at this tier.
    var restDay1Min: Int
    /// Minimum pitches thrown that require 2 days of rest. 0 = no threshold at this tier.
    var restDay2Min: Int
    /// Minimum pitches thrown that require 3 days of rest. nil = tier does not apply.
    var restDay3Min: Int?
    /// Minimum pitches thrown that require 4 days of rest. nil = tier does not apply.
    var restDay4Min: Int?

    /// Returns the number of rest days required for a given pitch count.
    func restDaysRequired(for pitches: Int) -> Int {
        if let min4 = restDay4Min, pitches >= min4 { return 4 }
        if let min3 = restDay3Min, pitches >= min3 { return 3 }
        if pitches >= restDay2Min { return 2 }
        if pitches >= restDay1Min { return 1 }
        return 0
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyMax    = (try? c.decodeIfPresent(Int.self, forKey: .dailyMax))    ?? 85
        restDay1Min = (try? c.decodeIfPresent(Int.self, forKey: .restDay1Min)) ?? 1
        restDay2Min = (try? c.decodeIfPresent(Int.self, forKey: .restDay2Min)) ?? 36
        restDay3Min = try? c.decodeIfPresent(Int.self, forKey: .restDay3Min)
        restDay4Min = try? c.decodeIfPresent(Int.self, forKey: .restDay4Min)
    }

    init(dailyMax: Int, restDay1Min: Int, restDay2Min: Int,
         restDay3Min: Int? = nil, restDay4Min: Int? = nil) {
        self.dailyMax    = dailyMax
        self.restDay1Min = restDay1Min
        self.restDay2Min = restDay2Min
        self.restDay3Min = restDay3Min
        self.restDay4Min = restDay4Min
    }
}

/// How the rolling pitch-count window is measured.
enum RollingWindowType: String, Codable, CaseIterable, Sendable {
    case calendarWeek = "Calendar Week"
    case rolling      = "Rolling 7 Days"

    nonisolated var displayName: String { rawValue }
}

/// Per-team pitching rules. Stored alongside FairPlayConfig on Team.
/// Defaults to disabled so existing teams are unaffected on upgrade.
struct PitchingConfig: Codable, Sendable {

    /// Master toggle. When false the rules engine is bypassed entirely.
    var rulesEnabled: Bool = false

    /// Age-bracket limits. Keyed by bracket. Pre-loaded by applyLittleLeaguePreset().
    var ageLimits: [PitchingAgeBracket: PitchingLimits] = [:]

    /// Whether a rolling pitch-count window cap is enforced.
    var weeklyLimitEnabled: Bool = false

    /// Maximum total pitches allowed in the rolling window period.
    var weeklyLimit: Int = 0

    /// How the rolling window is calculated. Calendar week = Mon-Sun.
    /// Rolling = true 7-day window from any given game date.
    var rollingWindowType: RollingWindowType = .rolling

    /// Duration of the rolling window in days. Not surfaced in UI yet —
    /// UI exposes calendarWeek vs rolling7Days toggle only. Reserved for
    /// a future release when variable window lengths ship.
    var rollingWindowDays: Int = 7

    // MARK: Presets

    /// Seeds ageLimits with the standard Little League pitch count rules.
    /// The coach can edit any value after applying — the preset is a starting point only.
    mutating func applyLittleLeaguePreset() {
        ageLimits = [
            .u8:  PitchingLimits(dailyMax: 50, restDay1Min: 21, restDay2Min: 36),
            .u10: PitchingLimits(dailyMax: 75, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66),
            .u12: PitchingLimits(dailyMax: 85, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66),
            .u14: PitchingLimits(dailyMax: 95, restDay1Min: 21, restDay2Min: 36, restDay3Min: 51, restDay4Min: 66),
            .u16: PitchingLimits(dailyMax: 95, restDay1Min: 31, restDay2Min: 46, restDay3Min: 61, restDay4Min: 76)
        ]
    }

    // MARK: Safe decode

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rulesEnabled       = (try? c.decodeIfPresent(Bool.self,                              forKey: .rulesEnabled))       ?? false
        ageLimits          = (try? c.decodeIfPresent([PitchingAgeBracket: PitchingLimits].self, forKey: .ageLimits))       ?? [:]
        weeklyLimitEnabled = (try? c.decodeIfPresent(Bool.self,                              forKey: .weeklyLimitEnabled)) ?? false
        weeklyLimit        = (try? c.decodeIfPresent(Int.self,                               forKey: .weeklyLimit))        ?? 0
        rollingWindowType  = (try? c.decodeIfPresent(RollingWindowType.self,                 forKey: .rollingWindowType))  ?? .rolling
        rollingWindowDays  = (try? c.decodeIfPresent(Int.self,                               forKey: .rollingWindowDays))  ?? 7
    }

    init(
        rulesEnabled: Bool = false,
        ageLimits: [PitchingAgeBracket: PitchingLimits] = [:],
        weeklyLimitEnabled: Bool = false,
        weeklyLimit: Int = 0,
        rollingWindowType: RollingWindowType = .rolling,
        rollingWindowDays: Int = 7
    ) {
        self.rulesEnabled       = rulesEnabled
        self.ageLimits          = ageLimits
        self.weeklyLimitEnabled = weeklyLimitEnabled
        self.weeklyLimit        = weeklyLimit
        self.rollingWindowType  = rollingWindowType
        self.rollingWindowDays  = rollingWindowDays
    }
}

// MARK: - Fair Play Config

/// Per-team fair play rules. All defaults mirror the rules that were previously
/// hardcoded, so existing teams decoded without this key get identical behavior.
/// Lives on Team — a coach with a rec team and a travel team gets different rules for each.
struct FairPlayConfig: Codable, Sendable {

    // MARK: Position restrictions
    /// When true, Pitcher is removed from the valid position pool entirely.
    var noPitcher: Bool = false
    /// When true, Catcher is removed from the valid position pool entirely.
    var noCatcher: Bool = false
    /// Number of outfielders on the field. 3 = standard (LF/CF/RF).
    /// 4 = adds LCF and RCF; CF is hidden from the grid when this is 4.
    var outfielderCount: Int = 3

    // MARK: Bench rules
    /// Prevents a player from sitting bench in two consecutive innings.
    /// Was previously hardcoded on; now a toggle.
    var noConsecutiveBench: Bool = true
    /// Prevents a player from being assigned the same non-bench position
    /// in back-to-back innings.
    var noConsecutivePosition: Bool = false
    /// Don't sit any player twice before everyone has sat once.
    var equalBenchTime: Bool = false

    // MARK: Fielding minimums
    /// Minimum fielding innings each active player must play.
    /// Was previously hardcoded at 4.
    var minimumFieldingInnings: Int = 4
    /// Minimum infield innings each active player must play.
    /// Was previously hardcoded at 1.
    var minimumInfieldInnings: Int = 1
    /// Minimum outfield innings each active player must play.
    /// Was previously hardcoded at 1.
    var minimumOutfieldInnings: Int = 1

    // MARK: Battery restrictions
    /// If a player caught this many or more innings in the current game,
    /// they cannot pitch. 0 = rule disabled.
    var catcherToPitcherThreshold: Int = 0
    /// If a player pitched this many or more innings in the current game,
    /// they cannot catch. 0 = rule disabled.
    var pitcherToCatcherThreshold: Int = 0

    // MARK: League
    /// The league format this team plays under. Informational in v2.4;
    /// used for rule presets in v2.5.
    var leagueRuleset: LeagueRuleset = .custom

    // Safe decode: any missing key falls back to its default so adding
    // new fields in future versions never breaks existing saved configs.
    init(
        noPitcher: Bool = false,
        noCatcher: Bool = false,
        outfielderCount: Int = 3,
        noConsecutiveBench: Bool = true,
        noConsecutivePosition: Bool = false,
        equalBenchTime: Bool = false,
        minimumFieldingInnings: Int = 4,
        minimumInfieldInnings: Int = 1,
        minimumOutfieldInnings: Int = 1,
        catcherToPitcherThreshold: Int = 0,
        pitcherToCatcherThreshold: Int = 0,
        leagueRuleset: LeagueRuleset = .custom
    ) {
        self.noPitcher = noPitcher
        self.noCatcher = noCatcher
        self.outfielderCount = outfielderCount
        self.noConsecutiveBench = noConsecutiveBench
        self.noConsecutivePosition = noConsecutivePosition
        self.equalBenchTime = equalBenchTime
        self.minimumFieldingInnings = minimumFieldingInnings
        self.minimumInfieldInnings = minimumInfieldInnings
        self.minimumOutfieldInnings = minimumOutfieldInnings
        self.catcherToPitcherThreshold = catcherToPitcherThreshold
        self.pitcherToCatcherThreshold = pitcherToCatcherThreshold
        self.leagueRuleset = leagueRuleset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noPitcher                  = (try? c.decodeIfPresent(Bool.self,           forKey: .noPitcher))                  ?? false
        noCatcher                  = (try? c.decodeIfPresent(Bool.self,           forKey: .noCatcher))                  ?? false
        outfielderCount            = (try? c.decodeIfPresent(Int.self,            forKey: .outfielderCount))            ?? 3
        noConsecutiveBench         = (try? c.decodeIfPresent(Bool.self,           forKey: .noConsecutiveBench))         ?? true
        noConsecutivePosition      = (try? c.decodeIfPresent(Bool.self,           forKey: .noConsecutivePosition))      ?? false
        equalBenchTime             = (try? c.decodeIfPresent(Bool.self,           forKey: .equalBenchTime))             ?? false
        minimumFieldingInnings     = (try? c.decodeIfPresent(Int.self,            forKey: .minimumFieldingInnings))     ?? 4
        minimumInfieldInnings      = (try? c.decodeIfPresent(Int.self,            forKey: .minimumInfieldInnings))      ?? 1
        minimumOutfieldInnings     = (try? c.decodeIfPresent(Int.self,            forKey: .minimumOutfieldInnings))     ?? 1
        catcherToPitcherThreshold  = (try? c.decodeIfPresent(Int.self,            forKey: .catcherToPitcherThreshold))  ?? 0
        pitcherToCatcherThreshold  = (try? c.decodeIfPresent(Int.self,            forKey: .pitcherToCatcherThreshold))  ?? 0
        leagueRuleset              = (try? c.decodeIfPresent(LeagueRuleset.self,  forKey: .leagueRuleset))              ?? .custom
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
    /// Default inning count used when constructing a Lineup without team context
    /// (e.g. the default `Lineup()` initializer or decode fallback). Per-team
    /// inning count lives on `Team.gameInningCount`. The runtime source of truth
    /// for any active lineup is its `innings.count` array length, so views and
    /// game logic should iterate `innings.count` rather than this constant.
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

    /// Returns the field positions that are active under the given FairPlayConfig.
    /// Removes Pitcher/Catcher when toggled off, swaps CF for LCF+RCF when 4 OFs are set.
    /// Used by the position grid and picker so they only show relevant positions.
    nonisolated func activeFieldPositions(config: FairPlayConfig) -> [FieldPosition] {
        var positions = FieldPosition.fieldPositions
        if config.noPitcher { positions.removeAll { $0 == .pitcher } }
        if config.noCatcher { positions.removeAll { $0 == .catcher } }
        if config.outfielderCount == 4 {
            positions.removeAll { $0 == .centerField }
        } else {
            positions.removeAll { $0 == .leftCenterField || $0 == .rightCenterField }
        }
        return positions
    }

    /// Config-aware open positions — only reports slots that exist under the current ruleset.
    nonisolated func openPositions(inning: Int, players: [Player], config: FairPlayConfig) -> [FieldPosition] {
        let active = activePlayers(from: players)
        guard !active.isEmpty else { return [] }
        let assignment = innings[inning]
        let filledPositions = Set(assignment.assignments.values.filter { !$0.isAbsent })
        return activeFieldPositions(config: config).filter { !filledPositions.contains($0) }
    }

    /// Players who have caught at least `threshold` innings in this lineup AND
    /// are also assigned Pitcher in any inning. Returns [] when threshold == 0 (rule off).
    nonisolated func playersViolatingCatcherToPitcher(players: [Player], threshold: Int) -> [Player] {
        guard threshold > 0 else { return [] }
        return activePlayers(from: players).filter { player in
            let catcherInnings = innings.filter { $0.position(for: player) == .catcher }.count
            let hasPitcherInning = innings.contains { $0.position(for: player) == .pitcher }
            return catcherInnings >= threshold && hasPitcherInning
        }
    }

    /// Players who have pitched at least `threshold` innings in this lineup AND
    /// are also assigned Catcher in any inning. Returns [] when threshold == 0 (rule off).
    nonisolated func playersViolatingPitcherToCatcher(players: [Player], threshold: Int) -> [Player] {
        guard threshold > 0 else { return [] }
        return activePlayers(from: players).filter { player in
            let pitcherInnings = innings.filter { $0.position(for: player) == .pitcher }.count
            let hasCatcherInning = innings.contains { $0.position(for: player) == .catcher }
            return pitcherInnings >= threshold && hasCatcherInning
        }
    }

    nonisolated func hasConsecutiveBench(player: Player, assigningBenchToInning inningIndex: Int) -> Bool {
        if inningIndex > 0 && innings[inningIndex - 1].position(for: player) == .bench { return true }
        if inningIndex < innings.count - 1 && innings[inningIndex + 1].position(for: player) == .bench { return true }
        return false
    }

    /// True if the player is already assigned to bench in two adjacent innings anywhere
    /// in the lineup. Observational — checks existing assignments. Distinct from
    /// hasConsecutiveBench(player:assigningBenchToInning:), which is predictive
    /// ("would assigning bench here create a back-to-back").
    nonisolated func hasBackToBackBench(player: Player) -> Bool {
        (0..<innings.count - 1).contains { i in
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

    /// Returns active (non-absent) players who have fewer than `minimumInnings` fielding
    /// innings assigned across all innings in the lineup. Only fires when every inning is
    /// fully planned (i.e., every active player has an assignment in every inning).
    /// Absent-position innings are exempt from the minimum — they don't count for or
    /// against the player's fielding total. Players who have any innings marked ABS are
    /// fully exempt from this rule.
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
    /// Pitch counts entered or imported at archive time. Keyed by player UUID string.
    /// Optional per log — games archived before v2.5 will have nil/empty here.
    var pitchCounts: [String: Int] = [:]

    nonisolated var playedInnings: [InningAssignment] {
        Array(innings.prefix(inningsPlayed))
    }

    nonisolated func snapshot(for id: UUID) -> PlayerSnapshot? {
        playerSnapshot.first { $0.id == id }
    }

    // Custom decode: pitchCounts is new in v2.5 — older GameLog blobs won't include it.
    // All other fields are load-bearing; propagate failures so corrupt logs surface clearly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = (try? c.decode(UUID.self,             forKey: .id))             ?? UUID()
        gameDate       = try c.decode(Date.self,               forKey: .gameDate)
        opponent       = try c.decode(String.self,             forKey: .opponent)
        inningsPlayed  = try c.decode(Int.self,                forKey: .inningsPlayed)
        battingOrder   = try c.decode([UUID].self,             forKey: .battingOrder)
        innings        = try c.decode([InningAssignment].self, forKey: .innings)
        playerSnapshot = try c.decode([PlayerSnapshot].self,   forKey: .playerSnapshot)
        archivedAt     = (try? c.decode(Date.self,             forKey: .archivedAt))     ?? Date()
        pitchCounts    = (try? c.decodeIfPresent([String: Int].self, forKey: .pitchCounts)) ?? [:]
    }

    init(id: UUID = UUID(), gameDate: Date, opponent: String, inningsPlayed: Int,
         battingOrder: [UUID], innings: [InningAssignment], playerSnapshot: [PlayerSnapshot],
         archivedAt: Date = Date(), pitchCounts: [String: Int] = [:]) {
        self.id             = id
        self.gameDate       = gameDate
        self.opponent       = opponent
        self.inningsPlayed  = inningsPlayed
        self.battingOrder   = battingOrder
        self.innings        = innings
        self.playerSnapshot = playerSnapshot
        self.archivedAt     = archivedAt
        self.pitchCounts    = pitchCounts
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

// MARK: - Scheduled Game

/// A game imported from an iCal (.ics) subscription. Stored per-team.
/// The icalUID is the stable dedup key — re-importing the same calendar
/// updates existing records rather than creating duplicates.
struct ScheduledGame: Identifiable, Codable {
    var id: UUID = UUID()
    /// Stable unique ID from the VEVENT UID field. Used for dedup on re-sync.
    var icalUID: String
    var date: Date
    /// Parsed opponent name. Nil if SUMMARY didn't match any known pattern.
    var opponent: String?
    /// Raw LOCATION field value from the VEVENT.
    var location: String?
    /// Original SUMMARY field value, preserved for display if parsing fails.
    var rawSummary: String
    /// True if the VEVENT had STATUS:CANCELLED. Shown with strikethrough.
    var isCancelled: Bool = false
    /// When this record was last updated from a sync.
    var lastSyncedAt: Date = Date()
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
    /// Per-team game length. Common values: 5 (younger divisions), 6 (Cal Ripken Minor),
    /// 7 (Little League Majors+). Drives the size of new lineups created via clearAll(),
    /// clearPositions(), and the inningsPlayed clamp at archive time. Existing archived
    /// games keep their original inning count baked into the GameLog. Migrates to 7
    /// for any team decoded without this key.
    var gameInningCount: Int = 7
    /// Games imported from an iCal subscription. Sorted by date ascending.
    /// Re-syncing diffs by icalUID — existing records are updated, new ones appended.
    var scheduledGames: [ScheduledGame] = []
    /// The webcal:// or https:// URL the coach used to subscribe. Stored so
    /// "Sync" can re-fetch without asking for the URL again.
    var calendarSubscriptionURL: String? = nil
    /// Per-team fair play rule configuration. Defaults match previously hardcoded
    /// behavior so existing teams get identical validation after upgrading.
    var fairPlayConfig: FairPlayConfig = FairPlayConfig()
    /// Per-team pitching rules configuration. Disabled by default — existing teams
    /// are unaffected until a coach explicitly enables pitching rules.
    var pitchingConfig: PitchingConfig = PitchingConfig()

    var color: Color {
        get { Color(hex: colorHex) ?? .blue }
        set { colorHex = newValue.toHex() ?? "0000FF" }
    }

    // Explicit memberwise init — required because defining init(from:) below
    // suppresses the compiler-synthesized memberwise initializer.
    init(
        id: UUID = UUID(),
        name: String = "",
        colorHex: String = "0000FF",
        players: [Player] = [],
        lineup: Lineup = Lineup(),
        gameLogs: [GameLog] = [],
        createdAt: Date = Date(),
        gameInningCount: Int = 7,
        scheduledGames: [ScheduledGame] = [],
        calendarSubscriptionURL: String? = nil,
        fairPlayConfig: FairPlayConfig = FairPlayConfig(),
        pitchingConfig: PitchingConfig = PitchingConfig()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.players = players
        self.lineup = lineup
        self.gameLogs = gameLogs
        self.createdAt = createdAt
        self.gameInningCount = gameInningCount
        self.scheduledGames = scheduledGames
        self.calendarSubscriptionURL = calendarSubscriptionURL
        self.fairPlayConfig = fairPlayConfig
        self.pitchingConfig = pitchingConfig
    }

    // Custom decode: gameInningCount is new in v2.3 — older Team blobs won't
    // include it. Default to 7 so existing teams keep working unchanged.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                       = (try? c.decode(UUID.self,            forKey: .id))                       ?? UUID()
        name                     = (try? c.decode(String.self,          forKey: .name))                     ?? ""
        colorHex                 = (try? c.decode(String.self,          forKey: .colorHex))                 ?? "0000FF"
        players                  = (try? c.decode([Player].self,        forKey: .players))                  ?? []
        lineup                   = (try? c.decode(Lineup.self,          forKey: .lineup))                   ?? Lineup()
        gameLogs                 = (try? c.decode([GameLog].self,       forKey: .gameLogs))                 ?? []
        createdAt                = (try? c.decode(Date.self,            forKey: .createdAt))                ?? Date()
        gameInningCount          = (try? c.decode(Int.self,             forKey: .gameInningCount))          ?? 7
        scheduledGames           = (try? c.decode([ScheduledGame].self, forKey: .scheduledGames))           ?? []
        calendarSubscriptionURL  = (try? c.decode(String.self,         forKey: .calendarSubscriptionURL))
        // fairPlayConfig is new in v2.4 — older Team blobs won't include it.
        // Default constructs with safe values that match previous hardcoded behavior.
        fairPlayConfig           = (try? c.decode(FairPlayConfig.self,  forKey: .fairPlayConfig))           ?? FairPlayConfig()
        // pitchingConfig is new in v2.5 — older Team blobs won't include it.
        // Default to disabled so existing teams are unaffected on upgrade.
        pitchingConfig           = (try? c.decode(PitchingConfig.self,  forKey: .pitchingConfig))           ?? PitchingConfig()
    }
}

// MARK: - Store

/// State machine for the share-sheet roster import flow. Owned by LineupStore.
enum PendingRosterImport {
    case none
    case awaitingTeamSelection(filename: String, players: [RosterImporter.ImportedPlayer])
    case awaitingNewTeamCreation(filename: String, players: [RosterImporter.ImportedPlayer])
    case readyForPreview(filename: String, players: [RosterImporter.ImportedPlayer], targetTeamID: UUID)

    var isActive: Bool {
        if case .none = self { return false }
        return true
    }
}

class LineupStore: ObservableObject {

    // MARK: - Published State
    @Published var teams: [Team] = []
    @Published var activeTeamID: UUID?
    /// Drives the share-sheet roster import flow. Set when the app receives a
    /// CSV/.stlroster file via .onOpenURL. ContentView observes this and presents
    /// the team-picker and preview chain.
    @Published var pendingRosterImport: PendingRosterImport = .none

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
    var players: [Player]                { activeTeam.players }
    var lineup: Lineup                   { activeTeam.lineup }
    var gameLogs: [GameLog]              { activeTeam.gameLogs }
    var teamName: String                 { activeTeam.name }
    var teamColor: Color                 { activeTeam.color }
    var gameInningCount: Int             { activeTeam.gameInningCount }
    var scheduledGames: [ScheduledGame]  { activeTeam.scheduledGames }
    var calendarSubscriptionURL: String? { activeTeam.calendarSubscriptionURL }
    var fairPlayConfig: FairPlayConfig   { activeTeam.fairPlayConfig }
    var pitchingConfig: PitchingConfig   { activeTeam.pitchingConfig }

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
                // Sort each team's game logs by gameDate descending — corrects any
                // logs stored out of order due to the archive-order bug.
                teams = decoded.map { team in
                    var t = team
                    t.gameLogs = t.gameLogs.sorted { $0.gameDate > $1.gameDate }
                    return t
                }
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

    @discardableResult
    func archiveCurrentLineup(inningsPlayed: Int) -> UUID {
        let snapshot = activeTeam.players.map { PlayerSnapshot(from: $0) }

        let log = GameLog(
            gameDate: activeTeam.lineup.gameDate,
            opponent: activeTeam.lineup.opponent,
            inningsPlayed: max(1, min(activeTeam.gameInningCount, inningsPlayed)),
            battingOrder: activeTeam.lineup.battingOrder,
            innings: activeTeam.lineup.innings,
            playerSnapshot: snapshot
        )

        activeTeam.gameLogs.append(log)
        activeTeam.gameLogs.sort { $0.gameDate > $1.gameDate }
        if activeTeam.gameLogs.count > maxGameLogs {
            activeTeam.gameLogs = Array(activeTeam.gameLogs.prefix(maxGameLogs))
        }

        clearPositions()
        save()
        return log.id
    }

    func deleteGameLog(id: UUID) {
        activeTeam.gameLogs.removeAll { $0.id == id }
        save()
    }

    /// Replaces the entire pitchCounts dictionary on a specific game log.
    /// Used by GameLogDetailView when the coach edits pitch counts retroactively.
    /// Replacing the whole dict (rather than merging) ensures removed pitchers are cleared.
    func replacePitchCounts(_ counts: [String: Int], for logID: UUID) {
        guard let idx = activeTeam.gameLogs.firstIndex(where: { $0.id == logID }) else { return }
        activeTeam.gameLogs[idx].pitchCounts = counts
        save()
    }

    func insertDebugGameLog(_ log: GameLog) {
        activeTeam.gameLogs.append(log)
        activeTeam.gameLogs.sort { $0.gameDate > $1.gameDate }
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

    /// Bulk-add players in a single save. Used by roster import to avoid
    /// triggering an iCloud KV write per player. Each new player is appended
    /// to the bottom of the batting order in the same order they appear here.
    func addPlayers(_ players: [Player]) {
        guard !players.isEmpty else { return }
        activeTeam.players.append(contentsOf: players)
        for player in players where !activeTeam.lineup.battingOrder.contains(player.id) {
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
        activeTeam.lineup.innings = Array(repeating: InningAssignment(), count: activeTeam.gameInningCount)
        save()
    }

    func clearBattingOrder() {
        revertToDraftIfFinalized()
        activeTeam.lineup.battingOrder = []
        save()
    }

    func clearAll() {
        revertToDraftIfFinalized()
        activeTeam.lineup.innings = Array(repeating: InningAssignment(), count: activeTeam.gameInningCount)
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

    /// Updates the fair play config for a specific team. Scoped to teamID so
    /// FairPlayRulesView can write to a team other than activeTeam if needed.
    func updateFairPlayConfig(_ config: FairPlayConfig, for teamID: UUID) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx].fairPlayConfig = config
        Analytics.signal("fairplay.config.updated", parameters: [
            "noPitcher": "\(config.noPitcher)",
            "noCatcher": "\(config.noCatcher)",
            "outfielderCount": "\(config.outfielderCount)",
            "minimumFieldingInnings": "\(config.minimumFieldingInnings)"
        ])
        save()
    }

    /// Updates the pitching config for a specific team. Scoped to teamID so
    /// PitchingRulesView can write to a team other than activeTeam if needed.
    func updatePitchingConfig(_ config: PitchingConfig, for teamID: UUID) {
        guard let idx = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[idx].pitchingConfig = config
        Analytics.signal("pitching.config.updated", parameters: [
            "rulesEnabled": "\(config.rulesEnabled)",
            "weeklyLimitEnabled": "\(config.weeklyLimitEnabled)",
            "rollingWindowType": config.rollingWindowType.rawValue
        ])
        save()
    }

    /// Saves pitch counts to a specific game log. Merges with any existing counts
    /// so that a GC import and manual entry don't overwrite each other if called
    /// in sequence — last write per player ID wins.
    func savePitchCounts(_ counts: [String: Int], for gameLogID: UUID) {
        guard let teamIdx = teams.firstIndex(where: { $0.id == activeTeamID }),
              let logIdx = teams[teamIdx].gameLogs.firstIndex(where: { $0.id == gameLogID }) else { return }
        for (key, value) in counts {
            teams[teamIdx].gameLogs[logIdx].pitchCounts[key] = value
        }
        Analytics.signal("pitchcounts.saved", parameters: [
            "pitcherCount": "\(counts.count)"
        ])
        save()
    }

    /// Updates a team's game inning count and resizes its lineup's innings array
    /// to match. If teamID is nil, defaults to the active team.
    /// If the new count is smaller, trailing innings are dropped. If larger,
    /// empty innings are appended. Past archived games are not affected.
    func updateGameInningCount(_ newCount: Int, for teamID: UUID? = nil) {
        let clamped = max(1, min(9, newCount))
        let targetID = teamID ?? activeTeamID
        guard let targetID = targetID,
              let idx = teams.firstIndex(where: { $0.id == targetID }) else { return }
        guard clamped != teams[idx].gameInningCount else { return }

        teams[idx].gameInningCount = clamped

        let currentInnings = teams[idx].lineup.innings.count
        if clamped < currentInnings {
            teams[idx].lineup.innings = Array(teams[idx].lineup.innings.prefix(clamped))
            // Revert status directly on teams[idx] — avoids re-entrancy through
            // the activeTeam computed property setter while teams is being mutated.
            if teams[idx].lineup.status == .finalized {
                teams[idx].lineup.status = .draft
                Analytics.signal("lineup.reverted_to_draft", parameters: ["trigger": "inningCountReduced"])
            }
        } else if clamped > currentInnings {
            let toAdd = clamped - currentInnings
            teams[idx].lineup.innings.append(contentsOf: Array(repeating: InningAssignment(), count: toAdd))
        }

        Analytics.signal("team.gameInningCount.changed", parameters: ["count": "\(clamped)"])
        save()
    }

    // MARK: - Schedule Management

    /// Merges a parsed set of calendar events into the active team's scheduledGames.
    /// Uses icalUID as the dedup key:
    ///   - New UID → append
    ///   - Existing UID, data changed → update in place
    ///   - Existing UID, no change → skip
    ///   - STATUS:CANCELLED in new data → mark isCancelled = true
    /// Returns a summary tuple for the toast: (added, updated).
    @discardableResult
    func mergeScheduledGames(_ incoming: [ScheduledGame]) -> (added: Int, updated: Int) {
        var added = 0
        var updated = 0

        for event in incoming {
            if let idx = activeTeam.scheduledGames.firstIndex(where: { $0.icalUID == event.icalUID }) {
                let existing = activeTeam.scheduledGames[idx]
                let changed = existing.date != event.date
                    || existing.opponent != event.opponent
                    || existing.location != event.location
                    || existing.isCancelled != event.isCancelled
                if changed {
                    activeTeam.scheduledGames[idx] = event
                    activeTeam.scheduledGames[idx].id = existing.id // preserve stable SwiftUI identity
                    updated += 1
                }
            } else {
                activeTeam.scheduledGames.append(event)
                added += 1
            }
        }

        // Keep sorted by date ascending
        activeTeam.scheduledGames.sort { $0.date < $1.date }
        save()
        return (added, updated)
    }

    /// Stores the webcal/https subscription URL on the active team.
    func setCalendarSubscriptionURL(_ urlString: String) {
        // Normalize webcal:// → https:// for URLSession compatibility
        let normalized = urlString.replacingOccurrences(of: "webcal://", with: "https://")
        activeTeam.calendarSubscriptionURL = normalized
        save()
    }

    /// Removes all scheduled games from the active team and clears the URL.
    func clearSchedule() {
        activeTeam.scheduledGames = []
        activeTeam.calendarSubscriptionURL = nil
        save()
        Analytics.signal("schedule.cleared")
    }

    /// Pre-fills the active lineup's date and opponent from a scheduled game.
    /// Does not lock the fields — coach can still edit after selection.
    func applyScheduledGame(_ game: ScheduledGame) {
        revertToDraftIfFinalized()
        activeTeam.lineup.gameDate = game.date
        if let opponent = game.opponent {
            activeTeam.lineup.opponent = opponent
        }
        save()
        Analytics.signal("schedule.game.applied")
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

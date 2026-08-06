import Foundation
import SwiftUI
import Combine
import os

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
    /// Auto-Fill tries to give each player a different field position in
    /// every inning. Falls back to repeats when no fresh positions are
    /// available rather than leaving a slot unfilled.
    var noRepeatPositions: Bool = false

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
        noRepeatPositions: Bool = false,
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
        self.noConsecutiveBench    = noConsecutiveBench
        self.noConsecutivePosition = noConsecutivePosition
        self.equalBenchTime        = equalBenchTime
        self.noRepeatPositions     = noRepeatPositions
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
        noRepeatPositions          = (try? c.decodeIfPresent(Bool.self,           forKey: .noRepeatPositions))          ?? false
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

nonisolated struct InningAssignment: Codable, Sendable {
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

    /// Enforces the invariant that at most one player holds any given fielding
    /// position in an inning. Bench and ABS are exempt — any number of players
    /// may share those.
    ///
    /// `assign(player:position:)` deliberately does not evict the current
    /// occupant (LineupStore.assignPosition handles eviction for interactive
    /// edits), so any path that builds an InningAssignment by replaying stored
    /// assignments in bulk — applying an archived game or a template — has to
    /// normalize afterwards or it can surface two pitchers in one inning.
    ///
    /// On conflict the player appearing earliest in `preferenceOrder` (the
    /// batting order) keeps the position; the others are left *unassigned*
    /// rather than benched. An open cell is visible and fixable in the grid,
    /// and it lets AutoFill fill the gap — silently benching someone would
    /// quietly change their playing time instead.
    nonisolated func deduplicatingFieldingPositions(preferring preferenceOrder: [UUID]) -> InningAssignment {
        var seenPositions: Set<FieldPosition> = []
        var result: [UUID: FieldPosition] = [:]

        let rank: (UUID) -> Int = { id in
            preferenceOrder.firstIndex(of: id) ?? Int.max
        }
        // Ties (both unranked) break on UUID so the result is stable rather
        // than dependent on dictionary iteration order.
        let ordered = assignments.sorted { lhs, rhs in
            let (l, r) = (rank(lhs.key), rank(rhs.key))
            return l == r ? lhs.key.uuidString < rhs.key.uuidString : l < r
        }

        for (playerID, position) in ordered {
            if position.isNonFielding {
                result[playerID] = position
            } else if !seenPositions.contains(position) {
                seenPositions.insert(position)
                result[playerID] = position
            }
            // else: duplicate holder of an already-taken position — cell stays open
        }

        var deduped = InningAssignment()
        deduped.assignments = result
        return deduped
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
    /// Display name of the coach who last finalized this lineup.
    /// Nil for lineups finalized before v3.0 or when coachName is not set.
    var lastFinalizedBy: String? = nil
    /// Timestamp of the most recent finalization. Nil for pre-v3.0 lineups.
    var lastFinalizedAt: Date? = nil
    /// ID of the team's default template, when that template's locks are what
    /// populated this lineup's grid. Drives the "you're overriding your default
    /// template" confirmation in the position pickers: a cell counts as
    /// default-assigned only while it still holds the player the template put
    /// there, so once the coach confirms an override that cell stops matching
    /// and never prompts again. Nil when no default template fed this lineup.
    var defaultTemplateID: UUID? = nil

    // Explicit memberwise init so views can construct a Lineup() directly.
    init(
        gameDate: Date = Date(),
        opponent: String = "",
        battingOrder: [UUID] = [],
        innings: [InningAssignment] = Array(repeating: InningAssignment(), count: Lineup.inningCount),
        absentPlayerIDs: Set<UUID> = [],
        status: LineupStatus = .draft,
        lastFinalizedBy: String? = nil,
        lastFinalizedAt: Date? = nil,
        defaultTemplateID: UUID? = nil
    ) {
        self.gameDate          = gameDate
        self.opponent          = opponent
        self.battingOrder      = battingOrder
        self.innings           = innings
        self.absentPlayerIDs   = absentPlayerIDs
        self.status            = status
        self.lastFinalizedBy   = lastFinalizedBy
        self.lastFinalizedAt   = lastFinalizedAt
        self.defaultTemplateID = defaultTemplateID
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
        // lastFinalizedBy and lastFinalizedAt are new in v3.0 — nil for older lineups
        lastFinalizedBy = try? c.decode(String.self,              forKey: .lastFinalizedBy)
        lastFinalizedAt = try? c.decode(Date.self,                forKey: .lastFinalizedAt)
        // defaultTemplateID is new — nil for lineups saved before default templates
        defaultTemplateID = try? c.decode(UUID.self,              forKey: .defaultTemplateID)
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

    /// True if `player` reaches `threshold` innings at `from` before ever being
    /// assigned `to`. Order matters: innings at `from` that come after the `to`
    /// inning don't count, since the rule is about what the player did *before*
    /// taking the second position.
    private nonisolated func crossesBatteryTransition(
        player: Player, from: FieldPosition, to: FieldPosition, threshold: Int
    ) -> Bool {
        var priorInnings = 0
        for inning in innings {
            switch inning.position(for: player) {
            case to where priorInnings >= threshold: return true
            case from: priorInnings += 1
            default: break
            }
        }
        return false
    }

    /// Players who caught at least `threshold` innings and *then* pitched.
    /// Returns [] when threshold == 0 (rule off).
    nonisolated func playersViolatingCatcherToPitcher(players: [Player], threshold: Int) -> [Player] {
        guard threshold > 0 else { return [] }
        return activePlayers(from: players).filter {
            crossesBatteryTransition(player: $0, from: .catcher, to: .pitcher, threshold: threshold)
        }
    }

    /// Players who pitched at least `threshold` innings and *then* caught.
    /// Returns [] when threshold == 0 (rule off).
    nonisolated func playersViolatingPitcherToCatcher(players: [Player], threshold: Int) -> [Player] {
        guard threshold > 0 else { return [] }
        return activePlayers(from: players).filter {
            crossesBatteryTransition(player: $0, from: .pitcher, to: .catcher, threshold: threshold)
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
        !backToBackBenchInnings(player: player).isEmpty
    }

    /// The 1-based inning pairs where the player sits twice in a row, e.g. `[(3, 4)]`.
    /// `hasBackToBackBench` answers *whether*; this answers *where*, so warning copy
    /// can name the innings rather than just the player.
    ///
    /// The count guard matters: `0..<innings.count - 1` traps on an empty innings
    /// array, which a hand-edited or truncated blob can produce.
    nonisolated func backToBackBenchInnings(player: Player) -> [(first: Int, second: Int)] {
        guard innings.count > 1 else { return [] }
        return (0..<innings.count - 1).compactMap { i in
            guard innings[i].position(for: player) == .bench,
                  innings[i + 1].position(for: player) == .bench else { return nil }
            return (i + 1, i + 2)
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

// MARK: - Fair Play Findings
//
// Which fair-play rules a lineup breaks, evaluated once against the team's
// config. The individual `playersWithout…` helpers above are the rules; this is
// the one place that knows which of them are switched on and what thresholds
// they run at.
//
// It exists because that "which rules are on" logic had been copy-pasted onto
// every surface that shows a warning, and the copies disagree. GameRecapIntent
// would have been the sixth copy — and a recap that reports a clean game while
// the app's own Fair Play rail shows a violation is worse than no recap.

nonisolated struct FairPlayFindings {
    /// Empty when the corresponding rule is switched off in `FairPlayConfig`,
    /// so callers never have to re-check the config to interpret a result.
    let withoutInfield: [Player]
    let withoutOutfield: [Player]
    let underFieldingMinimum: [Player]
    let backToBackBench: [Player]
    let catcherThenPitcher: [Player]
    let pitcherThenCatcher: [Player]
    /// The threshold `underFieldingMinimum` was measured against, so messages
    /// can name the real number rather than assuming the old hardcoded 4.
    let minimumFieldingInnings: Int

    /// Distinct players implicated in at least one rule. The warning badges
    /// count coaches, not violations — one player missing both infield and
    /// outfield is one thing to go fix.
    var implicatedPlayerIDs: Set<UUID> {
        Set((withoutInfield + withoutOutfield + underFieldingMinimum
             + backToBackBench + catcherThenPitcher + pitcherThenCatcher).map(\.id))
    }

    var isEmpty: Bool { implicatedPlayerIDs.isEmpty }
}

extension Lineup {

    /// Evaluates every fair-play rule that `config` has switched on.
    ///
    /// Note the two different roster arguments in play: the per-position rules
    /// run against active players only, while back-to-back bench is handed the
    /// full roster because `playersWithBackToBackBench` filters to active
    /// itself. That asymmetry was in all the copies; it's preserved here rather
    /// than "tidied", since changing it would change what the badges count.
    nonisolated func fairPlayFindings(players: [Player], config: FairPlayConfig) -> FairPlayFindings {
        let active = activePlayers(from: players)

        return FairPlayFindings(
            withoutInfield: config.minimumInfieldInnings > 0
                ? playersWithoutInfield(players: active) : [],
            withoutOutfield: config.minimumOutfieldInnings > 0
                ? playersWithoutOutfield(players: active) : [],
            underFieldingMinimum: config.minimumFieldingInnings > 0
                ? playersUnderFieldingMinimum(players: active,
                                              minimumInnings: config.minimumFieldingInnings) : [],
            backToBackBench: config.noConsecutiveBench
                ? playersWithBackToBackBench(from: players) : [],
            catcherThenPitcher: playersViolatingCatcherToPitcher(
                players: active, threshold: config.catcherToPitcherThreshold),
            pitcherThenCatcher: playersViolatingPitcherToCatcher(
                players: active, threshold: config.pitcherToCatcherThreshold),
            minimumFieldingInnings: config.minimumFieldingInnings
        )
    }
}

// MARK: - Lineup Template
// A reusable, partially-specified lineup. Unlike a saved Lineup, a template
// does not require every cell to be filled. Position locks pin specific
// players to specific positions for a range of innings (e.g. Caleb pitches
// innings 1-2). Every cell not covered by a lock stays open for the coach
// to fill manually or via AutoFillEngine, which already skips any slot that
// already has an assignment — so no AutoFillEngine changes are needed to
// respect locks.

struct PositionLock: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var playerID: UUID
    var position: FieldPosition
    /// 0-based inning range, inclusive. e.g. 0...1 covers innings 1-2 on screen.
    var innings: ClosedRange<Int>

    init(id: UUID = UUID(), playerID: UUID, position: FieldPosition, innings: ClosedRange<Int>) {
        self.id = id
        self.playerID = playerID
        self.position = position
        self.innings = innings
    }
}

struct LineupTemplate: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Full batting order — always fully specified, no partial locks.
    var battingOrder: [UUID]
    /// Locked player/position/inning-range triples. Everything not covered
    /// by a lock is left open in any lineup the template is applied to.
    var positionLocks: [PositionLock]
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        name: String,
        battingOrder: [UUID],
        positionLocks: [PositionLock],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.battingOrder = battingOrder
        self.positionLocks = positionLocks
        self.createdAt = createdAt
    }

    // Custom decode: safe defaults so a future field addition doesn't break
    // decoding of templates saved by an older build.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = (try? c.decode(UUID.self,            forKey: .id))            ?? UUID()
        name          = (try? c.decode(String.self,          forKey: .name))          ?? ""
        battingOrder  = (try? c.decode([UUID].self,           forKey: .battingOrder))  ?? []
        positionLocks = (try? c.decode([PositionLock].self,   forKey: .positionLocks)) ?? []
        createdAt     = (try? c.decode(Date.self,             forKey: .createdAt))     ?? Date()
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
    /// Display name of the coach who archived this game. Empty for logs created
    /// before v3.0 or on single-coach teams.
    var archivedBy: String = ""
    /// Freeform coach notes captured at archive time. Optional — empty for games
    /// archived before v3.1. Editable retroactively from GameLogDetailView.
    var notes: String = ""

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
        archivedBy     = (try? c.decode(String.self, forKey: .archivedBy)) ?? ""
        notes          = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
    }

    init(id: UUID = UUID(), gameDate: Date, opponent: String, inningsPlayed: Int,
         battingOrder: [UUID], innings: [InningAssignment], playerSnapshot: [PlayerSnapshot],
         archivedAt: Date = Date(), pitchCounts: [String: Int] = [:], archivedBy: String = "",
         notes: String = "") {
        self.id             = id
        self.gameDate       = gameDate
        self.opponent       = opponent
        self.inningsPlayed  = inningsPlayed
        self.battingOrder   = battingOrder
        self.innings        = innings
        self.playerSnapshot = playerSnapshot
        self.archivedAt     = archivedAt
        self.pitchCounts    = pitchCounts
        self.archivedBy     = archivedBy
        self.notes          = notes
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
    /// 7 (Little League Majors+). Drives the size of new lineups created via
    /// clearPositions() and the inningsPlayed clamp at archive time. Existing archived
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
    /// The coach's display name, used to attribute lineup finalization in shared teams.
    /// Defaults to the device name on creation. Editable in Edit Team.
    var coachName: String = ""
    /// The CKRecord.ID.recordName for this team's CloudKit record.
    /// Nil until the team has been saved to CloudKit (post-v3.0 migration).
    var ckRecordName: String? = nil
    /// True when this team is a shared record owned by another coach.
    /// All editing is locked for read-only participants.
    var isReadOnly: Bool = false
    /// True when this team was received via CKShare (participant copy, not the owner).
    /// Used to route CloudKit saves to sharedDB instead of privateDB.
    /// Never persisted to the server blob -- always re-derived from the fetch path.
    var isSharedParticipant: Bool = false
    /// Saved lineup templates for this team. First template is free; additional
    /// templates are Pro-gated (checked at the UI layer via purchaseManager.isPro,
    /// same pattern as Multiple Teams).
    var lineupTemplates: [LineupTemplate] = []
    /// The one template, if any, that auto-fills the grid at the start of every
    /// new game. At most one template per team can hold this — setting a new
    /// default replaces the old one rather than adding to a list.
    var defaultTemplateID: UUID? = nil

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
        pitchingConfig: PitchingConfig = PitchingConfig(),
        coachName: String = "",
        ckRecordName: String? = nil,
        isReadOnly: Bool = false,
        isSharedParticipant: Bool = false,
        lineupTemplates: [LineupTemplate] = [],
        defaultTemplateID: UUID? = nil
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
        self.coachName = coachName
        self.ckRecordName = ckRecordName
        self.isReadOnly = isReadOnly
        self.isSharedParticipant = isSharedParticipant
        self.lineupTemplates = lineupTemplates
        self.defaultTemplateID = defaultTemplateID
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
        // coachName, ckRecordName, isReadOnly are new in v3.0.
        // coachName defaults to empty string — LineupStore migration fills it from device name.
        coachName                = (try? c.decode(String.self,           forKey: .coachName))               ?? ""
        ckRecordName             = try? c.decode(String.self,            forKey: .ckRecordName)
        isReadOnly               = (try? c.decode(Bool.self,             forKey: .isReadOnly))              ?? false
        // isSharedParticipant is never stored in the JSON blob -- it is always
        // re-derived from the fetch path (fetchSharedTeams sets it to true).
        isSharedParticipant      = false
        // lineupTemplates is new in this release — older Team blobs won't include it.
        lineupTemplates          = (try? c.decode([LineupTemplate].self, forKey: .lineupTemplates)) ?? []
        // defaultTemplateID is new in this release — nil means no default template,
        // which is the pre-upgrade behavior for every existing team.
        defaultTemplateID        = try? c.decode(UUID.self,              forKey: .defaultTemplateID)
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

    /// Teams deleted on this device. Persisted immediately on every change —
    /// a tombstone that only lived in memory would be gone by the relaunch
    /// where it matters most. See `TeamTombstones`.
    var tombstones: TeamTombstones = TeamStorage.loadTombstones() {
        didSet {
            guard tombstones != oldValue else { return }
            TeamStorage.saveTombstones(tombstones)
        }
    }

    /// Teams deleted on another device that this one still has. Drives the
    /// "deleted elsewhere — delete here too?" prompt. In-memory: if the app
    /// closes before the coach answers, the next fetch asks again.
    @Published var pendingRemoteDeletions: [PendingRemoteDeletion] = []

    /// Record names the coach chose to keep. Persisted so the prompt asks once
    /// and then stops — a dialog that returns on every sync is worse than none.
    var declinedRemoteDeletions: Set<String> = TeamStorage.loadDeclinedDeletions() {
        didSet {
            guard declinedRemoteDeletions != oldValue else { return }
            TeamStorage.saveDeclinedDeletions(declinedRemoteDeletions)
        }
    }
    /// Drives the share-sheet roster import flow. Set when the app receives a
    /// CSV/.stlroster file via .onOpenURL. ContentView observes this and presents
    /// the team-picker and preview chain.
    @Published var pendingRosterImport: PendingRosterImport = .none
    /// Opponent of the archived game the current lineup was copied from, or nil
    /// if it wasn't copied. Drives two things: ContentView switches to the
    /// Lineup tab when this becomes non-nil, and LineupView shows the "Copied
    /// from…" banner while it stays non-nil. Not persisted — it describes this
    /// session's navigation, not the lineup itself.
    @Published var copiedFromGameOpponent: String?
    /// Transient confirmation for the reuse actions, rendered by ContentView
    /// above the tab bar. Lives here rather than in the History screen because
    /// copying switches tabs — a toast owned by the screen that triggered it
    /// would animate in off screen.
    @Published var reuseToast: String?

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
    // Storage keys live on TeamStorage — the write path below and the read path
    // in TeamStorage.load() must never drift apart.
    private let maxGameLogs   = 20

    // MARK: - Init
    init() { load() }

    // MARK: - Persistence

    func save() {
        saveLocalOnly()

        // CloudKit push — fire and forget, fully isolated from the local write path.
        // Only the active team is pushed; it is always the one that was just mutated.
        // If CloudKit returns a new ckRecordName (first-ever save for this team),
        // stamp it back onto the in-memory team and persist locally.
        guard let activeTeamID else { return }
        let teamCopy = teams.first(where: { $0.id == activeTeamID })
        // Read-only participants cannot write back to CloudKit.
        // Read-write participants (isSharedParticipant && !isReadOnly) can and should.
        guard let teamCopy, !teamCopy.isReadOnly else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let recordName = try await CloudKitManager.shared.saveTeam(teamCopy, useSharedDB: teamCopy.isSharedParticipant)
                if teamCopy.ckRecordName == nil {
                    await MainActor.run {
                        if let idx = self.teams.firstIndex(where: { $0.id == teamCopy.id }) {
                            self.teams[idx].ckRecordName = recordName
                            self.saveLocalOnly()
                        }
                    }
                }
            } catch {
                Log.sync.error("CloudKit save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Writes teams to UserDefaults and NSUbiquitousKeyValueStore without triggering
    /// a CloudKit push. Use when persisting metadata-only changes (e.g. ckRecordName
    /// stamps) that CloudKit already knows about, to avoid redundant round-trips.
    private func saveLocalOnly() {
        let snapshot   = teams
        let activeID   = activeTeamID?.uuidString
        let widgetTeam = activeTeam  // value copy — safe to capture in detached task
        let savedAt    = Date().timeIntervalSince1970

        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(snapshot) else { return }

            // Write to UserDefaults on main thread
            await MainActor.run {
                UserDefaults.standard.set(data, forKey: TeamStorage.teamsKey)
                UserDefaults.standard.set(savedAt, forKey: TeamStorage.savedAtKey)
                if let id = activeID {
                    UserDefaults.standard.set(id, forKey: TeamStorage.activeTeamKey)
                }
            }

            // Write to iCloud KV store off main thread — synchronize() must
            // not be called on the main thread per Apple documentation.
            // KV store is kept as a fallback alongside CloudKit for v3.0.
            //
            // DEBUG builds never write the KV store: it is shared across every
            // install of the bundle ID on the same Apple ID (no dev/prod split,
            // unlike CloudKit), so a debug write here can clobber real devices.
            // This caused the July 2026 data wipe.
            #if !DEBUG
            let icloud = NSUbiquitousKeyValueStore.default
            if data.count < 800_000 {
                icloud.set(data, forKey: TeamStorage.teamsKey)
                icloud.set(savedAt, forKey: TeamStorage.savedAtKey)
                if let id = activeID { icloud.set(id, forKey: TeamStorage.activeTeamKey) }
                icloud.synchronize()
            } else {
                // The saved-at stamp is deliberately not written either: the KV
                // copy stays frozen at its old timestamp, so applyStoredData()
                // keeps preferring the newer local blob instead of the stale
                // KV one.
                Log.storage.notice("Teams blob exceeds the iCloud KV safety threshold; storing locally only")
            }
            #endif

            // Write lightweight snapshot to App Group container for the home screen widget.
            await MainActor.run {
                WidgetDataBridge.writeSnapshot(from: widgetTeam)
            }

            // Republish players and teams to Spotlight. Passed the snapshot rather
            // than re-reading storage, and internally a no-op unless the roster
            // itself changed — this runs on every position drag.
            await STLSpotlightIndexer.reindexIfNeeded(teams: snapshot)
        }
    }

    func load() {
        applyStoredData()

        // Register for iCloud change notifications so updates from other
        // devices are applied as soon as they arrive.
        // Guard against duplicate observers on re-load.
        // DEBUG builds skip the KV store entirely — see applyStoredData().
        #if !DEBUG
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
        #endif

        // One-time CloudKit migration — runs exactly once per install, gated by
        // hasCompletedCloudKitMigration in UserDefaults. Defers gracefully when
        // iCloud is unavailable. Stamps ckRecordName onto each team after upload.
        let currentTeams = teams
        Task { [weak self] in
            guard let self else { return }
            do {
                let updatedTeams = try await CloudKitManager.shared.migrateFromKVStoreIfNeeded(teams: currentTeams)
                await MainActor.run {
                    for serverTeam in updatedTeams {
                        if let idx = self.teams.firstIndex(where: { $0.id == serverTeam.id }),
                           self.teams[idx].ckRecordName == nil,
                           let recordName = serverTeam.ckRecordName {
                            self.teams[idx].ckRecordName = recordName
                        }
                    }
                    self.saveLocalOnly()
                }
            } catch {
                // Deferral (e.g. no iCloud account) is expected and non-fatal.
                // The gate flag was not set, so migration retries on next launch.
                Log.sync.notice("CloudKit migration deferred: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Decides whether the iCloud KV copy of the teams blob should be applied
    /// instead of the local UserDefaults copy. The newer save-timestamp wins;
    /// a missing timestamp sorts oldest (legacy blobs), and ties prefer local
    /// so a device's own data is never shadowed by stale shared sync state.
    /// Whether the iCloud KV copy should win over the local one.
    /// Thin forwarder — the implementation lives in TeamStorage so the App Intents
    /// layer arbitrates identically. Kept here as the name the tests already use.
    nonisolated static func shouldPreferCloudBlob(cloudData: Data?, cloudSavedAt: TimeInterval,
                                                  localData: Data?, localSavedAt: TimeInterval) -> Bool {
        TeamStorage.shouldPreferCloudBlob(cloudData: cloudData, cloudSavedAt: cloudSavedAt,
                                          localData: localData, localSavedAt: localSavedAt)
    }

    /// Applies whichever stored copy TeamStorage selected into this store.
    /// Safe to call multiple times.
    ///
    /// Reading and decoding now live in TeamStorage.load() so that App Intents,
    /// which cannot reach this @StateObject, resolve teams through the exact same
    /// path. What stays here is everything that needs live store state: clobber
    /// detection against the currently loaded teams, first-launch migration, and
    /// the stale-game-date reset.
    ///
    /// SAFETY RULE: if storage contains data but it fails to decode, we return
    /// early without touching `teams`. This prevents a decode failure from
    /// cascading into migrateOrCreateDefaultTeam() which would overwrite iCloud
    /// with an empty team.
    private func applyStoredData() {
        let decodedTeams: [Team]?
        let savedActiveID: UUID?

        switch TeamStorage.load() {
        case .decodeFailed:
            // Data exists but failed to decode (e.g. schema mismatch).
            // DO NOT fall through to migration — that would overwrite iCloud
            // with an empty team. Leave teams as-is and wait for a future
            // successful sync or manual recovery.
            Log.storage.fault("stl_teams exists but failed to decode; aborting load to protect existing data")
            return
        case .loaded(let loaded, let activeID):
            decodedTeams  = loaded
            savedActiveID = activeID
        case .empty(let activeID):
            // Genuine first launch — fall through to migration.
            decodedTeams  = nil
            savedActiveID = activeID
        }

        if let decoded = decodedTeams {
            // Cheap clobber detection: an incoming blob carrying notably less
            // data than what's already loaded is the signature of a sync wipe
            // (July 2026 incident). Signal it so future variants are visible.
            if !teams.isEmpty {
                let oldLogs = teams.reduce(0) { $0 + $1.gameLogs.count }
                let newLogs = decoded.reduce(0) { $0 + $1.gameLogs.count }
                if decoded.count < teams.count || newLogs < oldLogs {
                    Analytics.signal("sync.blob_shrank", parameters: [
                        "oldTeams": "\(teams.count)", "newTeams": "\(decoded.count)",
                        "oldLogs": "\(oldLogs)", "newLogs": "\(newLogs)"
                    ])
                }
            }
            teams = decoded
        }

        if let uuid = savedActiveID {
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

    // MARK: - CloudKit Foreground Sync

    /// Fetches incremental CloudKit changes (private + shared databases) and merges
    /// them into the local teams array. Call from ContentView when scenePhase == .active.
    ///
    /// Merge rules:
    ///   Modified owned teams: replace local copy (CloudKit is authoritative post-migration).
    ///   Modified shared teams: replace local copy if isReadOnly, skip if owner's copy.
    ///   Deleted records: remove only read-only teams (owned deletions are explicit user actions).
    ///   New shared teams: append if not already present by ckRecordName.
    func fetchCloudKitChanges() async {
        Log.sync.debug("fetchCloudKitChanges called")
        // Zone creation is idempotent and cheap after the first call.
        do { try await CloudKitManager.shared.ensureZoneExists() } catch {
            Log.sync.error("CloudKit ensureZoneExists failed: \(error.localizedDescription, privacy: .public)")
        }

        // Run private and shared fetches independently so a failure in one
        // does not prevent the other from loading. This is critical on the
        // recipient device where the private STLTeams zone is brand new and
        // fetchChanges() may throw before a change token is established.
        var privateChanges = CloudKitManager.FetchChangesResult(
            modifiedTeams: [],
            deletedRecordNames: []
        )
        var sharedTeams: [Team] = []

        do {
            privateChanges = try await CloudKitManager.shared.fetchChanges()
        } catch {
            Log.sync.error("CloudKit private fetch failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            sharedTeams = try await CloudKitManager.shared.fetchSharedTeams()
        } catch {
            Log.sync.error("CloudKit shared fetch failed: \(error.localizedDescription, privacy: .public)")
        }

        await MainActor.run {
            self.mergeCloudKitChanges(privateChanges, sharedTeams: sharedTeams)
        }
    }

    @MainActor
    private func mergeCloudKitChanges(
        _ changes: CloudKitManager.FetchChangesResult,
        sharedTeams: [Team]
    ) {
        var didChange = false

        // Apply modified/new teams from the private database.
        // coachName is a local-only field — it must never be overwritten by a
        // server copy, because the server blob always carries the owner's name.
        for serverTeam in changes.modifiedTeams {
            if let idx = localIndex(for: serverTeam) {
                var updated = serverTeam
                updated.coachName = teams[idx].coachName
                teams[idx] = updated
            } else {
                // No local match. Before this check that meant "new team, add
                // it" — including on a fresh install, where nothing matches and
                // every record the coach ever deleted came back.
                guard !tombstones.blocks(teamID: serverTeam.id, recordName: serverTeam.ckRecordName) else {
                    Log.sync.info("Ignored a server team this device deleted")
                    continue
                }
                teams.append(serverTeam)
            }
            didChange = true
        }

        // A record deleted on the server means two different things depending on
        // whose team it is.
        //
        // Read-only (shared) teams are removed outright — the owner deleted it,
        // and a participant's copy has no independent existence.
        //
        // Owned teams are NOT auto-removed. That rule predates this code and is
        // right: a spurious or misread deletion would silently destroy a coach's
        // roster. But leaving it at that meant the other device just kept the
        // team forever and re-uploaded it. So we ask instead.
        let outcome = Self.classifyRemoteDeletions(
            recordNames: changes.deletedRecordNames,
            teams: teams,
            declined: declinedRemoteDeletions
        )

        if !outcome.autoRemove.isEmpty {
            teams.removeAll { outcome.autoRemove.contains($0.id) }
            didChange = true
        }

        for pending in outcome.prompt where !pendingRemoteDeletions.contains(where: { $0.id == pending.id }) {
            pendingRemoteDeletions.append(pending)
        }

        // Merge shared teams from the shared database.
        //
        // Owned teams (isReadOnly == false) also arrive here when an assistant
        // coach edits the shared record -- e.g. finalizing a lineup. We must
        // update them too, not just read-only copies.
        //
        // coachName is local-only: always preserve the value already on disk
        // so each coach sees their own name in "Finalized by", not the owner's.
        //
        // isSharedParticipant is always true for these teams -- it is never
        // stored in the JSON blob so we must stamp it here every time.
        for sharedTeam in sharedTeams {
            if let idx = localIndex(for: sharedTeam) {
                let localCoachName = teams[idx].coachName
                var updated = sharedTeam
                updated.coachName = localCoachName
                updated.isSharedParticipant = true
                teams[idx] = updated
                didChange = true
            } else {
                // Same guard as the private path: a coach who left a shared team
                // shouldn't have it reappear from the next shared fetch.
                // `acceptShare` clears the tombstone, so a genuine re-invite
                // still works.
                guard !tombstones.blocks(teamID: sharedTeam.id, recordName: sharedTeam.ckRecordName) else {
                    Log.sync.info("Ignored a shared team this device left")
                    continue
                }
                var newTeam = sharedTeam
                newTeam.coachName = UIDevice.current.name
                newTeam.isSharedParticipant = true
                teams.append(newTeam)
                didChange = true
            }
        }

        // Dedup sweep — removes any duplicate teams that snuck in before this fix
        // shipped. Two teams are duplicates if they share the same ckRecordName or
        // the same UUID. First occurrence wins (it has the most recent local edits).
        let beforeDedup = teams.count
        var seenRecordNames = Set<String>()
        var seenUUIDs       = Set<UUID>()
        teams = teams.filter { team in
            if let rn = team.ckRecordName {
                guard seenRecordNames.insert(rn).inserted else { return false }
            }
            return seenUUIDs.insert(team.id).inserted
        }
        if teams.count != beforeDedup { didChange = true }

        // Keep activeTeamID pointing at a valid team.
        if activeTeamID == nil || !teams.contains(where: { $0.id == activeTeamID }) {
            activeTeamID = teams.first?.id
            didChange = true
        }

        if didChange { saveLocalOnly() }
    }

    /// Finds the local index for a server-returned team.
    ///
    /// Primary match: ckRecordName (the normal post-migration path).
    /// Fallback match: UUID embedded in the record name ("team-<UUID>") for
    /// teams whose local copy hasn't been stamped with ckRecordName yet
    /// (e.g. the window between migration upload and the ckRecordName stamp-back).
    /// This prevents fetchCloudKitChanges from appending duplicates during that window.
    @MainActor
    private func localIndex(for serverTeam: Team) -> Int? {
        // Primary: exact ckRecordName match.
        if let idx = teams.firstIndex(where: { $0.ckRecordName == serverTeam.ckRecordName }) {
            return idx
        }
        // Fallback: parse UUID out of "team-<UUID>" record name and match by team.id.
        guard let recordName = serverTeam.ckRecordName,
              recordName.hasPrefix("team-"),
              let uuid = UUID(uuidString: String(recordName.dropFirst(5))) else { return nil }
        return teams.firstIndex(where: { $0.id == uuid })
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
            activeTeam.lineup.lastFinalizedBy = nil
            activeTeam.lineup.lastFinalizedAt = nil
            Analytics.signal("lineup.reverted_to_draft", parameters: ["trigger": "edit"])
        }
    }

    /// Marks the active lineup as finalized. Soft status only — editing remains possible
    /// and will automatically revert back to draft.
    func finalizeLineup() {
        activeTeam.lineup.status = .finalized
        // The banner asks the coach to review and finalize; finalizing is them
        // doing it, so it has nothing left to say.
        copiedFromGameOpponent = nil
        let name = activeTeam.coachName.trimmingCharacters(in: .whitespaces)
        activeTeam.lineup.lastFinalizedBy = name.isEmpty ? nil : name
        activeTeam.lineup.lastFinalizedAt = Date()
        save()
        Analytics.signal("lineup.finalized")

        // Notify other coaches via Cloudflare Worker -> APNs.
        let opponent = activeTeam.lineup.opponent
        let gameDate = activeTeam.lineup.gameDate.formatted(
            Date.FormatStyle().month(.abbreviated).day()
        )
        NotificationManager.shared.postEvent(
            eventType: NotificationManager.eventLineupFinalized,
            team: activeTeam,
            metadata: [
                "opponent": opponent,
                "gameDate": gameDate,
            ]
        )
    }

    /// Reopens a finalized lineup, setting status back to draft.
    func reopenLineup() {
        activeTeam.lineup.status = .draft
        save()
        Analytics.signal("lineup.reopened")
    }

    // MARK: - Game Log Operations

    @discardableResult
    func archiveCurrentLineup(inningsPlayed: Int, notes: String = "") -> UUID {
        let snapshot = activeTeam.players.map { PlayerSnapshot(from: $0) }

        let coachName = activeTeam.coachName.trimmingCharacters(in: .whitespaces)
        let log = GameLog(
            gameDate: activeTeam.lineup.gameDate,
            opponent: activeTeam.lineup.opponent,
            inningsPlayed: max(1, min(activeTeam.gameInningCount, inningsPlayed)),
            battingOrder: activeTeam.lineup.battingOrder,
            innings: activeTeam.lineup.innings,
            playerSnapshot: snapshot,
            archivedBy: coachName,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        activeTeam.gameLogs.append(log)
        activeTeam.gameLogs.sort { $0.gameDate > $1.gameDate }
        if activeTeam.gameLogs.count > maxGameLogs {
            activeTeam.gameLogs = Array(activeTeam.gameLogs.prefix(maxGameLogs))
        }

        clearPositions()
        // Archiving is the app's only "new game starts now" moment, so this is
        // where a default template earns its keep — the next game opens with
        // the coach's standing assignments already in the grid.
        applyDefaultTemplatePositions()
        // The game the banner referred to has been played and archived.
        copiedFromGameOpponent = nil
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

    /// Updates the freeform notes on an archived game log.
    func updateGameLogNotes(_ notes: String, for logID: UUID) {
        guard let idx = activeTeam.gameLogs.firstIndex(where: { $0.id == logID }) else { return }
        activeTeam.gameLogs[idx].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        Analytics.signal("gamelog.notes.updated")
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
        assignPosition(player: player, innings: [inning], position: position)
    }

    /// Assigns one player to the same position across several innings in a
    /// single save.
    ///
    /// Every `save()` encodes the whole `[Team]` array, writes UserDefaults and
    /// the iCloud KV store, rewrites the widget snapshot and fires a CloudKit
    /// push — so calling the single-inning version in a loop cost six of each
    /// for a six-inning Quick Set. Same reasoning as `addPlayers(_:)`, which
    /// exists so roster import doesn't write once per player.
    ///
    /// Out-of-range innings are skipped rather than trapping: callers derive
    /// them from UI state that can lag a game-length change.
    func assignPosition(player: Player, innings: [Int], position: FieldPosition) {
        guard !innings.isEmpty else { return }
        revertToDraftIfFinalized()
        for inning in innings where activeTeam.lineup.innings.indices.contains(inning) {
            // Evicting the current occupant is per-inning: the same position can
            // be held by a different player in each one.
            if !position.isBench,
               let occupant = activeTeam.lineup.innings[inning].player(at: position, in: activeTeam.players),
               occupant.id != player.id {
                activeTeam.lineup.innings[inning].removeAssignment(for: occupant)
            }
            activeTeam.lineup.innings[inning].assign(player: player, position: position)
        }
        save()
    }

    func removeAssignment(player: Player, inning: Int) {
        removeAssignments(player: player, innings: [inning])
    }

    /// Clears one player from several innings in a single save. See
    /// `assignPosition(player:innings:position:)` for why the bulk form exists.
    func removeAssignments(player: Player, innings: [Int]) {
        guard !innings.isEmpty else { return }
        revertToDraftIfFinalized()
        for inning in innings where activeTeam.lineup.innings.indices.contains(inning) {
            activeTeam.lineup.innings[inning].removeAssignment(for: player)
        }
        save()
    }

    func clearPositions() {
        revertToDraftIfFinalized()
        activeTeam.lineup.innings = Array(repeating: InningAssignment(), count: activeTeam.gameInningCount)
        // Nothing from the default template survives an explicit clear, so the
        // grid stops being attributable to it. (archiveCurrentLineup re-applies
        // the default immediately after calling this, which re-sets the link.)
        activeTeam.lineup.defaultTemplateID = nil
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
        let targetID = teamID ?? activeTeamID
        guard let targetID = targetID,
              let idx = teams.firstIndex(where: { $0.id == targetID }) else { return }
        if applyGameInningCount(newCount, at: idx) { save() }
    }

    /// The resize half of `updateGameInningCount`, without the `save()`.
    ///
    /// Split out so an edit that also changes the name, colour or coach name can
    /// persist all of it in one `save()` — each `save()` is a full re-encode of
    /// `[Team]` plus a CloudKit upload of the whole team blob, so Edit Team was
    /// firing two of them for a single submission.
    ///
    /// Returns false when the count is already `clamped` and nothing was
    /// touched, which is what keeps `updateGameInningCount` from saving on a
    /// no-op the way it always has.
    @discardableResult
    private func applyGameInningCount(_ newCount: Int, at idx: Int) -> Bool {
        let clamped = max(1, min(9, newCount))
        guard clamped != teams[idx].gameInningCount else { return false }

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
        return true
    }

    /// Applies one Edit Team submission — name, colour, coach name and game
    /// length — in a single save.
    ///
    /// Exists because the caller can't get this right by composing the
    /// individual mutators: `updateGameInningCount` saves, but only when the
    /// count actually changed, so a trailing `save()` for the other three fields
    /// is load-bearing on the unchanged path and a duplicate upload on the
    /// changed one. Always saves — name, colour and coach name have no
    /// equivalent early return.
    func updateTeamDetails(id: UUID, name: String, color: Color, coachName: String, gameInningCount: Int) {
        guard let idx = teams.firstIndex(where: { $0.id == id }) else { return }
        teams[idx].name = name
        teams[idx].color = color
        teams[idx].coachName = coachName
        applyGameInningCount(gameInningCount, at: idx)
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

    // MARK: - Lineup Templates

    /// Templates saved for the active team: the default first so it's visible
    /// without scrolling, then the rest most recent first.
    var lineupTemplates: [LineupTemplate] {
        let defaultID = activeTeam.defaultTemplateID
        return activeTeam.lineupTemplates.sorted { lhs, rhs in
            if (lhs.id == defaultID) != (rhs.id == defaultID) { return lhs.id == defaultID }
            return lhs.createdAt > rhs.createdAt
        }
    }

    /// Saves a new template to the active team. Pro-gating (first template
    /// free, additional templates require Pro) is enforced by the caller —
    /// same pattern as Multiple Teams — this method performs no gating itself.
    func saveTemplate(_ template: LineupTemplate) {
        activeTeam.lineupTemplates.append(template)
        Analytics.signal("template.saved", parameters: [
            "templateCount": "\(activeTeam.lineupTemplates.count)"
        ])
        save()
    }

    func deleteTemplate(id: UUID) {
        activeTeam.lineupTemplates.removeAll { $0.id == id }
        // A deleted template can't stay the default, and any grid it populated
        // is no longer traceable back to it — drop both references.
        if activeTeam.defaultTemplateID == id {
            activeTeam.defaultTemplateID = nil
        }
        if activeTeam.lineup.defaultTemplateID == id {
            activeTeam.lineup.defaultTemplateID = nil
        }
        Analytics.signal("template.deleted")
        save()
    }

    // MARK: - Default Template

    /// The template that auto-fills the grid at the start of every new game,
    /// or nil when the coach hasn't chosen one.
    var defaultTemplate: LineupTemplate? {
        guard let id = activeTeam.defaultTemplateID else { return nil }
        return activeTeam.lineupTemplates.first { $0.id == id }
    }

    func isDefaultTemplate(_ id: UUID) -> Bool {
        activeTeam.defaultTemplateID == id
    }

    /// Promotes a template to the team's default, or clears the default when
    /// passed nil. Only one template can be the default, so this replaces any
    /// previous choice rather than adding to a set.
    func setDefaultTemplate(id: UUID?) {
        guard activeTeam.defaultTemplateID != id else { return }
        activeTeam.defaultTemplateID = id
        // The current grid was not built from the incoming default, so it must
        // not start claiming those cells as default-assigned.
        activeTeam.lineup.defaultTemplateID = nil
        Analytics.signal(id == nil ? "template.default.cleared" : "template.default.set")
        save()
    }

    /// Fills the (already empty) grid from the default template's position
    /// locks, leaving the batting order alone. Called at the start of a new
    /// game — archiving clears positions but deliberately keeps the batting
    /// order, and the default template follows that same split.
    ///
    /// No-op when there's no default template, so teams that never set one
    /// see exactly the pre-existing behavior.
    private func applyDefaultTemplatePositions() {
        guard let template = defaultTemplate else { return }

        let inningCount = activeTeam.gameInningCount
        var innings = Array(repeating: InningAssignment(), count: inningCount)

        for lock in template.positionLocks {
            // Player left the roster since the template was saved — skip
            // silently, matching applyTemplate. That cell stays open.
            guard let player = activeTeam.players.first(where: { $0.id == lock.playerID }) else { continue }
            for inningIndex in lock.innings where inningIndex >= 0 && inningIndex < inningCount {
                innings[inningIndex].assign(player: player, position: lock.position)
            }
        }

        let preference = activeTeam.lineup.battingOrder
        activeTeam.lineup.innings = innings.map { $0.deduplicatingFieldingPositions(preferring: preference) }
        activeTeam.lineup.defaultTemplateID = template.id
        Analytics.signal("template.default.autoApplied")
    }

    /// The player the default template placed at this cell, if that template
    /// fed the current grid and the cell still holds that exact player. Returns
    /// nil once the coach has overridden the cell, which is what keeps the
    /// override confirmation from firing twice on the same slot.
    func defaultTemplatePlayer(inning: Int, position: FieldPosition) -> Player? {
        guard let templateID = activeTeam.lineup.defaultTemplateID,
              let template = activeTeam.lineupTemplates.first(where: { $0.id == templateID }),
              inning >= 0, inning < activeTeam.lineup.innings.count
        else { return nil }

        let lockedPlayerIDs = template.positionLocks
            .filter { $0.position == position && $0.innings.contains(inning) }
            .map { $0.playerID }
        guard !lockedPlayerIDs.isEmpty else { return nil }

        guard let occupant = activeTeam.lineup.innings[inning].player(at: position, in: activeTeam.players),
              lockedPlayerIDs.contains(occupant.id)
        else { return nil }

        return occupant
    }

    /// True when this cell is still exactly as the default template left it,
    /// so changing or clearing it overrides the coach's default.
    func isDefaultTemplateAssignment(inning: Int, position: FieldPosition) -> Bool {
        defaultTemplatePlayer(inning: inning, position: position) != nil
    }

    /// True when moving this player within this inning would pull them out of a
    /// cell the default template assigned them to. Used by the player-led
    /// picker, where the coach picks a new position rather than a new player.
    func isDefaultTemplateAssignment(player: Player, inning: Int) -> Bool {
        guard inning >= 0, inning < activeTeam.lineup.innings.count,
              let position = activeTeam.lineup.innings[inning].position(for: player)
        else { return false }
        return defaultTemplatePlayer(inning: inning, position: position)?.id == player.id
    }

    /// Name of the default template, for use in override copy.
    var defaultTemplateName: String? { defaultTemplate?.name }

    /// Builds a fresh Lineup from a template, scoped to the active team's
    /// current roster. Any locked player no longer on the active roster is
    /// silently skipped — that cell (and any batting order slot) stays open
    /// rather than surfacing a warning. Everything not covered by a lock is
    /// left open for manual assignment or AutoFill, which already never
    /// touches a slot that already has an assignment.
    func applyTemplate(_ template: LineupTemplate) {
        revertToDraftIfFinalized()

        let activeIDs = Set(activeTeam.players.map { $0.id })
        var newLineup = Lineup()
        newLineup.gameDate = activeTeam.lineup.gameDate
        newLineup.opponent = activeTeam.lineup.opponent

        // Batting order is always fully specified on the template — but still
        // filter out players no longer on the roster, compressing the order
        // rather than leaving a gap.
        newLineup.battingOrder = template.battingOrder.filter { activeIDs.contains($0) }

        // Resize innings to match the team's current game length before
        // applying locks, so lock ranges map onto the right inning count.
        let inningCount = activeTeam.gameInningCount
        newLineup.innings = Array(repeating: InningAssignment(), count: inningCount)

        for lock in template.positionLocks {
            guard let player = activeTeam.players.first(where: { $0.id == lock.playerID }) else {
                continue // player no longer on roster — skip silently, cell stays open
            }
            for inningIndex in lock.innings {
                guard inningIndex >= 0 && inningIndex < newLineup.innings.count else { continue }
                newLineup.innings[inningIndex].assign(player: player, position: lock.position)
            }
        }

        // Two locks can name the same position in the same inning (nothing in
        // the lock editor prevents saving a template built from a grid that
        // already had a conflict), so normalize before this becomes the
        // coach's live lineup.
        let preference = newLineup.battingOrder
        newLineup.innings = newLineup.innings.map {
            $0.deduplicatingFieldingPositions(preferring: preference)
        }

        // Applying the default template by hand produces the same grid the new-game
        // auto-apply would, so those cells get the same override protection.
        // Any other template's cells are a deliberate one-off and stay unguarded.
        newLineup.defaultTemplateID = (template.id == activeTeam.defaultTemplateID) ? template.id : nil

        activeTeam.lineup = newLineup
        Analytics.signal("template.applied", parameters: ["templateName": template.name])
        save()
    }

    // MARK: - Reusing Archived Games

    /// Copies an archived game's batting order and defensive assignments onto
    /// the active lineup, keeping the current game's date and opponent — the
    /// coach is reusing the shape of an old game for today's game, not
    /// re-importing the old game itself.
    ///
    /// Mirrors applyTemplate's roster handling: any player no longer on the
    /// active roster is skipped silently, both in the batting order (which
    /// compresses rather than leaving a gap) and in the grid (that cell stays
    /// open). Innings are resized to the team's current game length, so a
    /// 7-inning log applied to a 6-inning team drops the trailing inning.
    ///
    /// ABS assignments are deliberately not carried over — absence is specific
    /// to the game it was recorded in, so those cells come back open. Bench
    /// assignments are copied, since they're part of the rotation being reused.
    func applyGameLog(_ log: GameLog) {
        revertToDraftIfFinalized()
        activeTeam.lineup = lineupFromGameLog(log)
        copiedFromGameOpponent = log.opponent.isEmpty ? "a past game" : "vs \(log.opponent)"
        Analytics.signal("history.lineup.applied", parameters: [
            "inningsPlayed": "\(log.inningsPlayed)"
        ])
        save()
    }

    /// True when the current game already has something worth warning about
    /// before a copy overwrites it. Drives whether the History screen shows the
    /// overwrite alert or copies straight through.
    var currentGameHasLineup: Bool {
        !activeTeam.lineup.battingOrder.isEmpty
            || activeTeam.lineup.innings.contains { !$0.assignments.isEmpty }
    }

    /// Builds — but does not apply — the Lineup an archived game maps onto for
    /// the active team's current roster and game length. Shared by
    /// applyGameLog and by TemplateLockEditorView, so the grid the coach picks
    /// locks from is exactly the grid applying the log would produce.
    func lineupFromGameLog(_ log: GameLog) -> Lineup {
        let activeIDs = Set(activeTeam.players.map { $0.id })
        var newLineup = Lineup()
        newLineup.gameDate = activeTeam.lineup.gameDate
        newLineup.opponent = activeTeam.lineup.opponent
        newLineup.battingOrder = log.battingOrder.filter { activeIDs.contains($0) }

        let inningCount = activeTeam.gameInningCount
        let preference = newLineup.battingOrder
        newLineup.innings = (0..<inningCount).map { index in
            guard index < log.innings.count else { return InningAssignment() }
            var assignment = InningAssignment()
            assignment.assignments = log.innings[index].assignments.filter { playerID, position in
                activeIDs.contains(playerID) && !position.isAbsent
            }
            // Archived grids are trusted but not guaranteed clean — normalize
            // so a duplicate in old data can't become a duplicate in today's game.
            return assignment.deduplicatingFieldingPositions(preferring: preference)
        }
        return newLineup
    }

    // MARK: - Team Management

    /// Creates a team and makes it active. Pass `gameInningCount` to set the
    /// game length as part of the same save — following it with
    /// `updateGameInningCount` costs a second full-team upload.
    func addTeam(name: String, color: Color = .blue, gameInningCount: Int? = nil) {
        var newTeam = Team()
        newTeam.name = name
        newTeam.color = color
        newTeam.coachName = UIDevice.current.name
        teams.append(newTeam)
        activeTeamID = newTeam.id
        if let gameInningCount {
            applyGameInningCount(gameInningCount, at: teams.count - 1)
        }
        Analytics.signal("team.created", parameters: ["teamCount": "\(teams.count)"])
        save()
    }

    // MARK: - Remote Deletions

    /// A team deleted on another device that this one still holds, waiting on
    /// the coach to say whether it should go here too.
    nonisolated struct PendingRemoteDeletion: Identifiable, Equatable {
        let teamID: UUID
        let teamName: String
        let recordName: String

        /// Keyed on the record, not the team — the record name is what CloudKit
        /// reported and what the declined ledger remembers.
        var id: String { recordName }

        var displayName: String { teamName.isEmpty ? "This team" : teamName }
    }

    /// What a batch of server-side deletions means for the teams held here.
    ///
    /// Pure and static so the rule can be tested without CloudKit: shared teams
    /// vanish, owned teams ask first, teams the coach already chose to keep stay
    /// quiet, and a record we don't recognise is ignored entirely.
    nonisolated static func classifyRemoteDeletions(
        recordNames: [String],
        teams: [Team],
        declined: Set<String>
    ) -> (autoRemove: [UUID], prompt: [PendingRemoteDeletion]) {
        var autoRemove: [UUID] = []
        var prompt: [PendingRemoteDeletion] = []

        for recordName in recordNames where !recordName.isEmpty {
            guard let team = teams.first(where: { $0.ckRecordName == recordName }) else { continue }

            if team.isReadOnly {
                autoRemove.append(team.id)
            } else if !declined.contains(recordName) {
                prompt.append(
                    PendingRemoteDeletion(
                        teamID: team.id,
                        teamName: team.name,
                        recordName: recordName
                    )
                )
            }
        }

        return (autoRemove, prompt)
    }

    /// Removes the team here too. The CKRecord is already gone — that's what
    /// started this — so there is nothing to delete server-side, only a
    /// tombstone to leave so it can't come back through the merge.
    func confirmRemoteDeletion(_ pending: PendingRemoteDeletion) {
        pendingRemoteDeletions.removeAll { $0.id == pending.id }
        guard teams.count > 1 else {
            // Never leave the coach with no team. Keep it and stop asking.
            declineRemoteDeletion(pending)
            return
        }
        teams.removeAll { $0.id == pending.teamID }
        if activeTeamID == pending.teamID {
            activeTeamID = teams.first?.id
        }
        tombstones.remember(teamID: pending.teamID, recordName: pending.recordName)
        Analytics.signal("team.remote_deletion.accepted")
        save()
    }

    /// Keeps the local copy. Remembered so the same deletion doesn't ask again
    /// on every fetch — a prompt that reappears is worse than no prompt.
    func declineRemoteDeletion(_ pending: PendingRemoteDeletion) {
        pendingRemoteDeletions.removeAll { $0.id == pending.id }
        declinedRemoteDeletions.insert(pending.recordName)
        Analytics.signal("team.remote_deletion.declined")
    }

    /// The CloudKit record this team's deletion should remove, or nil if none.
    ///
    /// THE NIL CASES ARE THE POINT. A shared team's record belongs to the coach
    /// who created it — deleting it would destroy their team and every other
    /// participant's copy, from a coach who only meant to leave. Leaving a
    /// shared team is a local removal and nothing more.
    ///
    /// Static and pure so `TeamTombstoneTests` can hold it to that without a
    /// CloudKit session.
    nonisolated static func recordNameToDelete(for team: Team) -> String? {
        guard !team.isReadOnly, !team.isSharedParticipant else { return nil }
        guard let recordName = team.ckRecordName, !recordName.isEmpty else { return nil }
        return recordName
    }

    func deleteTeam(id: UUID) {
        guard teams.count > 1 else { return }
        guard let team = teams.first(where: { $0.id == id }) else { return }

        let recordToDelete = Self.recordNameToDelete(for: team)

        teams.removeAll { $0.id == id }
        if activeTeamID == id {
            activeTeamID = teams.first?.id
        }

        // Remember the deletion before attempting it. The CKRecord outlived the
        // local delete until now, and `mergeCloudKitChanges` appends any server
        // team with no local match — so without this, a delete that fails
        // (offline, throttled) or a record another device re-uploads brings the
        // team straight back at the next sync.
        //
        // Recorded for shared teams too: leaving one shouldn't have it reappear
        // from the next shared-database fetch either.
        tombstones.remember(teamID: id, recordName: team.ckRecordName)

        if let recordToDelete {
            // Fire-and-forget: the local delete has already happened, and the
            // tombstone covers us if this never lands.
            Task {
                do {
                    try await CloudKitManager.shared.deleteTeam(recordName: recordToDelete)
                    Log.sync.info("Deleted team record from CloudKit")
                } catch {
                    Log.sync.error("Team record delete failed, tombstone holds: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // Drop this device's push token for the team we just left. Without it the
        // record stays in the public database and the Worker keeps finding it, so
        // a coach who leaves a shared team goes on receiving its notifications
        // forever. Fire-and-forget: the local delete has already happened and a
        // CloudKit failure here shouldn't block it.
        Task { await DeviceTokenManager.shared.removeTokens(for: id.uuidString) }

        Analytics.signal("team.deleted", parameters: ["remainingTeams": "\(teams.count)"])
        save()
    }

    func switchTeam(to id: UUID) {
        guard teams.contains(where: { $0.id == id }) else { return }
        activeTeamID = id
        let isSharedTeam = teams.first(where: { $0.id == id })?.isSharedParticipant ?? false

        // Tokens are otherwise only written by didRegister() at launch, so a team
        // created or joined mid-session has no token record until the next cold
        // start. No-ops when APNs hasn't handed us a token yet.
        DeviceTokenManager.shared.refreshTokenForCurrentTeam(store: self)

        Analytics.signal("team.switched", parameters: [
            "teamCount": "\(teams.count)",
            "shared": isSharedTeam ? "true" : "false"
        ])
        save()
    }

    // MARK: - Team File Import

    /// Replaces the active team's data with the imported snapshot.
    /// Keeps the existing team UUID so iCloud KV store references stay stable.
    /// Resets the active lineup to a fresh Lineup().
    func replaceActiveTeam(with snapshot: Team) {
        guard let idx = teams.firstIndex(where: { $0.id == activeTeamID }) else { return }
        var updated = snapshot
        updated.id = teams[idx].id
        updated.lineup = Lineup()
        teams[idx] = updated
        save()
    }

    /// Adds an imported team as a new entry, assigns a fresh UUID, and switches to it.
    /// Resets the active lineup to a fresh Lineup().
    func addImportedTeam(_ snapshot: Team) {
        var newTeam = snapshot
        newTeam.id = UUID()
        newTeam.lineup = Lineup()
        teams.append(newTeam)
        activeTeamID = newTeam.id
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

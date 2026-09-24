import XCTest
@testable import Lineup_Builder

// MARK: - Parity Fixture Writer
//
// Writes the fixtures the web app's TypeScript port is tested against
// (web/fixtures/parity/*.json), by running the REAL iOS engines on a fixed set
// of scenarios. The web tests then run their own engines on the same inputs
// and must agree. This is how "the web lineup follows the same rules as the
// app" stays true as either side changes.
//
// Two kinds of fixture:
//   * Exact: fair-play findings, pitch eligibility / coaches-guide pitch table,
//     and the deterministic Auto-Fill prompt parser. Same input, same output.
//   * Rules: Auto-Fill shuffles on purpose (two taps give two valid lineups),
//     so each scenario is filled many times and the fixture records what held
//     in EVERY run (invariants) and the distribution of each fairness metric.
//     The web port must never break an invariant, and its metric averages must
//     match within statistical tolerance.
//
// Skipped unless asked for, so normal test runs and CI never rewrite fixtures:
//
//   TEST_RUNNER_PARITY_WRITE=1 xcodebuild test -project "Lineup Builder.xcodeproj" \
//     -scheme "Lineup Builder" -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -only-testing:"Lineup BuilderTests/ParityFixtureWriter"
//
// Inputs are built from fixed UUIDs and a seeded generator so a re-run only
// changes the files when engine behavior changes. Names are the fake seeded
// roster; nothing here is real player data (the web repo is public).

@MainActor
final class ParityFixtureWriter: XCTestCase {

    /// Pitch rules are calendar-day based, so every fixture pins one zone.
    /// Fall Ball's last weekend straddles the Nov 1 2026 DST change on purpose.
    static let timeZoneID = "America/Los_Angeles"
    static let autoFillRuns = 500

    private var savedTimeZone: TimeZone!

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["PARITY_WRITE"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_PARITY_WRITE=1 to regenerate web parity fixtures.")
        }
        savedTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: Self.timeZoneID)!
        XCTAssertEqual(Calendar.current.timeZone.identifier, Self.timeZoneID,
                       "Calendar.current must follow the pinned zone or dates will drift")
    }

    override func tearDown() async throws {
        if let savedTimeZone { NSTimeZone.default = savedTimeZone }
    }

    // MARK: - Output

    private var outputDirectory: URL {
        // <repo>/Lineup BuilderTests/ParityFixtureWriter.swift -> <repo>/web/fixtures/parity
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("web/fixtures/parity", isDirectory: true)
    }

    private func write(_ name: String, _ body: [String: Any]) throws {
        var doc = body
        doc["generatedBy"] = "Lineup BuilderTests/ParityFixtureWriter.swift"
        doc["timeZone"] = Self.timeZoneID
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        let url = outputDirectory.appendingPathComponent(name)
        try data.write(to: url)
        print("PARITY wrote \(url.path) (\(data.count) bytes)")
    }

    // MARK: - Fixed inputs

    private static func pid(_ i: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012ld", i))!
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 18) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h
        return Calendar.current.date(from: c)!
    }

    /// The seeded demo roster (fake names) with stable ids.
    private static func demoRoster() -> [Player] {
        DebugDataSeeder.fakePlayers.enumerated().map { i, p in
            Player(id: pid(i + 1), firstName: p.firstName, lastName: p.lastName, number: p.number,
                   leagueAge: p.leagueAge, positionPreferences: p.positionPreferences)
        }
    }

    private static func plainRoster(_ count: Int, age: Int? = 10) -> [Player] {
        (1...count).map { i in
            Player(id: pid(100 + i), firstName: "P\(i)", lastName: "Test", number: "\(i)", leagueAge: age)
        }
    }

    private static func emptyLineup(_ players: [Player], innings: Int = 6) -> Lineup {
        Lineup(gameDate: date(2026, 10, 10), opponent: "Opponent A",
               battingOrder: players.map(\.id),
               innings: Array(repeating: InningAssignment(), count: innings))
    }

    // MARK: - Encoding (explicit, language-neutral: no Swift flat-array dictionaries)

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    private static func enc(_ p: Player) -> [String: Any] {
        var j: [String: Any] = [
            "id": p.id.uuidString, "firstName": p.firstName, "lastName": p.lastName, "number": p.number,
            "positionPreferences": Dictionary(uniqueKeysWithValues:
                p.positionPreferences.map { ($0.key.rawValue, $0.value.rawValue) }),
        ]
        if let age = p.leagueAge { j["leagueAge"] = age }
        return j
    }

    private static func enc(_ inning: InningAssignment) -> [String: String] {
        Dictionary(uniqueKeysWithValues: inning.assignments.map { ($0.key.uuidString, $0.value.rawValue) })
    }

    private static func enc(_ l: Lineup) -> [String: Any] {
        [
            "gameDate": iso.string(from: l.gameDate), "opponent": l.opponent,
            "battingOrder": l.battingOrder.map(\.uuidString),
            "innings": l.innings.map { enc($0) },
            "absentPlayerIDs": l.absentPlayerIDs.map(\.uuidString).sorted(),
            "status": l.status.rawValue,
        ]
    }

    private static func enc(_ c: FairPlayConfig) -> [String: Any] {
        [
            "noPitcher": c.noPitcher, "noCatcher": c.noCatcher, "outfielderCount": c.outfielderCount,
            "noConsecutiveBench": c.noConsecutiveBench, "noConsecutivePosition": c.noConsecutivePosition,
            "equalBenchTime": c.equalBenchTime, "noRepeatPositions": c.noRepeatPositions,
            "minimumFieldingInnings": c.minimumFieldingInnings,
            "minimumInfieldInnings": c.minimumInfieldInnings,
            "minimumOutfieldInnings": c.minimumOutfieldInnings,
            "catcherToPitcherThreshold": c.catcherToPitcherThreshold,
            "pitcherToCatcherThreshold": c.pitcherToCatcherThreshold,
            "leagueRuleset": c.leagueRuleset.rawValue,
        ]
    }

    private static func enc(_ l: PitchingLimits) -> [String: Any] {
        var j: [String: Any] = ["dailyMax": l.dailyMax, "restDay1Min": l.restDay1Min, "restDay2Min": l.restDay2Min]
        if let v = l.restDay3Min { j["restDay3Min"] = v }
        if let v = l.restDay4Min { j["restDay4Min"] = v }
        return j
    }

    private static func enc(_ c: PitchingConfig) -> [String: Any] {
        [
            "rulesEnabled": c.rulesEnabled,
            "ageLimits": Dictionary(uniqueKeysWithValues: c.ageLimits.map { ($0.key.rawValue, enc($0.value)) }),
            "weeklyLimitEnabled": c.weeklyLimitEnabled, "weeklyLimit": c.weeklyLimit,
            "rollingWindowType": c.rollingWindowType.rawValue, "rollingWindowDays": c.rollingWindowDays,
        ]
    }

    private static func enc(_ g: GameLog) -> [String: Any] {
        [
            "id": g.id.uuidString, "gameDate": iso.string(from: g.gameDate), "opponent": g.opponent,
            "inningsPlayed": g.inningsPlayed, "battingOrder": g.battingOrder.map(\.uuidString),
            "innings": g.innings.map { enc($0) }, "playerSnapshot": [] as [Any],
            "pitchCounts": g.pitchCounts, "archivedAt": iso.string(from: g.archivedAt),
            "archivedBy": g.archivedBy, "notes": g.notes,
        ]
    }

    private static func enc(_ s: PitchEligibilityStatus) -> [String: Any] {
        switch s {
        case .eligible: return ["kind": "eligible"]
        case .limited(let r): return ["kind": "limited", "remaining": r]
        case .mustRest(let d): return ["kind": "mustRest", "until": iso.string(from: d)]
        case .unknownAge: return ["kind": "unknownAge"]
        }
    }

    private static func enc(_ t: AutoFillConstraintTarget) -> [String: Any] {
        switch t {
        case .position(let p): return ["kind": "position", "position": p.rawValue]
        case .infield: return ["kind": "infield"]
        case .outfield: return ["kind": "outfield"]
        case .bench: return ["kind": "bench"]
        }
    }

    private static func enc(_ i: AutoFillConstraintIntent) -> String {
        switch i {
        case .assign: return "assign"
        case .avoid: return "avoid"
        case .prioritize: return "prioritize"
        }
    }

    private static func enc(_ c: AutoFillPlayerConstraint) -> [String: Any] {
        ["playerID": c.playerID.uuidString, "target": enc(c.target),
         "inningRange": [c.inningRange.lowerBound, c.inningRange.upperBound], "intent": enc(c.intent)]
    }

    private static func enc(_ r: AutoFillUnfilledReason) -> String {
        switch r {
        case .rosterTooSmall: return "rosterTooSmall"
        case .neverPreferences: return "neverPreferences"
        case .pitcherReentry: return "pitcherReentry"
        case .pitchCapacityLimited: return "pitchCapacityLimited"
        }
    }

    private static func enc(_ r: AutoFillConstraintOverrideReason) -> String {
        switch r {
        case .pitcherSoftCapBypassed: return "pitcherSoftCapBypassed"
        case .pitcherSoftCapBypassedByFallback: return "pitcherSoftCapBypassedByFallback"
        case .benchedOutOfTurn: return "benchedOutOfTurn"
        case .fairPlayZoneSkipped(let z):
            return z == .infield ? "fairPlayZoneSkipped.infield" : "fairPlayZoneSkipped.outfield"
        }
    }

    // MARK: - 1. Fair-play findings (exact)

    func testWriteFairPlayFixture() throws {
        var rng = SplitMix64(seed: 2026_09_24)
        let configs: [(String, FairPlayConfig)] = [
            ("default", FairPlayConfig()),
            ("nicksTeam", FairPlayConfig(noConsecutiveBench: true, equalBenchTime: true, noRepeatPositions: true,
                                         minimumFieldingInnings: 3, minimumInfieldInnings: 0, minimumOutfieldInnings: 0)),
            ("strictBattery", FairPlayConfig(minimumFieldingInnings: 5, catcherToPitcherThreshold: 1,
                                             pitcherToCatcherThreshold: 2)),
            ("rulesOff", FairPlayConfig(noConsecutiveBench: false, minimumFieldingInnings: 0,
                                        minimumInfieldInnings: 0, minimumOutfieldInnings: 0)),
            ("fourOutfieldNoPitcher", FairPlayConfig(noPitcher: true, outfielderCount: 4)),
        ]

        var scenarios: [[String: Any]] = []
        for n in 0..<24 {
            let roster = Self.plainRoster(9 + n % 5)
            let innings = [5, 6, 7][n % 3]
            var lineup = Self.emptyLineup(roster, innings: innings)
            if n % 4 == 3 { lineup.absentPlayerIDs = [roster[1].id] }
            let config = configs[n % configs.count].1
            let positions = lineup.activeFieldPositions(config: config)
            for i in 0..<innings {
                let order = roster.filter { !lineup.absentPlayerIDs.contains($0.id) }.shuffled(using: &rng)
                let spots = positions.shuffled(using: &rng)
                for (k, player) in order.enumerated() {
                    let roll = Int.random(in: 0..<100, using: &rng)
                    if roll < 6 { continue }                                   // left open
                    if roll < 9 { lineup.innings[i].assign(player: player, position: .absent); continue }
                    lineup.innings[i].assign(player: player, position: k < spots.count ? spots[k] : .bench)
                }
            }
            scenarios.append(fairPlayScenario("generated-\(n)-\(configs[n % configs.count].0)",
                                              roster, lineup, config))
        }

        // Hand-built edge cases.
        let r = Self.plainRoster(10)
        var b2b = Self.emptyLineup(r, innings: 6)
        let nine = FieldPosition.fieldPositions.filter { $0 != .leftCenterField && $0 != .rightCenterField }
        for i in 0..<6 {
            // Player 1 sits innings 3-4, player 2 sits 5-6, player 10 sits inning 1.
            let benched: Set<Int> = [i == 2 || i == 3 ? 0 : -1, i >= 4 ? 1 : -1, i == 0 ? 9 : -1]
            var spot = i
            for (k, p) in r.enumerated() {
                if benched.contains(k) { b2b.innings[i].assign(player: p, position: .bench); continue }
                if spot - i < nine.count { b2b.innings[i].assign(player: p, position: nine[spot % 9]) }
                else { b2b.innings[i].assign(player: p, position: .bench) }
                spot += 1
            }
        }
        scenarios.append(fairPlayScenario("edge-back-to-back-and-rotation", r, b2b, FairPlayConfig()))
        scenarios.append(fairPlayScenario("edge-empty-lineup", r, Self.emptyLineup(r), FairPlayConfig()))
        var battery = Self.emptyLineup(r, innings: 6)
        battery.innings[0].assign(player: r[0], position: .catcher)
        battery.innings[1].assign(player: r[0], position: .catcher)
        battery.innings[2].assign(player: r[0], position: .pitcher)
        battery.innings[0].assign(player: r[1], position: .pitcher)
        battery.innings[1].assign(player: r[1], position: .pitcher)
        battery.innings[3].assign(player: r[1], position: .catcher)
        scenarios.append(fairPlayScenario("edge-battery-transitions", r, battery,
                                          FairPlayConfig(catcherToPitcherThreshold: 2, pitcherToCatcherThreshold: 2)))
        var single = Self.emptyLineup(r, innings: 1)
        single.innings[0].assign(player: r[0], position: .bench)
        scenarios.append(fairPlayScenario("edge-one-inning", r, single, FairPlayConfig()))

        try write("fair-play.json", ["scenarios": scenarios])
    }

    private func fairPlayScenario(_ name: String, _ players: [Player], _ lineup: Lineup,
                                  _ config: FairPlayConfig) -> [String: Any] {
        let f = lineup.fairPlayFindings(players: players, config: config)
        let ids: ([Player]) -> [String] = { $0.map(\.id.uuidString) }
        var b2b: [String: [[Int]]] = [:]
        for p in players {
            let pairs = lineup.backToBackBenchInnings(player: p)
            if !pairs.isEmpty { b2b[p.id.uuidString] = pairs.map { [$0.first, $0.second] } }
        }
        return [
            "name": name,
            "players": players.map { Self.enc($0) }, "lineup": Self.enc(lineup), "config": Self.enc(config),
            "expected": [
                "activeFieldPositions": lineup.activeFieldPositions(config: config).map(\.rawValue),
                "openPositions": (0..<lineup.innings.count).map {
                    lineup.openPositions(inning: $0, players: players, config: config).map(\.rawValue)
                },
                "findings": [
                    "withoutInfield": ids(f.withoutInfield), "withoutOutfield": ids(f.withoutOutfield),
                    "underFieldingMinimum": ids(f.underFieldingMinimum),
                    "backToBackBench": ids(f.backToBackBench),
                    "catcherThenPitcher": ids(f.catcherThenPitcher),
                    "pitcherThenCatcher": ids(f.pitcherThenCatcher),
                    "minimumFieldingInnings": f.minimumFieldingInnings,
                    "implicatedPlayerIDs": f.implicatedPlayerIDs.map(\.uuidString).sorted(),
                ],
                "backToBackBenchInnings": b2b,
            ] as [String: Any],
        ]
    }

    // MARK: - 2. Pitch eligibility + coaches-guide table (exact)

    func testWritePitchEligibilityFixture() throws {
        let never = [FieldPosition.pitcher: PositionPreferenceTier.never]
        let players: [Player] = [
            Player(id: Self.pid(201), firstName: "Ace", lastName: "Adams", number: "1", leagueAge: 10),
            Player(id: Self.pid(202), firstName: "Ben", lastName: "Baker", number: "2", leagueAge: 12),
            Player(id: Self.pid(203), firstName: "Cal", lastName: "Cole", number: "3", leagueAge: 8),
            Player(id: Self.pid(204), firstName: "Dom", lastName: "Diaz", number: "4", leagueAge: 14),
            Player(id: Self.pid(205), firstName: "Eli", lastName: "Evans", number: "5", leagueAge: 16),
            Player(id: Self.pid(206), firstName: "Fin", lastName: "Ford", number: "6", leagueAge: nil),
            Player(id: Self.pid(207), firstName: "Gus", lastName: "Gray", number: "7", leagueAge: 17),
            Player(id: Self.pid(208), firstName: "Hal", lastName: "Hart", number: "8", leagueAge: 11,
                   positionPreferences: never),
            Player(id: Self.pid(209), firstName: "Ike", lastName: "Ives", number: "9", leagueAge: 10),
        ]
        func log(_ d: Date, _ counts: [(Int, Int)]) -> GameLog {
            GameLog(id: UUID(uuidString: String(format: "00000000-0000-4000-9000-%012ld",
                                                Int(d.timeIntervalSince1970) / 3600))!,
                    gameDate: d, opponent: "Opponent", inningsPlayed: 6, battingOrder: [], innings: [],
                    playerSnapshot: [], archivedAt: d,
                    pitchCounts: Dictionary(uniqueKeysWithValues: counts.map { (Self.pid($0.0).uuidString, $0.1) }))
        }
        let logs: [GameLog] = [
            log(Self.date(2026, 10, 17), [(201, 40), (202, 70), (204, 30)]),
            log(Self.date(2026, 10, 24), [(201, 55), (203, 30), (205, 80), (206, 45), (207, 60)]),
            log(Self.date(2026, 10, 27), [(202, 22), (209, 36)]),
            log(Self.date(2026, 10, 30), [(201, 20), (204, 66), (208, 25), (209, 50)]),
            log(Self.date(2026, 10, 31, 10), [(203, 21), (202, 41), (205, 31)]),
            log(Self.date(2026, 11, 1, 9), [(209, 15), (201, 1)]),     // DST day, morning game
        ]

        var ll = PitchingConfig(rulesEnabled: true); ll.applyLittleLeaguePreset()
        var weeklyRolling = ll; weeklyRolling.weeklyLimitEnabled = true; weeklyRolling.weeklyLimit = 100
        var weeklyCalendar = weeklyRolling; weeklyCalendar.rollingWindowType = .calendarWeek
        var shortWindow = weeklyRolling; shortWindow.rollingWindowDays = 3
        let configs: [(String, PitchingConfig)] = [
            ("rulesOff", PitchingConfig()), ("littleLeague", ll), ("weeklyRolling100", weeklyRolling),
            ("weeklyCalendar100", weeklyCalendar), ("rolling3Days", shortWindow),
        ]
        let referenceDates = [
            Self.date(2026, 10, 25, 12),          // Sunday (the old calendar-week bug day)
            Self.date(2026, 10, 26, 12),          // Monday
            Self.date(2026, 10, 31, 20),          // same day as a game (not counted yet)
            Self.date(2026, 11, 1, 23),           // DST change day, late
            Self.date(2026, 11, 2, 0),            // just after midnight, first day after DST
            Self.date(2026, 11, 4, 12),
        ]

        var scenarios: [[String: Any]] = []
        for (name, config) in configs {
            for ref in referenceDates {
                let statuses = PitchEligibilityEngine.compute(gameLogs: logs, players: players,
                                                              config: config, referenceDate: ref)
                let rows = PitchEligibilityEngine.pitchingSummaryRows(gameLogs: logs, players: players,
                                                                      config: config, referenceDate: ref)
                let guide = PitchEligibilityEngine.coachesGuideSummary(gameLogs: logs, players: players,
                                                                        config: config, referenceDate: ref)
                let row: (PitchingGuideSummaryRow) -> [String: Any] = { r in
                    ["playerID": r.player.id.uuidString, "pitchesInWindow": r.pitchesInWindow,
                     "dailyMax": r.dailyMax, "available": r.available,
                     "restDaysRequired": r.restDaysRequired, "status": Self.enc(r.status)]
                }
                var remaining: [String: Any] = [:]
                for p in players {
                    remaining[p.id.uuidString] = pitchesRemaining(for: p, gameLogs: logs, config: config,
                                                                   referenceDate: ref).map { $0 as Any } ?? NSNull()
                }
                scenarios.append([
                    "name": "\(name) @ \(Self.iso.string(from: ref))",
                    "config": Self.enc(config), "referenceDate": Self.iso.string(from: ref),
                    "expected": [
                        "statuses": statuses.mapKeysAndValues { ($0.uuidString, Self.enc($1)) },
                        "summaryRows": rows.map(row),
                        "coachesGuide": guide.map { $0.map(row) as Any } ?? NSNull(),
                        "pitchesRemaining": remaining,
                    ] as [String: Any],
                ])
            }
        }

        let weekStarts = (0..<16).map { Calendar.current.date(byAdding: .day, value: $0,
                                                              to: Self.date(2026, 10, 20, [0, 9, 23][$0 % 3]))! }.map {
            ["date": Self.iso.string(from: $0),
             "startOfPitchingWeek": Self.iso.string(from: PitchEligibilityEngine.startOfPitchingWeek(for: $0))]
        }

        try write("pitch-eligibility.json", [
            "players": players.map { Self.enc($0) }, "gameLogs": logs.map { Self.enc($0) },
            "scenarios": scenarios, "startOfPitchingWeek": weekStarts,
        ])
    }

    // MARK: - 3. Auto-Fill prompt parser (exact)

    func testWriteAutoFillParseFixture() throws {
        let roster = Self.demoRoster()
        var dupRoster = roster
        dupRoster[1] = Player(id: Self.pid(99), firstName: "Jake", lastName: "Other", number: "99", leagueAge: 11)

        let prompts = [
            // From AutoFillDeterministicParserTests / AutoFillNLPatternRuleTests / AutoFillCoordinatorTests
            "Jake at short", "Jake pitches and Owen catches", "Jake pitches the first 2 innings",
            "Jake starts on the bench then plays outfield", "Marcus, Drew and Eli play infield",
            "Nate starts on the bench", "Owen catches", "Sam pitches the first inning",
            "Tyler plays second base innings 3 to 5", "don't let Drew pitch", "everyone plays infield",
            "give the twins a breather up the middle", "keep Nate off pitcher",
            "Caleb pitches the first two innings", "Pitch Owen the first two innings",
            "Keep Zachary at catcher all game",
            "any player who sits must sit 2 consecutive innings", "Any player who sits, must sit 2 consecutive innings",
            "anyone who is benched sits two consecutive innings", "anyone who sits, benches the next one too",
            "have players sit two in a row", "have players sit two innings in a row", "double up the bench",
            "if a player sits one inning, have them sit the next too",
            "if someone sits, they sit the next inning as well", "enable bench pairing",
            "avoid back-to-back", "avoid sitting players back to back", "disable bench pairing",
            "don't sit anyone two innings in a row", "never sit a player consecutive innings",
            "Caleb plays two consecutive innings at shortstop",
            // Extra coverage
            "Leo plays left center field innings 2-4", "Cam catches innings 4 through 6",
            "keep Eli out of the infield", "Connor plays third", "Marcus pitches innings 5 and 6",
            "Drew rf 1-3", "Tyler ss first 3 innings", "Jake pitches the first 2 innings. Owen catches innings 1 to 3",
            "Nate starts on the bench\nLeo plays center field", "JAKE AT SHORT", "jake at 1b and connor at 2b",
            "Owen behind the plate innings 2-3", "Jake on the mound", "put Drew in the outfield all game",
            "Eli plays first base", "Cam plays right center", "Connor plays left field innings 1-6",
            "Jake pitches innings 7 to 9", "",
        ]

        func run(_ players: [Player], _ prompt: String, inningCount: Int) -> [String: Any] {
            let service = AutoFillNLConstraintService(activePlayers: players, inningCount: inningCount)
            let parse = service.parseDeterministically(prompt)
            let pattern = AutoFillNLConstraintService.detectedPatternRules(in: prompt)
            return [
                "prompt": prompt, "inningCount": inningCount,
                "expected": [
                    "constraints": parse.constraints.map { Self.enc($0) },
                    "hasUnresolvedInstruction": parse.hasUnresolvedInstruction,
                    "benchInConsecutivePairs": pattern.benchInConsecutivePairs,
                    "shouldTrustDeterministic": AutoFillCoordinator.shouldTrustDeterministic(
                        parse, patternDetected: pattern.benchInConsecutivePairs),
                ] as [String: Any],
            ]
        }

        var cases = prompts.map { run(roster, $0, inningCount: 6) }
        cases += ["Jake at short", "Jake pitches the first 2 innings"].map { run(dupRoster, $0, inningCount: 6) }
            .map { var c = $0; c["roster"] = "duplicateFirstNames"; return c }
        cases += ["Jake pitches the first 2 innings", "Tyler plays second base innings 3 to 5"]
            .map { run(roster, $0, inningCount: 4) }

        try write("autofill-parse.json", [
            "rosters": ["demo": roster.map { Self.enc($0) }, "duplicateFirstNames": dupRoster.map { Self.enc($0) }],
            "cases": cases.map { var c = $0; if c["roster"] == nil { c["roster"] = "demo" }; return c },
            "benchPairingConfirmationMessage": AutoFillNLConstraintService.benchPairingConfirmationMessage,
        ])
    }

    // MARK: - 4. Auto-Fill (rules)

    private enum Scope { case game, through(Int), inning(Int) }

    private struct AutoFillScenario {
        let name: String
        var players: [Player]
        var lineup: Lineup
        var config = FairPlayConfig()
        var pitching: PitchingConfig? = nil
        var gameLogs: [GameLog] = []
        var constraints = AutoFillConstraintSet.empty
        var scope = Scope.game
    }

    func testWriteAutoFillFixture() throws {
        let now = Date()
        let refDate = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
        var scenarios: [AutoFillScenario] = []
        let demo = Self.demoRoster()

        scenarios.append(.init(name: "demo-roster-defaults", players: demo, lineup: Self.emptyLineup(demo)))
        scenarios.append(.init(name: "twelve-plain-defaults", players: Self.plainRoster(12),
                               lineup: Self.emptyLineup(Self.plainRoster(12))))
        scenarios.append(.init(name: "thirteen-equal-bench", players: Self.plainRoster(13),
                               lineup: Self.emptyLineup(Self.plainRoster(13)),
                               config: FairPlayConfig(noConsecutiveBench: true, equalBenchTime: true)))
        scenarios.append(.init(name: "nicks-team-config", players: Self.plainRoster(12),
                               lineup: Self.emptyLineup(Self.plainRoster(12)),
                               config: FairPlayConfig(noConsecutiveBench: true, equalBenchTime: true, noRepeatPositions: true,
                                                      minimumFieldingInnings: 3, minimumInfieldInnings: 0,
                                                      minimumOutfieldInnings: 0)))
        scenarios.append(.init(name: "back-to-back-allowed", players: Self.plainRoster(12),
                               lineup: Self.emptyLineup(Self.plainRoster(12)),
                               config: FairPlayConfig(noConsecutiveBench: false)))
        scenarios.append(.init(name: "no-repeat-positions", players: Self.plainRoster(10),
                               lineup: Self.emptyLineup(Self.plainRoster(10), innings: 7),
                               config: FairPlayConfig(noRepeatPositions: true)))
        scenarios.append(.init(name: "coach-pitch-four-outfield", players: Self.plainRoster(12),
                               lineup: Self.emptyLineup(Self.plainRoster(12), innings: 5),
                               config: FairPlayConfig(noPitcher: true, outfielderCount: 4)))
        scenarios.append(.init(name: "short-roster-eight", players: Self.plainRoster(8),
                               lineup: Self.emptyLineup(Self.plainRoster(8))))

        var neverRoster = Self.plainRoster(11)
        for i in 0..<8 { neverRoster[i].positionPreferences[.pitcher] = .never }
        for i in 0..<5 { neverRoster[i].positionPreferences[.catcher] = .never }
        neverRoster[9].positionPreferences = [.firstBase: .never, .secondBase: .never, .thirdBase: .never,
                                              .shortstop: .never, .pitcher: .never, .catcher: .never]
        neverRoster[10].positionPreferences = [.shortstop: .strength, .pitcher: .capable, .leftField: .emergency]
        scenarios.append(.init(name: "never-preferences", players: neverRoster,
                               lineup: Self.emptyLineup(neverRoster)))

        var allNever = Self.plainRoster(10)
        for i in allNever.indices { allNever[i].positionPreferences[.pitcher] = .never }
        scenarios.append(.init(name: "nobody-can-pitch", players: allNever, lineup: Self.emptyLineup(allNever)))

        let lockedRoster = Self.plainRoster(12)
        var locked = Self.emptyLineup(lockedRoster)
        locked.innings[0].assign(player: lockedRoster[0], position: .pitcher)
        locked.innings[1].assign(player: lockedRoster[0], position: .pitcher)
        locked.innings[0].assign(player: lockedRoster[1], position: .catcher)
        locked.innings[2].assign(player: lockedRoster[2], position: .bench)
        locked.innings[3].assign(player: lockedRoster[2], position: .bench)
        locked.innings[4].assign(player: lockedRoster[3], position: .shortstop)
        scenarios.append(.init(name: "locked-cells", players: lockedRoster, lineup: locked))

        let absentRoster = Self.plainRoster(12)
        var absent = Self.emptyLineup(absentRoster)
        absent.absentPlayerIDs = [absentRoster[4].id, absentRoster[7].id]
        absent.battingOrder.removeAll { absent.absentPlayerIDs.contains($0) }
        scenarios.append(.init(name: "two-absent", players: absentRoster, lineup: absent))

        let partialRoster = Self.plainRoster(11)
        var partial = Self.emptyLineup(partialRoster)
        for (k, p) in partialRoster.prefix(9).enumerated() {
            partial.innings[0].assign(player: p, position: FieldPosition.fieldPositions
                .filter { $0 != .leftCenterField && $0 != .rightCenterField }[k])
        }
        partial.innings[0].assign(player: partialRoster[9], position: .bench)
        partial.innings[0].assign(player: partialRoster[10], position: .bench)
        scenarios.append(.init(name: "fill-through-inning-3", players: partialRoster, lineup: partial,
                               scope: .through(2)))
        scenarios.append(.init(name: "fill-single-inning-2", players: partialRoster, lineup: partial,
                               scope: .inning(1)))

        // Pitch-count capacity. Logs are relative to "now" because the engine
        // reads today's date internally; the fixture records the reference.
        let cal = Calendar.current
        var pitchRoster = Self.plainRoster(11, age: 10)
        pitchRoster[9].leagueAge = nil                       // no age: capacity unlimited
        var pc = PitchingConfig(rulesEnabled: true); pc.applyLittleLeaguePreset()
        pc.weeklyLimitEnabled = true; pc.weeklyLimit = 100
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: cal.startOfDay(for: refDate))!.addingTimeInterval(18 * 3600)
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: refDate))!.addingTimeInterval(18 * 3600)
        let recent = [
            GameLog(id: Self.pid(901), gameDate: twoDaysAgo, opponent: "Opponent", inningsPlayed: 6, battingOrder: [],
                    innings: [], playerSnapshot: [], archivedAt: twoDaysAgo,
                    pitchCounts: [pitchRoster[0].id.uuidString: 70, pitchRoster[1].id.uuidString: 95]),
            GameLog(id: Self.pid(902), gameDate: yesterday, opponent: "Opponent", inningsPlayed: 6, battingOrder: [],
                    innings: [], playerSnapshot: [], archivedAt: yesterday,
                    pitchCounts: [pitchRoster[2].id.uuidString: 60]),   // owes 3 rest days
        ]
        scenarios.append(.init(name: "pitch-capacity-weekly-100", players: pitchRoster,
                               lineup: Self.emptyLineup(pitchRoster), pitching: pc, gameLogs: recent))
        var pcNoWeekly = pc; pcNoWeekly.weeklyLimitEnabled = false
        scenarios.append(.init(name: "resting-pitcher-no-weekly-cap", players: pitchRoster,
                               lineup: Self.emptyLineup(pitchRoster), pitching: pcNoWeekly, gameLogs: recent))

        // Natural-language constraints, resolved by the deterministic parser.
        func parsed(_ prompt: String, _ players: [Player], innings: Int = 6) -> AutoFillConstraintSet {
            let service = AutoFillNLConstraintService(activePlayers: players, inningCount: innings)
            let (set, _) = AutoFillCoordinator.applyingPatternRuleSafetyNet(
                to: AutoFillConstraintSet(playerConstraints: service.parseDeterministically(prompt).constraints),
                prompt: prompt, diagnostic: nil)
            return set
        }
        scenarios.append(.init(name: "constraints-pitch-catch-bench", players: demo, lineup: Self.emptyLineup(demo),
                               constraints: parsed("Jake pitches the first 2 innings. Owen catches innings 1 to 3. Nate starts on the bench", demo)))
        scenarios.append(.init(name: "constraints-avoid-and-zone", players: demo, lineup: Self.emptyLineup(demo),
                               constraints: parsed("keep Eli out of the infield. don't let Drew pitch. put Connor in the outfield all game", demo)))
        scenarios.append(.init(name: "constraints-soft-cap-bypass", players: demo, lineup: Self.emptyLineup(demo),
                               constraints: parsed("Jake pitches innings 1 to 4", demo)))
        scenarios.append(.init(name: "pattern-bench-pairs", players: Self.plainRoster(13),
                               lineup: Self.emptyLineup(Self.plainRoster(13)),
                               constraints: parsed("have players sit two innings in a row", Self.plainRoster(13))))

        var out: [[String: Any]] = []
        for s in scenarios { out.append(autoFillFixture(s, referenceDate: refDate)) }
        try write("autofill.json", ["runs": Self.autoFillRuns, "scenarios": out])
    }

    private func fill(_ s: AutoFillScenario) -> AutoFillResult {
        let prefs = Dictionary(uniqueKeysWithValues: s.players.map { ($0.id, $0.positionPreferences) })
        switch s.scope {
        case .game:
            return AutoFillEngine.fillGame(in: s.lineup, players: s.players, preferences: prefs, config: s.config,
                                           pitchingConfig: s.pitching, gameLogs: s.gameLogs, constraints: s.constraints)
        case .through(let last):
            return AutoFillEngine.fillInnings(through: last, in: s.lineup, players: s.players, preferences: prefs,
                                              config: s.config, pitchingConfig: s.pitching, gameLogs: s.gameLogs,
                                              constraints: s.constraints)
        case .inning(let i):
            return AutoFillEngine.fillInning(i, in: s.lineup, players: s.players, preferences: prefs, config: s.config,
                                             pitchingConfig: s.pitching, gameLogs: s.gameLogs, constraints: s.constraints)
        }
    }

    private func autoFillFixture(_ s: AutoFillScenario, referenceDate: Date) -> [String: Any] {
        var held = Set(AutoFillRules.invariantNames)
        var broken: [String: Int] = [:]
        var samples: [String: [Int]] = [:]
        var unfilledOutcomes = Set<String>()
        var unfilledReasons = Set<String>()

        for _ in 0..<Self.autoFillRuns {
            let result = fill(s)
            let check = AutoFillRules.evaluate(scenario: s.players, before: s.lineup, after: result,
                                               config: s.config, pitching: s.pitching, gameLogs: s.gameLogs,
                                               constraints: s.constraints, filledInnings: filledRange(s),
                                               referenceDate: referenceDate)
            for name in check.violated { held.remove(name); broken[name, default: 0] += 1 }
            for (k, v) in check.metrics { samples[k, default: []].append(v) }
            for slot in result.unfilledSlots { unfilledReasons.insert(Self.enc(slot.reason)) }
            unfilledOutcomes.insert(result.unfilledSlots
                .map { "\($0.inningIndex):\($0.position.rawValue):\(Self.enc($0.reason))" }
                .sorted().joined(separator: ","))
        }
        if !broken.isEmpty { print("PARITY note: \(s.name) did not always hold \(broken)") }

        var scope: [String: Any]
        switch s.scope {
        case .game: scope = ["kind": "game"]
        case .through(let n): scope = ["kind": "through", "inning": n]
        case .inning(let n): scope = ["kind": "inning", "inning": n]
        }
        return [
            "name": s.name,
            "input": [
                "players": s.players.map { Self.enc($0) }, "lineup": Self.enc(s.lineup), "config": Self.enc(s.config),
                "pitchingConfig": s.pitching.map { Self.enc($0) as Any } ?? NSNull(), "gameLogs": s.gameLogs.map { Self.enc($0) },
                "constraints": s.constraints.playerConstraints.map { Self.enc($0) },
                "patternRules": ["benchInConsecutivePairs": s.constraints.patternRules.benchInConsecutivePairs],
                "scope": scope, "referenceDate": Self.iso.string(from: referenceDate),
            ] as [String: Any],
            "invariants": held.sorted(),
            "notAlwaysHeld": broken,
            "metrics": samples.mapValues { Self.distribution($0) },
            "unfilledOutcomes": unfilledOutcomes.sorted(),
            "unfilledReasons": unfilledReasons.sorted(),
        ]
    }

    /// min/max plus mean, standard deviation and a histogram, so the web side
    /// can compare distributions instead of treating a rare tail it happens to
    /// hit (and iOS happened not to, in 500 runs) as a failure.
    private static func distribution(_ values: [Int]) -> [String: Any] {
        let n = Double(values.count)
        let mean = values.reduce(0.0) { $0 + Double($1) } / n
        let variance = values.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / n
        var counts: [String: Int] = [:]
        for v in values { counts[String(v), default: 0] += 1 }
        return ["min": values.min() ?? 0, "max": values.max() ?? 0,
                "mean": (mean * 10_000).rounded() / 10_000, "sd": (sqrt(variance) * 10_000).rounded() / 10_000,
                "counts": counts]
    }

    private func filledRange(_ s: AutoFillScenario) -> ClosedRange<Int> {
        switch s.scope {
        case .game: return 0...(s.lineup.innings.count - 1)
        case .through(let n): return 0...n
        case .inning(let n): return n...n
        }
    }
}

// MARK: - Rules checked on every Auto-Fill run
//
// The web port implements the same checks from these names (see
// web/src/core/parity/autofillRules.ts). Keep the two in step.

@MainActor
enum AutoFillRules {
    static let invariantNames = [
        "lockedCellsUnchanged",       // coach assignments are never touched
        "noDuplicateFielders",        // one player per fielding position per inning
        "neverPreferenceRespected",   // Auto-Fill never places a player at a Never position
        "absentPlayersUntouched",     // absent players get no new assignments
        "onlyActivePositions",        // no P when coach-pitch, no LCF/RCF with 3 OF, etc.
        "pitcherReentryRespected",    // once off the mound, never auto-placed back on it
        "everyActivePlayerPlaced",    // each active player is on the field or bench in every filled inning
        "pitchCapacityRespected",     // auto P innings never push past pitches-remaining / 20
        "avoidConstraintsRespected",  // an "avoid" instruction is never auto-violated
    ]

    struct Check { var violated: Set<String> = []; var metrics: [String: Int] = [:] }

    static func evaluate(scenario players: [Player], before: Lineup, after result: AutoFillResult,
                         config: FairPlayConfig, pitching: PitchingConfig?, gameLogs: [GameLog],
                         constraints: AutoFillConstraintSet, filledInnings: ClosedRange<Int>,
                         referenceDate: Date) -> Check {
        var c = Check()
        let after = result.lineup
        let active = after.activePlayers(from: players)
        let activePositions = Set(after.activeFieldPositions(config: config))
        func pos(_ l: Lineup, _ i: Int, _ p: Player) -> FieldPosition? { l.innings[i].position(for: p) }
        func isAuto(_ i: Int, _ p: Player) -> Bool { pos(before, i, p) == nil && pos(after, i, p) != nil }

        for i in after.innings.indices {
            for p in players {
                if let b = pos(before, i, p), pos(after, i, p) != b { c.violated.insert("lockedCellsUnchanged") }
                if before.absentPlayerIDs.contains(p.id), isAuto(i, p) { c.violated.insert("absentPlayersUntouched") }
                guard isAuto(i, p), let a = pos(after, i, p) else { continue }
                if p.positionPreferences[a] == .never { c.violated.insert("neverPreferenceRespected") }
                if !a.isNonFielding && !activePositions.contains(a) { c.violated.insert("onlyActivePositions") }
                for k in constraints.constraints(for: i) where k.playerID == p.id && k.intent == .avoid {
                    let hit: Bool
                    switch k.target {
                    case .position(let t): hit = a == t
                    case .infield: hit = a.isInfield
                    case .outfield: hit = a.isOutfield
                    case .bench: hit = false
                    }
                    if hit { c.violated.insert("avoidConstraintsRespected") }
                }
            }
            let fielding = after.innings[i].assignments.values.filter { !$0.isNonFielding }
            if Set(fielding).count != fielding.count { c.violated.insert("noDuplicateFielders") }
        }

        for i in filledInnings where !active.isEmpty {
            if active.contains(where: { pos(after, i, $0) == nil }) { c.violated.insert("everyActivePlayerPlaced") }
        }

        for p in players {
            var pitchedAt: Int? = nil
            for i in after.innings.indices {
                let a = pos(after, i, p)
                if a == .pitcher {
                    if let last = pitchedAt,
                       (last + 1..<i).contains(where: { j in
                           guard let q = pos(after, j, p) else { return false }
                           return !q.isNonFielding && q != .pitcher }),
                       isAuto(i, p) {
                        c.violated.insert("pitcherReentryRespected")
                    }
                    pitchedAt = i
                }
            }
            if let pc = pitching, pc.rulesEnabled,
               let remaining = pitchesRemaining(for: p, gameLogs: gameLogs, config: pc, referenceDate: referenceDate) {
                let capacity = remaining / 20
                let autoP = after.innings.indices.filter { isAuto($0, p) && pos(after, $0, p) == .pitcher }.count
                let totalP = after.innings.indices.filter { pos(after, $0, p) == .pitcher }.count
                if autoP > 0 && totalP > capacity { c.violated.insert("pitchCapacityRespected") }
            }
        }

        // Fairness metrics over the filled innings.
        let inRange = Array(filledInnings)
        let bench = active.map { p in inRange.filter { pos(after, $0, p) == .bench }.count }
        let f = after.fairPlayFindings(players: players, config: config)
        var pitcherInnings: [UUID: Int] = [:]
        for i in after.innings.indices {
            for (id, a) in after.innings[i].assignments where a == .pitcher { pitcherInnings[id, default: 0] += 1 }
        }
        var repeats = 0
        for p in active {
            let played = after.innings.compactMap { $0.position(for: p) }.filter { !$0.isNonFielding }
            repeats += played.count - Set(played).count
        }
        var blockedPitcherInnings = 0
        if let pc = pitching, pc.rulesEnabled {
            for p in players where PitchEligibilityEngine.status(for: p, gameLogs: gameLogs, config: pc,
                                                                  referenceDate: referenceDate).blocksAssignment {
                blockedPitcherInnings += after.innings.indices.filter { isAuto($0, p) && pos(after, $0, p) == .pitcher }.count
            }
        }
        var overrideCounts: [String: Int] = [:]
        for o in result.constraintOverrides {
            let key: String
            switch o.reason {
            case .pitcherSoftCapBypassed: key = "pitcherSoftCapBypassed"
            case .pitcherSoftCapBypassedByFallback: key = "pitcherSoftCapBypassedByFallback"
            case .benchedOutOfTurn: key = "benchedOutOfTurn"
            case .fairPlayZoneSkipped(let z): key = z == .infield ? "fairPlayZoneSkipped.infield" : "fairPlayZoneSkipped.outfield"
            }
            overrideCounts[key, default: 0] += 1
        }

        c.metrics = [
            "filledCount": result.filledCount,
            "unfilledCount": result.unfilledSlots.count,
            "benchSpread": (bench.max() ?? 0) - (bench.min() ?? 0),
            "maxBenchInnings": bench.max() ?? 0,
            "backToBackBenchPlayers": after.playersWithBackToBackBench(from: players).count,
            "playersWithoutInfield": after.playersWithoutInfield(players: active).count,
            "playersWithoutOutfield": after.playersWithoutOutfield(players: active).count,
            "playersUnderFieldingMinimum": config.minimumFieldingInnings > 0
                ? after.playersUnderFieldingMinimum(players: active, minimumInnings: config.minimumFieldingInnings).count : 0,
            "implicatedPlayers": f.implicatedPlayerIDs.count,
            "repeatPositions": repeats,
            "distinctPitchers": pitcherInnings.count,
            "maxPitcherInnings": pitcherInnings.values.max() ?? 0,
            "blockedPitcherInnings": blockedPitcherInnings,
            "constraintRejections": result.constraintRejections.count,
            "overrides.pitcherSoftCapBypassed": overrideCounts["pitcherSoftCapBypassed"] ?? 0,
            "overrides.pitcherSoftCapBypassedByFallback": overrideCounts["pitcherSoftCapBypassedByFallback"] ?? 0,
            "overrides.benchedOutOfTurn": overrideCounts["benchedOutOfTurn"] ?? 0,
            "overrides.fairPlayZoneSkipped.infield": overrideCounts["fairPlayZoneSkipped.infield"] ?? 0,
            "overrides.fairPlayZoneSkipped.outfield": overrideCounts["fairPlayZoneSkipped.outfield"] ?? 0,
        ]
        return c
    }
}

// MARK: - Helpers

/// Seeded generator for building fixture INPUTS reproducibly. The engines under
/// test keep using the system generator.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension Dictionary {
    func mapKeysAndValues<K: Hashable, V>(_ transform: (Key, Value) -> (K, V)) -> [K: V] {
        Dictionary<K, V>(uniqueKeysWithValues: map(transform))
    }
}

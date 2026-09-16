import XCTest
@testable import Lineup_Builder

// MARK: - HittingArchetypeTests
//
// HittingArchetype is a new optional field on Player. It rides the same JSON
// blob that TeamStorage persists and CloudKit syncs to coaches on other builds,
// so the failure that matters here isn't a wrong pill in the UI — it's a schema
// change that makes a whole shared roster fail to decode on someone else's
// phone. These pin the two properties that prevent that: the field is tolerant
// (an unknown/renamed axis value decodes to nil for that axis instead of
// throwing), and it is additive (a Player encoded by a build that never had the
// field still decodes, with the archetype defaulting to nil).

final class HittingArchetypeTests: XCTestCase {

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - isEmpty

    func testEmptyArchetypeReportsEmpty() {
        XCTAssertTrue(HittingArchetype().isEmpty)
    }

    func testAnySingleAxisMakesItNonEmpty() {
        XCTAssertFalse(HittingArchetype(hitting: .power).isEmpty)
        XCTAssertFalse(HittingArchetype(speed: .fast).isEmpty)
        XCTAssertFalse(HittingArchetype(onBase: .high).isEmpty)
    }

    // MARK: - Codable round-trip

    func testRoundTripAllAxes() throws {
        let original = HittingArchetype(hitting: .gap, speed: .medium, onBase: .high)
        XCTAssertEqual(try roundTrip(original), original)
    }

    func testRoundTripPartialAxesKeepsNilsNil() throws {
        let original = HittingArchetype(hitting: .singles)
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.speed)
        XCTAssertNil(decoded.onBase)
    }

    // MARK: - Tolerant decode

    /// An unknown or renamed raw value on any one axis decodes as nil for that
    /// axis — it must not throw and take the whole Player (and roster) down.
    func testUnknownAxisRawValueDecodesToNilNotThrow() throws {
        let json = Data("""
        { "hitting": "Power", "speed": "Blazing", "onBase": "High" }
        """.utf8)
        let decoded = try JSONDecoder().decode(HittingArchetype.self, from: json)
        XCTAssertEqual(decoded.hitting, .power)
        XCTAssertNil(decoded.speed, "unknown speed raw value should decode as nil")
        XCTAssertEqual(decoded.onBase, .high)
    }

    func testEmptyObjectDecodesToEmptyArchetype() throws {
        let decoded = try JSONDecoder().decode(HittingArchetype.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.isEmpty)
    }

    // MARK: - Player compatibility

    /// A Player written by a build that predates the field has no
    /// `hittingArchetype` key. It must still decode, defaulting the field to nil.
    func testPlayerWithoutArchetypeKeyStillDecodes() throws {
        let json = Data("""
        {
          "id": "\(UUID().uuidString)",
          "firstName": "Bobby",
          "lastName": "Reyes",
          "number": "7"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(Player.self, from: json)
        XCTAssertNil(decoded.hittingArchetype)
        XCTAssertEqual(decoded.firstName, "Bobby")
    }

    func testPlayerWithArchetypeRoundTrips() throws {
        var player = Player(firstName: "Caleb", lastName: "Ortiz", number: "12")
        player.hittingArchetype = HittingArchetype(hitting: .power, speed: .fast, onBase: .medium)
        XCTAssertEqual(try roundTrip(player).hittingArchetype, player.hittingArchetype)
    }

    // MARK: - Shared-team / CloudKit blob

    /// The whole [Team] blob is what TeamStorage serializes and CloudKit syncs.
    /// The archetype must survive that round-trip so a shared roster carries it
    /// to the other coach intact.
    func testTeamBlobRoundTripPreservesArchetype() throws {
        var player = Player(firstName: "Dee", lastName: "Kim", number: "3")
        player.hittingArchetype = HittingArchetype(speed: .slow, onBase: .low)
        let team = Team(id: UUID(), name: "Tigers", players: [player])

        let data = try JSONEncoder().encode([team])
        let decoded = try JSONDecoder().decode([Team].self, from: data)
        XCTAssertEqual(decoded.first?.players.first?.hittingArchetype,
                       HittingArchetype(speed: .slow, onBase: .low))
    }

    // MARK: - CloudKit sync contract
    //
    // A shared team syncs as ONE JSON blob per team: CloudKitManager.encodeTeam
    // does `JSONEncoder().encode(team)` into a CKAsset, and decodeTeam reads it
    // back with `JSONDecoder().decode(Team.self, ...)` (CloudKitManager.swift).
    // So cross-build compatibility for the new field is entirely governed by
    // that single-Team encode/decode with a lenient decoder. These pin that
    // exact boundary, so a future change (a custom Player CodingKeys that omits
    // the field, a stricter decoder) fails here rather than silently on a coach's
    // phone. They mirror the CloudKit path directly — one Team, not the [Team]
    // array TeamStorage uses.

    /// New build → new build over CloudKit: the archetype survives the
    /// single-Team blob the CKAsset carries.
    func testCloudKitSingleTeamBlobPreservesArchetype() throws {
        var player = Player(firstName: "Sam", lastName: "Vega", number: "21")
        player.hittingArchetype = HittingArchetype(hitting: .gap, speed: .fast, onBase: .high)
        let team = Team(id: UUID(), name: "Hawks", players: [player])

        // Exactly what encodeTeam/decodeTeam do (minus the CKAsset file wrapper).
        let data = try JSONEncoder().encode(team)
        let decoded = try JSONDecoder().decode(Team.self, from: data)
        XCTAssertEqual(decoded.players.first?.hittingArchetype,
                       HittingArchetype(hitting: .gap, speed: .fast, onBase: .high))
    }

    /// Older build → newer build: a team blob written before the field existed
    /// decodes cleanly, archetype nil. (A minimal Team object stands in for the
    /// older schema — Team.init(from:) defaults every absent field.)
    func testCloudKitTeamBlobWithoutArchetypeDecodes() throws {
        let json = Data("""
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy Team",
          "players": [
            { "id": "\(UUID().uuidString)", "firstName": "Old", "lastName": "Timer", "number": "1" }
          ]
        }
        """.utf8)
        let team = try JSONDecoder().decode(Team.self, from: json)
        XCTAssertEqual(team.name, "Legacy Team")
        XCTAssertNil(team.players.first?.hittingArchetype)
    }

    /// Newer build → older build (the data-safety case): the reason a shared
    /// roster can't break decode on a coach who hasn't updated is that
    /// JSONDecoder ignores keys it doesn't know. An unknown future key inside a
    /// player object must not fail the whole Team decode.
    func testCloudKitTeamBlobWithUnknownPlayerKeyStillDecodes() throws {
        var player = Player(firstName: "Fwd", lastName: "Compat", number: "9")
        player.hittingArchetype = HittingArchetype(hitting: .power)
        let team = Team(id: UUID(), name: "Falcons", players: [player])

        // Round-trip through a mutable JSON object and inject a key no build
        // knows yet, simulating a blob written by a *newer* build than the reader.
        let data = try JSONEncoder().encode(team)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var players = try XCTUnwrap(object["players"] as? [[String: Any]])
        players[0]["someFutureField_v99"] = "ignore me"
        object["players"] = players
        let mutated = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Team.self, from: mutated)
        XCTAssertEqual(decoded.players.first?.firstName, "Fwd",
                       "an unknown future key must not break the roster decode")
        XCTAssertEqual(decoded.players.first?.hittingArchetype, HittingArchetype(hitting: .power))
    }
}

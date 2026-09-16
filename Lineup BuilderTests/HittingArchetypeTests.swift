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
}

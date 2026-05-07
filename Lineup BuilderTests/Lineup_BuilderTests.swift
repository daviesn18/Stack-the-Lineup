import XCTest
@testable import Lineup_Builder

// MARK: - Test Suite Index
//
// Tests have been split into focused files. Add this file's target to each:
//
//   DataIntegrityTests.swift      — Encode/decode safety across all schema versions.
//                                   Covers Lineup, Team, FairPlayConfig, FieldPosition,
//                                   Player, and corrupt data handling.
//
//   FairPlayValidationTests.swift — Lineup validation engine. Covers activeFieldPositions,
//                                   openPositions (config-aware), playersWithoutInfield/
//                                   Outfield, playersUnderFieldingMinimum,
//                                   playersWithBackToBackBench, and both battery
//                                   restriction validators (C-to-P, P-to-C).
//
//   AutoFillEngineTests.swift     — AutoFillEngine position assignment. Covers noPitcher,
//                                   noCatcher, outfielderCount (3 vs 4), combined
//                                   restrictions, pre-existing assignment preservation,
//                                   and fillInnings / fillGame multi-inning passes.
//
//   LineupStoreTests.swift        — LineupStore mutation methods. Covers updateFairPlayConfig
//                                   (correct team, isolation, unknown ID no-op), config
//                                   passthrough, inning count resizing, player CRUD,
//                                   multi-team isolation, and clearPositions behavior.

import AppIntents

// MARK: - FieldPositionAppEnum
//
// The App Intents face of `FieldPosition`.
//
// Deliberately a wrapper rather than an `AppEnum` conformance on FieldPosition
// itself. Models.swift and AutoFillEngine.swift stay framework-independent —
// they are pure value types the widget target and the unit tests both compile
// against, and dragging AppIntents into that layer would spread a UI-framework
// dependency across the whole model.
//
// The mapping is total in both directions. That is load-bearing: the exhaustive
// switch means adding a position to FieldPosition fails the build here until
// it's given a spoken name, instead of silently becoming unaddressable by voice.

nonisolated enum FieldPositionAppEnum: String, AppEnum, CaseIterable {
    case pitcher
    case catcher
    case firstBase
    case secondBase
    case thirdBase
    case shortstop
    case leftField
    case leftCenterField
    case centerField
    case rightCenterField
    case rightField
    case bench
    case absent

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Position")

    // Siri matches spoken input against these titles. Synonyms carry the shorthand
    // a coach actually says out loud — "short", "first", "left" — which the formal
    // display names in Models.swift don't cover.
    static let caseDisplayRepresentations: [FieldPositionAppEnum: DisplayRepresentation] = [
        .pitcher:          DisplayRepresentation(title: "Pitcher",      synonyms: ["P", "pitching"]),
        .catcher:          DisplayRepresentation(title: "Catcher",      synonyms: ["C", "catching"]),
        .firstBase:        DisplayRepresentation(title: "1st Base",     synonyms: ["first base", "first", "1B"]),
        .secondBase:       DisplayRepresentation(title: "2nd Base",     synonyms: ["second base", "second", "2B"]),
        .thirdBase:        DisplayRepresentation(title: "3rd Base",     synonyms: ["third base", "third", "3B"]),
        .shortstop:        DisplayRepresentation(title: "Shortstop",    synonyms: ["short", "SS"]),
        .leftField:        DisplayRepresentation(title: "Left Field",   synonyms: ["left", "LF"]),
        .leftCenterField:  DisplayRepresentation(title: "Left Center",  synonyms: ["left center field", "LCF"]),
        .centerField:      DisplayRepresentation(title: "Center Field", synonyms: ["center", "CF"]),
        .rightCenterField: DisplayRepresentation(title: "Right Center", synonyms: ["right center field", "RCF"]),
        .rightField:       DisplayRepresentation(title: "Right Field",  synonyms: ["right", "RF"]),
        .bench:            DisplayRepresentation(title: "Bench",        synonyms: ["sitting", "benched"]),
        .absent:           DisplayRepresentation(title: "Absent",       synonyms: ["out", "not here"]),
    ]

    // MARK: - Bridge

    init(_ position: FieldPosition) {
        switch position {
        case .pitcher:          self = .pitcher
        case .catcher:          self = .catcher
        case .firstBase:        self = .firstBase
        case .secondBase:       self = .secondBase
        case .thirdBase:        self = .thirdBase
        case .shortstop:        self = .shortstop
        case .leftField:        self = .leftField
        case .leftCenterField:  self = .leftCenterField
        case .centerField:      self = .centerField
        case .rightCenterField: self = .rightCenterField
        case .rightField:       self = .rightField
        case .bench:            self = .bench
        case .absent:           self = .absent
        }
    }

    var fieldPosition: FieldPosition {
        switch self {
        case .pitcher:          return .pitcher
        case .catcher:          return .catcher
        case .firstBase:        return .firstBase
        case .secondBase:       return .secondBase
        case .thirdBase:        return .thirdBase
        case .shortstop:        return .shortstop
        case .leftField:        return .leftField
        case .leftCenterField:  return .leftCenterField
        case .centerField:      return .centerField
        case .rightCenterField: return .rightCenterField
        case .rightField:       return .rightField
        case .bench:            return .bench
        case .absent:           return .absent
        }
    }

    /// Plain-text name, for Spotlight keywords and dialog strings that build a
    /// sentence rather than presenting a picker.
    var displayName: String { fieldPosition.displayName }
}

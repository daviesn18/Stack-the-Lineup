import SwiftUI

// MARK: - Fair Play Rules View
//
// Per-team fair play rule configuration. Accessed from TeamFormView (Edit Team sheet).
// Reads the current team's FairPlayConfig on appear, writes back on Save.
// Organised into four sections matching the FairPlayConfig property groups:
//   1. Position Restrictions  (noPitcher, noCatcher, outfielderCount)
//   2. Bench Rules            (noConsecutiveBench, equalBenchTime)
//   3. Fielding Minimums      (minimumFieldingInnings, minimumInfieldInnings, minimumOutfieldInnings)
//   4. Battery Restrictions   (catcherToPitcherThreshold, pitcherToCatcherThreshold)
//
// noConsecutivePosition is wired up in the model but kept off the UI for v2.4 —
// the validation and AutoFill engine work for it ships in a later pass.

struct FairPlayRulesView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let teamID: UUID

    // Local working copy — only written back on Save
    @State private var config: FairPlayConfig = FairPlayConfig()

    /// True when every rule is in its disabled/off state.
    private var allRulesOff: Bool {
        !config.noPitcher
        && !config.noCatcher
        && config.outfielderCount == 3
        && !config.noConsecutiveBench
        && !config.equalBenchTime
        && config.minimumFieldingInnings == 0
        && config.minimumInfieldInnings == 0
        && config.minimumOutfieldInnings == 0
        && config.catcherToPitcherThreshold == 0
        && config.pitcherToCatcherThreshold == 0
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                allRulesSection
                positionRestrictionsSection
                benchRulesSection
                fieldingMinimumsSection
                batteryRestrictionsSection
                resetSection
            }
            .navigationTitle("Fair Play Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                if let team = store.teams.first(where: { $0.id == teamID }) {
                    config = team.fairPlayConfig
                }
            }
        }
    }

    // MARK: - Sections

    private var allRulesSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { !allRulesOff },
                set: { enabled in
                    if enabled {
                        config = FairPlayConfig()
                    } else {
                        config = FairPlayConfig(
                            noPitcher: false,
                            noCatcher: false,
                            outfielderCount: 3,
                            noConsecutiveBench: false,
                            noConsecutivePosition: false,
                            equalBenchTime: false,
                            minimumFieldingInnings: 0,
                            minimumInfieldInnings: 0,
                            minimumOutfieldInnings: 0,
                            catcherToPitcherThreshold: 0,
                            pitcherToCatcherThreshold: 0
                        )
                    }
                }
            )) {
                Text("Fair Play Rules Enabled")
            }
        } footer: {
            Text("Turn off to disable all fair play rules for this team. Individual rules can still be configured below.")
        }
    }

    private var positionRestrictionsSection: some View {
        Section {
            Toggle("No Pitcher", isOn: $config.noPitcher)
            Toggle("No Catcher", isOn: $config.noCatcher)

            Picker("Outfielders", selection: $config.outfielderCount) {
                Text("3 (LF / CF / RF)").tag(3)
                Text("4 (LF / LCF / RCF / RF)").tag(4)
            }
        } header: {
            Text("Position Restrictions")
        } footer: {
            Text("Restricted positions are removed from the field entirely. Auto-Fill will not assign them, and they won't appear as open slots.")
        }
    }

    private var benchRulesSection: some View {
        Section {
            Toggle("No Back-to-Back Bench", isOn: $config.noConsecutiveBench)
            Toggle("Equal Bench Time", isOn: $config.equalBenchTime)
        } header: {
            Text("Bench Rules")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if config.noConsecutiveBench {
                    Text("No player can sit bench two innings in a row. A warning fires if this happens.")
                }
                if config.equalBenchTime {
                    Text("No player sits bench twice until every player has sat once.")
                }
            }
        }
    }

    private var fieldingMinimumsSection: some View {
        Section {
            InningMinimumRow(
                label: "Min. Innings Fielded",
                value: $config.minimumFieldingInnings,
                range: 0...9,
                zeroLabel: "Off"
            )
            InningMinimumRow(
                label: "Min. Infield Innings",
                value: $config.minimumInfieldInnings,
                range: 0...9,
                zeroLabel: "Off"
            )
            InningMinimumRow(
                label: "Min. Outfield Innings",
                value: $config.minimumOutfieldInnings,
                range: 0...9,
                zeroLabel: "Off"
            )
        } header: {
            Text("Fielding Minimums")
        } footer: {
            Text("Set to Off to disable a minimum. Warnings fire when all innings are fully planned and a player falls short.")
        }
    }

    private var batteryRestrictionsSection: some View {
        Section {
            InningMinimumRow(
                label: "Catcher to Pitcher",
                value: $config.catcherToPitcherThreshold,
                range: 0...9,
                zeroLabel: "Off"
            )
            InningMinimumRow(
                label: "Pitcher to Catcher",
                value: $config.pitcherToCatcherThreshold,
                range: 0...9,
                zeroLabel: "Off"
            )
        } header: {
            Text("Battery Restrictions")
        } footer: {
            Text("Catcher to Pitcher: a player who caught this many innings cannot pitch. Pitcher to Catcher: a player who pitched this many innings cannot catch. Set to Off to disable.")
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                withAnimation { config = FairPlayConfig() }
            } label: {
                HStack {
                    Spacer()
                    Text("Reset to Defaults")
                    Spacer()
                }
            }
        } footer: {
            Text("Defaults: No Back-to-Back Bench on, 4 innings fielded minimum, 1 infield and 1 outfield minimum, all other rules off.")
        }
    }

    // MARK: - Save

    private func save() {
        store.updateFairPlayConfig(config, for: teamID)
        dismiss()
    }
}

// MARK: - Inning Minimum Row
//
// Stepper-style row for Int values with a defined range.
// Displays "Off" when value == 0 (zeroLabel) instead of "0".

struct InningMinimumRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let zeroLabel: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 12) {
                Button {
                    if value > range.lowerBound { value -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(value > range.lowerBound ? .blue : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Text(value == 0 ? zeroLabel : "\(value)")
                    .font(.body.monospacedDigit())
                    .foregroundColor(value == 0 ? .secondary : .primary)
                    .frame(minWidth: 28, alignment: .center)

                Button {
                    if value < range.upperBound { value += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(value < range.upperBound ? .blue : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

import SwiftUI

// MARK: - Pitching Rules View
//
// Per-team pitch count rule configuration. Accessed from TeamFormView (Edit Team sheet),
// listed alongside Fair Play Rules in the Game Settings section.
//
// Reads the current team's PitchingConfig on appear, writes back on Save.
//
// Sections:
//   1. Master toggle
//   2. Weekly cap — includes window type picker (controls when cap resets)
//   3. Age bracket limits — one accordion row per bracket
//   4. Preset / Reset
//
// The Little League preset seeds all age bracket fields as a starting point.
// All values remain fully editable after applying the preset.
// rollingWindowDays is stored in the model but not surfaced in this UI yet.

struct PitchingRulesView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let teamID: UUID

    @State private var config: PitchingConfig = PitchingConfig()
    @State private var expandedBracket: PitchingAgeBracket? = nil
    @State private var showingPresetConfirm = false
    /// String buffer for the weekly cap text field — lets coach type freely before committing
    @State private var weeklyLimitText: String = ""

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                masterToggleSection
                if config.rulesEnabled {
                    weeklyCapSection
                    ageBracketsSection
                    presetSection
                }
            }
            .navigationTitle("Pitching Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let team = store.teams.first(where: { $0.id == teamID }) {
                    config = team.pitchingConfig
                    weeklyLimitText = config.weeklyLimit > 0 ? "\(config.weeklyLimit)" : ""
                }
            }
            .confirmationDialog(
                "Apply Little League Preset?",
                isPresented: $showingPresetConfirm,
                titleVisibility: .visible
            ) {
                Button("Apply Preset") {
                    withAnimation { config.applyLittleLeaguePreset() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will overwrite your current age bracket values with the standard Little League pitch count rules. You can edit them after.")
            }
        }
    }

    // MARK: - Master Toggle

    private var masterToggleSection: some View {
        Section {
            Toggle("Pitching Rules Enabled", isOn: $config.rulesEnabled)
        } footer: {
            Text("When on, pitch counts logged at archive time are used to compute rest days and eligibility. Warnings appear in the lineup when an ineligible player is assigned as pitcher.")
        }
    }

    // MARK: - Weekly Cap
    // The window type picker lives here because it controls when the cap resets,
    // not rest days (which are purely game-date relative).

    private var weeklyCapSection: some View {
        Section {
            Toggle("Weekly Pitch Cap", isOn: Binding(
                get: { config.weeklyLimitEnabled },
                set: { enabled in
                    config.weeklyLimitEnabled = enabled
                    // Default to 100 when first enabled so the engine always
                    // has a valid value — coach can adjust from there
                    if enabled && config.weeklyLimit == 0 {
                        config.weeklyLimit = 100
                        weeklyLimitText = "100"
                    }
                }
            ))

            if config.weeklyLimitEnabled {
                HStack {
                    Text("Max Pitches Per Window")
                    Spacer()
                    TextField("e.g. 100", text: $weeklyLimitText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .foregroundStyle(.blue)
                        .onChange(of: weeklyLimitText) { _, newValue in
                            let digits = newValue.filter { $0.isNumber }
                            weeklyLimitText = digits
                            config.weeklyLimit = Int(digits) ?? 0
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cap Resets")
                        .font(.subheadline)
                    Picker("Cap Resets", selection: $config.rollingWindowType) {
                        ForEach(RollingWindowType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Weekly Cap")
        } footer: {
            if config.weeklyLimitEnabled {
                switch config.rollingWindowType {
                case .calendarWeek:
                    Text("The cap resets each Monday. A player who reaches the limit on Saturday is eligible again the following Monday, subject to rest day requirements.")
                case .rolling:
                    Text("The cap is tracked over any 7-day period. A game played last Tuesday drops off this Tuesday.")
                }
            } else {
                Text("Optionally cap the total pitches a player may throw within a window. Rest day requirements still apply independently.")
            }
        }
    }

    // MARK: - Age Bracket Limits

    private var ageBracketsSection: some View {
        Section {
            if config.ageLimits.isEmpty {
                Text("No brackets configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(PitchingAgeBracket.allCases, id: \.self) { bracket in
                    if let _ = config.ageLimits[bracket] {
                        ageBracketRow(bracket: bracket)
                    }
                }
            }

            Button {
                // Add the next unconfigured bracket, or all if none exist
                let missing = PitchingAgeBracket.allCases.first { config.ageLimits[$0] == nil }
                if let bracket = missing {
                    config.ageLimits[bracket] = PitchingLimits(
                        dailyMax: 85, restDay1Min: 21, restDay2Min: 36,
                        restDay3Min: 51, restDay4Min: 66
                    )
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedBracket = bracket
                    }
                }
            } label: {
                Label("Add Age Bracket", systemImage: "plus.circle")
            }
            .disabled(PitchingAgeBracket.allCases.allSatisfy { config.ageLimits[$0] != nil })
        } header: {
            Text("Age Brackets")
        } footer: {
            Text("Tap a bracket to edit its daily maximum and rest day thresholds.")
        }
    }

    @ViewBuilder
    private func ageBracketRow(bracket: PitchingAgeBracket) -> some View {
        let isExpanded = expandedBracket == bracket
        let dailyMax = config.ageLimits[bracket]?.dailyMax ?? 0
        let limits = config.ageLimits[bracket]

        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedBracket = isExpanded ? nil : bracket
                }
            } label: {
                HStack {
                    Text("Ages \(bracket.displayName)")
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Max \(dailyMax)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            if isExpanded {
                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 0) {
                    // Daily Max — number pad entry
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Daily Max")
                                .font(.subheadline)
                            Text("pitches per game")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("85", text: intTextBinding(bracket: bracket, keyPath: \.dailyMax))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }

                    Divider()
                        .padding(.vertical, 12)

                    Text("Rest Day Thresholds")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)

                    Text("Enter where each tier starts. Leave blank to skip a tier.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 12)

                    // Tier 1 — always active, upper = tier2.lower - 1
                    let tier1Upper = (limits?.restDay2Min ?? (dailyMax + 1)) - 1
                    restTierRow(
                        label: "1 Rest Day",
                        lowerText: intTextBinding(bracket: bracket, keyPath: \.restDay1Min),
                        upper: tier1Upper
                    )
                    .padding(.bottom, 10)

                    // Tier 2 — always active, upper = tier3.lower - 1, or dailyMax if tier 3 blank
                    let tier2Upper = (limits?.restDay3Min ?? (dailyMax + 1)) - 1
                    restTierRow(
                        label: "2 Rest Days",
                        lowerText: intTextBinding(bracket: bracket, keyPath: \.restDay2Min),
                        upper: tier2Upper
                    )
                    .padding(.bottom, 10)

                    // Tier 3 — always visible, blank = inactive, upper = tier4.lower - 1 or dailyMax
                    let tier3Upper = (limits?.restDay4Min ?? (dailyMax + 1)) - 1
                    restTierRow(
                        label: "3 Rest Days",
                        lowerText: optionalIntTextBinding(bracket: bracket, keyPath: \.restDay3Min),
                        upper: tier3Upper
                    )
                    .padding(.bottom, 10)

                    // Tier 4 — always visible, blank = inactive, upper = dailyMax
                    restTierRow(
                        label: "4 Rest Days",
                        lowerText: optionalIntTextBinding(bracket: bracket, keyPath: \.restDay4Min),
                        upper: dailyMax
                    )
                    .padding(.bottom, 10)

                    // Remove bracket
                    Button(role: .destructive) {
                        withAnimation {
                            config.ageLimits.removeValue(forKey: bracket)
                            if expandedBracket == bracket { expandedBracket = nil }
                        }
                    } label: {
                        Label("Remove Ages \(bracket.displayName)", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .padding(.top, 4)
                }
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Rest tier row

    /// A single rest tier row. Always visible — blank lower bound means the tier
    /// is inactive and won't affect calculations.
    /// Layout: [label]  [TextField] – [upper] pitches
    /// All rows have identical trailing width so columns align regardless of label.
    private func restTierRow(
        label: String,
        lowerText: Binding<String>,
        upper: Int
    ) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 6) {
                TextField("—", text: lowerText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 48)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(lowerText.wrappedValue.isEmpty ? Color.secondary : Color.blue)
                    .fontWeight(.semibold)

                Text("–")
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                let lowerVal = Int(lowerText.wrappedValue) ?? 0
                Text(lowerText.wrappedValue.isEmpty ? "—" : (upper >= lowerVal && upper > 0 ? "\(upper)" : "—"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)

                Text("pitches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .leading)
            }
            .frame(width: 168)
        }
    }

    // MARK: - Number pad text bindings

    /// Binding for a non-optional Int field — filters to digits only on set.
    private func intTextBinding(
        bracket: PitchingAgeBracket,
        keyPath: WritableKeyPath<PitchingLimits, Int>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let v = config.ageLimits[bracket]?[keyPath: keyPath], v > 0 else { return "" }
                return "\(v)"
            },
            set: { text in
                let digits = text.filter { $0.isNumber }
                if let v = Int(digits), v > 0, config.ageLimits[bracket] != nil {
                    config.ageLimits[bracket]![keyPath: keyPath] = v
                }
            }
        )
    }

    /// Binding for an optional Int? field.
    /// Empty text = nil (tier inactive). Valid number = tier active with that lower bound.
    private func optionalIntTextBinding(
        bracket: PitchingAgeBracket,
        keyPath: WritableKeyPath<PitchingLimits, Int?>
    ) -> Binding<String> {
        Binding(
            get: {
                guard let v = config.ageLimits[bracket]?[keyPath: keyPath], v > 0 else { return "" }
                return "\(v)"
            },
            set: { text in
                guard config.ageLimits[bracket] != nil else { return }
                let digits = text.filter { $0.isNumber }
                if digits.isEmpty {
                    // Coach cleared the field — deactivate this tier
                    config.ageLimits[bracket]![keyPath: keyPath] = nil
                } else if let v = Int(digits), v > 0 {
                    config.ageLimits[bracket]![keyPath: keyPath] = v
                }
            }
        )
    }

    // MARK: - Preset / Reset

    private var presetSection: some View {
        Section {
            Button {
                showingPresetConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Apply Little League Preset")
                    Spacer()
                }
            }

            Button(role: .destructive) {
                withAnimation { config = PitchingConfig() }
            } label: {
                HStack {
                    Spacer()
                    Text("Reset to Defaults")
                    Spacer()
                }
            }
        } footer: {
            Text("The Little League preset loads the standard 2026 pitch count rules as a starting point. Reset clears all values and disables pitching rules.")
        }
    }

    // MARK: - Save

    private func save() {
        if let parsed = Int(weeklyLimitText), parsed > 0 {
            config.weeklyLimit = parsed
        }
        store.updatePitchingConfig(config, for: teamID)
        dismiss()
    }
}

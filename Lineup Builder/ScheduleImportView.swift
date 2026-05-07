import SwiftUI
import UniformTypeIdentifiers

// MARK: - ScheduleImportView
// Pre-import instruction sheet shown when coach taps "Import Schedule"
// or "Sync" in LineupView. Explains how to get the GC calendar link,
// accepts a paste URL or a file pick, fetches + parses, and hands the
// results back to LineupView via onImport.

struct ScheduleImportView: View {
    @EnvironmentObject var store: LineupStore
    @Environment(\.dismiss) var dismiss

    let onImport: (([ScheduledGame], String?) -> Void)

    @State private var urlText: String = ""
    @State private var isLoading = false
    @State private var showingFilePicker = false
    @State private var errorMessage: String?
    @State private var showingClearConfirmation = false

    private var isSync: Bool { store.calendarSubscriptionURL != nil }
    private var hasSchedule: Bool { !store.scheduledGames.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 28) {

                        // Icon + headline
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 52))
                                .foregroundColor(.blue)
                                .padding(.top, 16)

                            Text(isSync ? "Sync Schedule" : "Import Schedule")
                                .font(.title2.bold())

                            if isSync {
                                Text("We'll pull the latest from GameChanger and update your schedule.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(.horizontal, 24)

                        // GameChanger steps — always shown so coach can find the URL again
                        VStack(alignment: .leading, spacing: 16) {
                            instructionRow(number: "1", text: "In GameChanger, go to Settings.")
                            instructionRow(number: "2", text: "Tap Schedule Sync, then Sync Schedule to your calendar.")
                            instructionRow(number: "3", text: "Tap Copy Calendar Link.")
                            instructionRow(number: "4", text: "Paste the link below.")
                        }
                        .padding(.horizontal, 24)

                        // URL paste field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Calendar Link")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                TextField("webcal://...", text: $urlText)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .padding(10)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                if !urlText.isEmpty {
                                    Button {
                                        urlText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            if let stored = store.calendarSubscriptionURL, urlText.isEmpty {
                                Text("Stored: \(stored)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Error message
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 24)
                        }

                        // Sync note — shown after first import
                        if hasSchedule {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Keeping your schedule up to date")
                                    .font(.subheadline.bold())
                                Text("GameChanger doesn't push changes automatically. When your schedule changes, tap Sync and we'll pull the latest from GameChanger. New games and reschedules update in place — anything you've already planned won't be affected.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 24)
                        }

                        // Clear schedule option
                        if hasSchedule {
                            Button(role: .destructive) {
                                showingClearConfirmation = true
                            } label: {
                                Label("Clear Schedule", systemImage: "trash")
                                    .font(.subheadline)
                            }
                            .padding(.bottom, 8)
                        }

                        Spacer(minLength: 24)
                    }
                }

                // Bottom CTA area
                VStack(spacing: 12) {
                    // Primary: fetch from URL
                    Button {
                        Task { await fetchAndImport() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 4)
                            }
                            Text(primaryButtonLabel)
                                .font(.body.bold())
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(primaryButtonEnabled ? Color.blue : Color(.systemGray4))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!primaryButtonEnabled || isLoading)

                    // Secondary: file picker fallback
                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text("Choose .ics File Instead")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .padding(.top, 12)
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            .confirmationDialog("Clear Schedule?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
                Button("Clear Schedule", role: .destructive) {
                    store.clearSchedule()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all imported games and your calendar link. You can re-import anytime.")
            }
            .onAppear {
                // Pre-fill with stored URL if syncing
                if let stored = store.calendarSubscriptionURL {
                    urlText = stored
                }
            }
        }
    }

    // MARK: - Computed

    private var primaryButtonLabel: String {
        if isLoading { return "Importing..." }
        if isSync { return "Sync Now" }
        return "Import from Link"
    }

    private var primaryButtonEnabled: Bool {
        let effectiveURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveURL.isEmpty { return true }
        // Sync with stored URL and no new text entered
        return store.calendarSubscriptionURL != nil
    }

    // MARK: - Fetch + Parse

    @MainActor
    private func fetchAndImport() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        // Determine URL to use: typed field wins, else stored URL
        let raw = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = raw.isEmpty
            ? (store.calendarSubscriptionURL ?? "")
            : raw.replacingOccurrences(of: "webcal://", with: "https://")
                 .replacingOccurrences(of: "webcal://", with: "https://")

        guard let url = URL(string: urlString), !urlString.isEmpty else {
            errorMessage = "That doesn't look like a valid URL. Copy the link from GameChanger and try again."
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                errorMessage = "GameChanger returned an error (\(http.statusCode)). The link may have expired — try copying a fresh one."
                return
            }

            let result = ICalParser.parse(data: data)
            switch result {
            case .success(let events):
                let games = buildScheduledGames(from: events)
                let storedURL = raw.isEmpty ? nil : urlString
                Analytics.signal("schedule.import.completed", parameters: [
                    "count": "\(games.count)",
                    "source": "url"
                ])
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onImport(games, storedURL)
                }
            case .failure(let err):
                errorMessage = err.errorDescription ?? "Couldn't parse the calendar file."
                Analytics.signal("schedule.import.failed", parameters: ["reason": "\(err)"])
            }
        } catch {
            errorMessage = "Couldn't connect to GameChanger. Check your internet connection and try again."
            Analytics.signal("schedule.import.failed", parameters: ["reason": "network_error"])
        }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                errorMessage = "Couldn't read that file."
                return
            }
            switch ICalParser.parse(data: data) {
            case .success(let events):
                let games = buildScheduledGames(from: events)
                Analytics.signal("schedule.import.completed", parameters: [
                    "count": "\(games.count)",
                    "source": "file"
                ])
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onImport(games, nil) // no URL to store for file-based imports
                }
            case .failure(let err):
                errorMessage = err.errorDescription ?? "Couldn't parse the calendar file."
                Analytics.signal("schedule.import.failed", parameters: ["reason": "\(err)", "source": "file"])
            }
        case .failure:
            Analytics.signal("schedule.import.failed", parameters: ["reason": "file_picker_error", "source": "file"])
            break
        }
    }

    // MARK: - Helpers

    /// Converts parsed events to ScheduledGame values, filtering to future
    /// games only (today onwards) and excluding practices.
    /// Past games are excluded on import.
    private func buildScheduledGames(from events: [ICalParser.ParsedEvent]) -> [ScheduledGame] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return events.compactMap { event in
            guard event.date >= startOfToday else { return nil }
            guard !ICalParser.isPractice(event.rawSummary) else { return nil }
            return ScheduledGame(
                icalUID: event.uid,
                date: event.date,
                opponent: event.opponent,
                location: event.location,
                rawSummary: event.rawSummary,
                isCancelled: event.isCancelled
            )
        }
        .sorted { $0.date < $1.date }
    }

    @ViewBuilder
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue))
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}

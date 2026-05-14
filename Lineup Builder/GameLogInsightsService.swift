import Foundation
import SwiftUI
import Combine
import FoundationModels

// MARK: - GameLogInsightsService
// Generates coaching insights using Apple Intelligence via the FoundationModels
// framework (iOS 26+). Runs entirely on-device — no network call, no API key,
// works offline. Cache is keyed on game log count so inference only re-runs
// when new games are archived or a log is deleted.
//
// Inference is deliberately run off the main actor using a detached Task to
// prevent blocking the UI thread during LanguageModelSession initialization
// and response generation.

@MainActor
class GameLogInsightsService: ObservableObject {

    enum InsightState {
        case idle
        case placeholder          // Fewer than 2 logs — not enough data yet
        case unsupported          // Device/OS doesn't support Apple Intelligence
        case loading
        case loaded(String)
        case error(String)
    }

    @Published var state: InsightState = .idle

    private var cachedInsight: String?
    private var cachedLogCount: Int = -1
    private var inferenceTask: Task<Void, Never>?

    // MARK: - Public API

    func loadIfNeeded(logs: [GameLog]) {
        guard logs.count >= 2 else {
            state = .placeholder
            return
        }

        // Return cache if nothing has changed since last successful generation
        if let cached = cachedInsight, logs.count == cachedLogCount {
            state = .loaded(cached)
            return
        }

        startInference(logs: logs)
    }

    func invalidateCache() {
        inferenceTask?.cancel()
        inferenceTask = nil
        cachedInsight = nil
        cachedLogCount = -1
    }

    func retry(logs: [GameLog]) {
        invalidateCache()
        loadIfNeeded(logs: logs)
    }

    // MARK: - Inference

    private func startInference(logs: [GameLog]) {
        // Cancel any in-flight inference before starting a new one
        inferenceTask?.cancel()

        state = .loading

        // Check model availability on main actor before dispatching
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable:
            state = .unsupported
            return
        }

        // Capture what we need for the background task
        let prompt = buildPrompt(logs: logs)
        let instructions = self.instructions
        let logCount = logs.count

        // Run inference on a detached task so it never blocks the main thread
        inferenceTask = Task.detached(priority: .userInitiated) {
            do {
                let text = try await Self.runInference(
                    prompt: prompt,
                    instructions: instructions
                )
                await MainActor.run { [weak self] in
                    self?.cachedInsight = text
                    self?.cachedLogCount = logCount
                    self?.state = .loaded(text)
                    Analytics.signal("insights.generated")
                }
            } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                let trimmedLogs = Array(logs.prefix(10))
                let trimmedPrompt = Self.buildStaticPrompt(logs: trimmedLogs)
                do {
                    let text = try await Self.runInference(
                        prompt: trimmedPrompt,
                        instructions: instructions
                    )
                    await MainActor.run { [weak self] in
                        self?.cachedInsight = text
                        self?.cachedLogCount = logCount
                        self?.state = .loaded(text)
                        Analytics.signal("insights.generated")
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.state = .error(error.localizedDescription)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Static inference runner (nonisolated, safe to call from detached task)

    nonisolated private static func runInference(prompt: String, instructions: String) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt Construction

    private var instructions: String {
        """
        You are a helpful assistant coach for a youth baseball team. \
        When given season stats, respond with exactly 3 bullet points. \
        Format: put each bullet on its own separate line, starting with •. \
        Example format:
        • First observation here.
        • Second observation here.
        • Third observation here.

        Focus only on:
        - Which players have significantly more bench innings than their teammates
        - Which players are heavily skewed toward infield or outfield (not a balance of both)
        - Which players are getting significantly fewer total innings than others

        Rules:
        - Each bullet must be on its own line. Do not put multiple bullets on one line.
        - No preamble, no intro sentence, no summary sentence — bullets only.
        - Name specific players.
        - Do not mention players who have "never played" a position — focus on imbalances in what they HAVE played.
        - If everything is balanced, each bullet should note something positive that is going well.
        """
    }

    private func buildPrompt(logs: [GameLog]) -> String {
        Self.buildStaticPrompt(logs: logs)
    }

    nonisolated private static func buildStaticPrompt(logs: [GameLog]) -> String {
        let stats = SeasonStatsCalculator.compute(from: logs)

        // Manually build the stats string rather than using JSONEncoder in a nonisolated
        // context, which triggers a Swift 6 actor isolation warning.
        var lines: [String] = []
        lines.append("Games played: \(stats.gameCount)")
        if !stats.dateRange.isEmpty {
            lines.append("Date range: \(stats.dateRange)")
        }
        for p in stats.players {
            let positions = p.posCounts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            lines.append("\(p.playerName): \(p.totalInnings) innings, \(p.benchInnings) bench, \(p.infieldInnings) infield, \(p.outfieldInnings) outfield — \(positions)")
        }
        return "Here are the season stats:\n" + lines.joined(separator: "\n")
    }
}

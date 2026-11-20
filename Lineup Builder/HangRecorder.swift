#if DEBUG
import Foundation
import MetricKit
import os

// MARK: - HangRecorder (Debug builds only)
//
// Catches the intermittent ~20-second freeze seen around airplane mode while
// testing Merge 0b (PR #7), so the next one leaves evidence behind. An
// Instruments trace couldn't reach the phone over Wi-Fi, and the freeze doesn't
// reproduce on demand, so this records every hang whenever it happens.
//
// Two sources, written to Application Support/Diagnostics/Hangs/ and printed
// in the Debug section of the diagnostics report:
//
// 1. MetricKit hang diagnostics (MXHangDiagnostic). These carry the main
//    thread's call stack. iOS delivers them to the subscriber some time after
//    the hang, normally on the next launch, so relaunch the app after a freeze
//    before emailing the report. The stacks are unsymbolicated (binary UUID +
//    offset); symbolicate them with `atos` against the build's dSYM.
//    Xcode's Debug > Simulate MetricKit Payloads checks the plumbing.
//
// 2. A main-thread watchdog. A background thread pings the main queue every
//    0.25 s and records any gap of 2 s or more, the moment the main thread
//    comes back. It has no call stack, but it's immediate, it doesn't depend on
//    MetricKit's delivery, and it works under the debugger. If the watchdog
//    records a freeze and MetricKit never does, the freeze was probably the
//    debugger's (a Wi-Fi debug session pausing the app).
//
// Privacy: everything recorded is a time, a duration, an OS/build version, or
// a call stack of code addresses. No team, player or coach data.
//
// `nonisolated` because the project defaults to MainActor and both MetricKit's
// callback and the watchdog run off the main thread. State is behind a lock.

nonisolated final class HangRecorder: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    static let shared = HangRecorder()

    /// A freeze shorter than this isn't the bug we're chasing, and recording
    /// every 300 ms layout hitch would bury it.
    private static let watchdogThreshold: TimeInterval = 2.0
    private static let tick: TimeInterval = 0.25

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nickdavies.LineupBuilder",
                                    category: "hangs")

    private struct PingState {
        var outstandingSince: TimeInterval?   // uptime the unanswered ping was sent
        var answeredAt: TimeInterval?         // uptime the main thread answered it
        var reportedStart = false
    }
    private let state = OSAllocatedUnfairLock(initialState: PingState())
    private let fileLock = NSLock()
    private var started = false

    // MARK: Start

    /// Call once at launch. Safe to call again.
    func start() {
        let shouldStart = fileLock.withLock { () -> Bool in
            if started { return false }
            started = true
            return true
        }
        guard shouldStart else { return }

        MXMetricManager.shared.add(self)
        // Payloads delivered while no subscriber was registered (an earlier
        // launch that crashed or was killed before start()).
        store(MXMetricManager.shared.pastDiagnosticPayloads)

        let thread = Thread { [weak self] in self?.watchdogLoop() }
        thread.name = "HangRecorder.watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    // MARK: MetricKit

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        store(payloads)
    }

    private func store(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for (i, hang) in (payload.hangDiagnostics ?? []).enumerated() {
                let seconds = hang.hangDuration.converted(to: .seconds).value
                let stack = (try? JSONSerialization.jsonObject(with: hang.callStackTree.jsonRepresentation()))
                    ?? [String: Any]()
                let record: [String: Any] = [
                    "source": "metrickit",
                    "recordedAt": Self.iso(Date()),
                    "windowBegin": Self.iso(payload.timeStampBegin),
                    "windowEnd": Self.iso(payload.timeStampEnd),
                    "durationSeconds": seconds,
                    "appBuild": hang.metaData.applicationBuildVersion,
                    "os": hang.metaData.osVersion,
                    "callStackTree": stack,
                ]
                // The same payload can arrive twice (didReceive and
                // pastDiagnosticPayloads); its window + index names it.
                let name = "metrickit-\(Int(payload.timeStampEnd.timeIntervalSince1970))-\(i).json"
                write(record, named: name, skipIfExists: true)
                Self.log.error("MetricKit hang: \(seconds, format: .fixed(precision: 1), privacy: .public)s")
            }
        }
    }

    // MARK: Watchdog

    private func watchdogLoop() {
        var lastTick = ProcessInfo.processInfo.systemUptime
        while true {
            Thread.sleep(forTimeInterval: Self.tick)
            let now = ProcessInfo.processInfo.systemUptime

            // A tick far later than scheduled means this thread was frozen too:
            // the app was suspended in the background, not hung. Start over.
            if now - lastTick > Self.tick * 6 {
                state.withLock { $0 = PingState() }
                lastTick = now
                continue
            }
            lastTick = now

            enum Action { case none, ping, began(TimeInterval), ended(start: TimeInterval, end: TimeInterval) }
            let action: Action = state.withLock { s in
                if let sent = s.outstandingSince {
                    if let answered = s.answeredAt {
                        let reported = s.reportedStart
                        s = PingState()
                        if reported || answered - sent >= Self.watchdogThreshold {
                            return .ended(start: sent, end: answered)
                        }
                        return .none
                    }
                    if !s.reportedStart && now - sent >= Self.watchdogThreshold {
                        s.reportedStart = true
                        return .began(sent)
                    }
                    return .none
                }
                s.outstandingSince = now
                return .ping
            }

            switch action {
            case .none:
                break
            case .ping:
                DispatchQueue.main.async { [weak self] in
                    let answered = ProcessInfo.processInfo.systemUptime
                    self?.state.withLock { $0.answeredAt = answered }
                }
            case .began(let sent):
                Self.log.error("Main thread blocked for \(now - sent, format: .fixed(precision: 1), privacy: .public)s and counting")
            case .ended(let start, let end):
                let duration = end - start
                let startedAt = Date().addingTimeInterval(start - now)
                let record: [String: Any] = [
                    "source": "watchdog",
                    "startedAt": Self.iso(startedAt),
                    "durationSeconds": (duration * 10).rounded() / 10,
                    "os": ProcessInfo.processInfo.operatingSystemVersionString,
                ]
                write(record, named: "watchdog-\(Int(startedAt.timeIntervalSince1970 * 1000)).json", skipIfExists: false)
                Self.log.error("Main thread was blocked \(duration, format: .fixed(precision: 1), privacy: .public)s")
            }
        }
    }

    // MARK: Files

    private static var directory: URL {
        URL.applicationSupportDirectory
            .appending(path: "Diagnostics", directoryHint: .isDirectory)
            .appending(path: "Hangs", directoryHint: .isDirectory)
    }

    private func write(_ record: [String: Any], named name: String, skipIfExists: Bool) {
        fileLock.withLock {
            let fm = FileManager.default
            let url = Self.directory.appending(path: name)
            if skipIfExists && fm.fileExists(atPath: url.path) { return }
            do {
                try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url, options: .atomic)
            } catch {
                Self.log.error("Couldn't save hang record: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func records() -> [(name: String, json: [String: Any], raw: String)] {
        fileLock.withLock {
            let fm = FileManager.default
            let names = (try? fm.contentsOfDirectory(atPath: Self.directory.path)) ?? []
            return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
                let url = Self.directory.appending(path: name)
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return (name, json, String(decoding: data, as: UTF8.self))
            }
        }
    }

    /// How many hangs are on file (for the Debug row in Settings).
    var recordCount: Int { records().count }

    /// Deletes every recorded hang.
    func clear() {
        fileLock.withLock {
            try? FileManager.default.removeItem(at: Self.directory)
        }
    }

    // MARK: Report

    /// The Debug-only section of the diagnostics report: a one-line summary per
    /// hang, then the full MetricKit call stacks.
    func reportLines() -> [String] {
        let all = records()
        var lines = ["", "Hangs recorded (Debug build): \(all.count)"]
        guard !all.isEmpty else {
            lines.append("  none (MetricKit hangs arrive after a relaunch)")
            return lines
        }
        for r in all {
            let source = r.json["source"] as? String ?? "?"
            let seconds = r.json["durationSeconds"] as? Double ?? 0
            let duration = String(format: "%.1fs", seconds)
            if source == "watchdog" {
                lines.append("  watchdog   \(duration) at \(r.json["startedAt"] as? String ?? "?")")
            } else {
                let window = "\(r.json["windowBegin"] as? String ?? "?") – \(r.json["windowEnd"] as? String ?? "?")"
                lines.append("  metrickit  \(duration) in \(window)   build \(r.json["appBuild"] as? String ?? "?")")
            }
        }
        let stacks = all.filter { ($0.json["source"] as? String) == "metrickit" }
        if !stacks.isEmpty {
            lines.append("")
            lines.append("MetricKit hang call stacks (unsymbolicated; use atos with the build's dSYM):")
            for r in stacks {
                lines.append("--- \(r.name)")
                lines.append(r.raw)
            }
        }
        return lines
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
#endif

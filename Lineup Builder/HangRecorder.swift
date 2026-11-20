#if DEBUG
import Foundation
import MetricKit
import UIKit
import os

// MARK: - HangRecorder (Debug builds only)
//
// Catches the intermittent ~20-second freeze seen around airplane mode while
// testing Merge 0b (PR #7), so the next one leaves evidence behind. An
// Instruments trace couldn't reach the phone over Wi-Fi, and the freeze doesn't
// reproduce on demand, so this records every hang whenever it happens.
//
// Records go to Application Support/Diagnostics/Hangs/ and into the Debug
// section of the diagnostics report. Every record says whether a debugger was
// attached at the time. There are three kinds:
//
// 1. "watchdog": the main thread was blocked. A background thread pings the
//    main queue every 0.25 s. Once a ping goes unanswered for 2 s it saves an
//    in-progress record, updates it every second, and finalizes it when the
//    main thread answers. A record still marked in progress at the next launch
//    means the app was killed (or quit) while blocked. No call stack.
//
// 2. "paused": the WHOLE APP was stopped while in the foreground, the
//    watchdog's own thread included. Our code can't do that to its own
//    background threads; a debugger can (Xcode over Wi-Fi pausing the app when
//    it loses the phone), and so can iOS. The watchdog sees it as one tick
//    arriving far too late. Pauses while backgrounded are normal suspension and
//    aren't recorded. This is the kind the Nov 20 freeze turned out to be (run
//    from Xcode; the watchdog recorded nothing).
//
// 3. "metrickit": MetricKit hang diagnostics (MXHangDiagnostic), with the main
//    thread's call stack. iOS delivers them some time after the hang, normally
//    on the next launch, so relaunch before emailing the report. Stacks are
//    unsymbolicated (binary UUID + offset): symbolicate with `atos` against the
//    build's dSYM. Xcode's Debug > Simulate MetricKit Payloads checks the
//    plumbing.
//
// Privacy: everything recorded is a time, a duration, a flag, an OS/build
// version, or a call stack of code addresses. No team, player or coach data.
//
// `nonisolated` because the project defaults to MainActor and both MetricKit's
// callback and the watchdog run off the main thread. State is behind locks.

nonisolated final class HangRecorder: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    static let shared = HangRecorder()

    /// A freeze shorter than this isn't the bug we're chasing, and recording
    /// every 300 ms layout hitch would bury it.
    private static let threshold: TimeInterval = 2.0
    private static let tick: TimeInterval = 0.25
    /// A tick this late means the watchdog thread itself was stopped.
    private static let pauseGap: TimeInterval = tick * 6

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nickdavies.LineupBuilder",
                                    category: "hangs")

    private struct OpenHang {
        let file: String
        let startedAt: Date
        let sentAt: TimeInterval        // uptime the unanswered ping was sent
        let debuggerAtStart: Bool
        var lastWrite: TimeInterval
    }

    private struct State {
        var pingSentAt: TimeInterval?      // uptime of the unanswered ping
        var pingAnsweredAt: TimeInterval?  // uptime the main thread answered it
        var open: OpenHang?                // a main-thread hang past the threshold
        var isActive = false               // app in the foreground (didBecomeActive)
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let fileLock = NSLock()
    private var started = false

    // MARK: Start

    /// Call once at launch, on the main thread. Safe to call again.
    @MainActor
    func start() {
        let shouldStart = fileLock.withLock { () -> Bool in
            if started { return false }
            started = true
            return true
        }
        guard shouldStart else { return }

        // Hangs left "in progress" by the previous run: it ended while blocked.
        closeOrphanedHangs()

        // Foreground tracking, so a whole-app pause can be told apart from
        // ordinary suspension in the background.
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.state.withLock { $0.isActive = true }
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.state.withLock { $0.isActive = false }
        }

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
                    "durationSeconds": Self.round1(seconds),
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
            let gap = now - lastTick
            lastTick = now

            if gap > Self.pauseGap {
                handleWholeAppPause(gap: gap, resumedAt: now)
                continue
            }
            checkMainThread(now: now)
        }
    }

    /// This thread was stopped along with everything else. Records the pause if
    /// the app was in the foreground, and drops the ping in flight, which the
    /// pause (not a main-thread block) delayed.
    private func handleWholeAppPause(gap: TimeInterval, resumedAt now: TimeInterval) {
        let (wasActive, open) = state.withLock { s -> (Bool, OpenHang?) in
            let result = (s.isActive, s.open)
            s.pingSentAt = nil
            s.pingAnsweredAt = nil
            s.open = nil
            return result
        }

        // A main-thread hang already under way when the pause began: close it
        // at the pause, saying so.
        if let open {
            let blocked = (now - gap) - open.sentAt
            finalize(open, blockedSeconds: blocked, outcome: "the whole app paused while the main thread was blocked")
        }

        guard wasActive, gap >= Self.threshold else { return }
        let startedAt = Date().addingTimeInterval(-gap)
        let debugger = Self.debuggerAttached()
        let record: [String: Any] = [
            "source": "paused",
            "startedAt": Self.iso(startedAt),
            "durationSeconds": Self.round1(gap),
            "debuggerAttached": debugger,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        write(record, named: "paused-\(Self.millis(startedAt)).json", skipIfExists: false)
        Self.log.error("Whole app was paused \(gap, format: .fixed(precision: 1), privacy: .public)s in the foreground (debugger attached: \(debugger, privacy: .public))")
    }

    private func checkMainThread(now: TimeInterval) {
        enum Action {
            case none
            case ping
            case began(OpenHang)
            case update(OpenHang, blocked: TimeInterval)
            case ended(OpenHang, blocked: TimeInterval)
        }

        let action: Action = state.withLock { s in
            guard let sent = s.pingSentAt else {
                s.pingSentAt = now
                return .ping
            }
            if let answered = s.pingAnsweredAt {
                let open = s.open
                s.pingSentAt = nil
                s.pingAnsweredAt = nil
                s.open = nil
                if let open { return .ended(open, blocked: answered - sent) }
                return .none
            }
            let blocked = now - sent
            if var open = s.open {
                guard now - open.lastWrite >= 1 else { return .none }
                open.lastWrite = now
                s.open = open
                return .update(open, blocked: blocked)
            }
            guard blocked >= Self.threshold else { return .none }
            let startedAt = Date().addingTimeInterval(-blocked)
            let open = OpenHang(file: "watchdog-\(Self.millis(startedAt)).json",
                                startedAt: startedAt,
                                sentAt: sent,
                                debuggerAtStart: Self.debuggerAttached(),
                                lastWrite: now)
            s.open = open
            return .began(open)
        }

        switch action {
        case .none:
            break
        case .ping:
            DispatchQueue.main.async { [weak self] in
                let answered = ProcessInfo.processInfo.systemUptime
                self?.state.withLock { s in
                    if s.pingSentAt != nil { s.pingAnsweredAt = answered }
                }
            }
        case .began(let open):
            writeInProgress(open, blockedSeconds: now - open.sentAt)
            Self.log.error("Main thread blocked for \(now - open.sentAt, format: .fixed(precision: 1), privacy: .public)s and counting")
        case .update(let open, let blocked):
            writeInProgress(open, blockedSeconds: blocked)
        case .ended(let open, let blocked):
            finalize(open, blockedSeconds: blocked, outcome: "recovered")
            Self.log.error("Main thread was blocked \(blocked, format: .fixed(precision: 1), privacy: .public)s")
        }
    }

    private func watchdogRecord(_ open: OpenHang, blockedSeconds: TimeInterval, inProgress: Bool, outcome: String?) -> [String: Any] {
        var record: [String: Any] = [
            "source": "watchdog",
            "startedAt": Self.iso(open.startedAt),
            "durationSeconds": Self.round1(blockedSeconds),
            "inProgress": inProgress,
            "debuggerAttached": open.debuggerAtStart,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        if let outcome { record["outcome"] = outcome }
        return record
    }

    private func writeInProgress(_ open: OpenHang, blockedSeconds: TimeInterval) {
        write(watchdogRecord(open, blockedSeconds: blockedSeconds, inProgress: true, outcome: nil),
              named: open.file, skipIfExists: false)
    }

    private func finalize(_ open: OpenHang, blockedSeconds: TimeInterval, outcome: String) {
        write(watchdogRecord(open, blockedSeconds: blockedSeconds, inProgress: false, outcome: outcome),
              named: open.file, skipIfExists: false)
    }

    /// A watchdog record still in progress at launch belongs to a run that
    /// ended while the main thread was blocked: killed by the coach, Xcode, or
    /// iOS. Its duration is the last one written (at most a second short).
    private func closeOrphanedHangs() {
        for r in records() where (r.json["inProgress"] as? Bool) == true {
            var json = r.json
            json["inProgress"] = false
            json["outcome"] = "the app ended while the main thread was still blocked (at least this long)"
            write(json, named: r.name, skipIfExists: false)
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
            return names.filter { $0.hasSuffix(".json") }.compactMap { name in
                let url = Self.directory.appending(path: name)
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return (name, json, String(decoding: data, as: UTF8.self))
            }
            .sorted { Self.sortKey($0.json) < Self.sortKey($1.json) }
        }
    }

    private static func sortKey(_ json: [String: Any]) -> String {
        (json["startedAt"] as? String) ?? (json["windowEnd"] as? String) ?? ""
    }

    /// How many hangs and pauses are on file (for the Debug row in Settings).
    var recordCount: Int { records().count }

    /// Deletes every record.
    func clear() {
        fileLock.withLock {
            try? FileManager.default.removeItem(at: Self.directory)
        }
    }

    // MARK: Report

    /// The Debug-only section of the diagnostics report: a one-line summary per
    /// record, then the full MetricKit call stacks.
    func reportLines() -> [String] {
        let all = records()
        var lines = [
            "",
            "Hangs recorded (Debug build): \(all.count)   debugger attached now: \(Self.debuggerAttached() ? "yes" : "no")",
        ]
        guard !all.isEmpty else {
            lines.append("  none (MetricKit hangs arrive after a relaunch)")
            return lines
        }
        for r in all {
            let source = r.json["source"] as? String ?? "?"
            let duration = String(format: "%.1fs", r.json["durationSeconds"] as? Double ?? 0)
            let debugger = (r.json["debuggerAttached"] as? Bool).map { $0 ? "   debugger: yes" : "   debugger: no" } ?? ""
            let started = r.json["startedAt"] as? String ?? "?"
            switch source {
            case "watchdog":
                let state = (r.json["inProgress"] as? Bool) == true
                    ? "still blocked"
                    : (r.json["outcome"] as? String ?? "recovered")
                lines.append("  main thread blocked  \(duration) at \(started)\(debugger)   (\(state))")
            case "paused":
                lines.append("  whole app paused     \(duration) at \(started)\(debugger)")
            default:
                let window = "\(r.json["windowBegin"] as? String ?? "?") – \(r.json["windowEnd"] as? String ?? "?")"
                lines.append("  metrickit hang       \(duration) in \(window)   build \(r.json["appBuild"] as? String ?? "?")")
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

    // MARK: Helpers

    /// True while a debugger is attached to this process (P_TRACED).
    static func debuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func millis(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970 * 1000)
    }

    private static func round1(_ seconds: Double) -> Double {
        (seconds * 10).rounded() / 10
    }
}
#endif

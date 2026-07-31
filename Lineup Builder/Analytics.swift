//
//  Analytics.swift
//  Lineup Builder
//
//  Created by Nick Davies on 4/3/26.
//

import TelemetryDeck

/// `nonisolated` because the project defaults every type to `@MainActor`, and
/// this one has no reason to be: it reads no state and only forwards to
/// TelemetryDeck's own queue. Background-answering App Intents
/// (`openAppWhenRun = false`) run off the main actor by design, and hopping
/// there to record a signal would give that up for telemetry.
nonisolated enum Analytics {
    static func signal(_ name: String, parameters: [String: String] = [:]) {
        #if targetEnvironment(simulator)
        return // Never send signals from the simulator
        #else
        TelemetryDeck.signal(name, parameters: parameters)
        #endif
    }
}

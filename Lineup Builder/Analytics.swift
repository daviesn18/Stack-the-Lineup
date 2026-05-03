//
//  Analytics.swift
//  Lineup Builder
//
//  Created by Nick Davies on 4/3/26.
//

import TelemetryDeck

enum Analytics {
    static func signal(_ name: String, parameters: [String: String] = [:]) {
        #if targetEnvironment(simulator)
        return // Never send signals from the simulator
        #else
        TelemetryDeck.signal(name, parameters: parameters)
        #endif
    }
}

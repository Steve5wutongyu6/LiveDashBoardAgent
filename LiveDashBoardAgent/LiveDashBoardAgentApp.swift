//
//  LiveDashBoardAgentApp.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import SwiftUI

@main
struct LiveDashBoardAgentApp: App {
    @StateObject private var store = AgentDashboardStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            MenuBarStatusLabel(runtimeState: store.runtimeState)
        }
        .menuBarExtraStyle(.window)
    }
}

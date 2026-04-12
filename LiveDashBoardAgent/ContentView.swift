//
//  ContentView.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AgentDashboardStore
    @State private var selectedTab: DashboardPanelTab = .statusOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            DashboardTabSection(selectedTab: $selectedTab, store: store)
            actionsSection
        }
        .padding(12)
        .frame(width: 440, height: 650, alignment: .topLeading)
        .background(Color.clear)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(headerAccentColor)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.appHeaderTitle)
                            .font(.headline.weight(.semibold))
                    }
                }

                Spacer(minLength: 8)

                Button(L10n.appQuitAction, action: store.quitApplication)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            }

            if let bannerMessage = store.bannerMessage, !bannerMessage.isEmpty {
                Text(bannerMessage)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                    )
            }
        }
    }

    private var actionsSection: some View {
        PanelSection(title: L10n.quickActionsTitle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button(L10n.saveConfigurationAction, action: store.saveConfiguration)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(store.validationMessage != nil && !store.validationMessage!.isEmpty)

                    Button(L10n.reloadFromDiskAction, action: store.reloadConfigurationFromDisk)
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button(L10n.discardUnsavedAction, action: store.discardUnsavedChanges)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!store.hasUnsavedChanges)
                }

                Button(L10n.openConfigurationDirectoryAction, action: store.openConfigurationDirectory)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
    }

    private var headerAccentColor: Color {
        switch store.runtimeState.lifecycle {
        case .running:
            return .green
        case .away:
            return .orange
        case .waitingPermission:
            return .yellow
        case .configurationRequired, .error:
            return .red
        case .stopped:
            return .gray
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(store: AgentDashboardStore())
    }
}

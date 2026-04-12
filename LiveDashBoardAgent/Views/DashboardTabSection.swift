//
//  DashboardTabSection.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import SwiftUI

enum DashboardPanelTab: String, CaseIterable, Identifiable {
    case statusOverview
    case permissionStatus
    case configurationEditor

    var id: Self { self }

    var title: String {
        switch self {
        case .statusOverview:
            return NSLocalizedString("dashboard.tabs.status.title", comment: "")
        case .permissionStatus:
            return NSLocalizedString("dashboard.tabs.permissions.title", comment: "")
        case .configurationEditor:
            return NSLocalizedString("dashboard.tabs.configuration.title", comment: "")
        }
    }
}

struct DashboardTabSection: View {
    @Binding var selectedTab: DashboardPanelTab
    @ObservedObject var store: AgentDashboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $selectedTab) {
                ForEach(DashboardPanelTab.allCases) { tab in
                    Text(tab.title)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            ScrollView {
                activeTabContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .statusOverview:
            StatusOverviewSection(runtimeState: store.runtimeState)
        case .permissionStatus:
            PermissionStatusSection(
                runtimeState: store.runtimeState,
                onRequestPermission: store.requestAccessibilityPermission
            )
        case .configurationEditor:
            ConfigurationEditorSection(store: store)
        }
    }
}

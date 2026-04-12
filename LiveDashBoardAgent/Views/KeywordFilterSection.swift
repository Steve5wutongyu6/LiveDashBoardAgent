//
//  KeywordFilterSection.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import SwiftUI

struct KeywordFilterSection: View {
    @ObservedObject var store: AgentDashboardStore

    var body: some View {
        PanelSection(
            title: L10n.configurationKeywordFilterTitle,
            subtitle: L10n.configurationKeywordFilterSubtitle
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.configurationKeywordFilterLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField(L10n.configurationKeywordFilterPlaceholder, text: $store.draftConfiguration.keywordFilterText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)

                Text(helperMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var helperMessage: String {
        let keywordCount = store.draftConfiguration.keywordFilters.count
        if keywordCount == 0 {
            return L10n.configurationKeywordFilterEmptyHint
        }
        return L10n.configurationKeywordFilterEnabledCount(keywordCount)
    }
}

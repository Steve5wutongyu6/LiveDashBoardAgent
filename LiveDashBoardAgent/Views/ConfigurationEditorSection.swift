//
//  ConfigurationEditorSection.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import SwiftUI

struct ConfigurationEditorSection: View {
    @ObservedObject var store: AgentDashboardStore

    var body: some View {
        PanelSection(title: L10n.configurationPanelTitle) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.configurationServerURLLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(L10n.configurationServerURLPlaceholder, text: $store.draftConfiguration.serverURLString)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.configurationTokenLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SecureField(L10n.configurationTokenPlaceholder, text: $store.draftConfiguration.token)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Stepper(value: $store.draftConfiguration.intervalSeconds, in: 1...300) {
                        configurationLine(
                            title: L10n.configurationIntervalLabel,
                            value: L10n.seconds(store.draftConfiguration.intervalSeconds)
                        )
                    }
                    .controlSize(.small)

                    Stepper(value: $store.draftConfiguration.heartbeatSeconds, in: 10...600) {
                        configurationLine(
                            title: L10n.configurationHeartbeatLabel,
                            value: L10n.seconds(store.draftConfiguration.heartbeatSeconds)
                        )
                    }
                    .controlSize(.small)

                    Stepper(value: $store.draftConfiguration.idleThresholdSeconds, in: 30...3600) {
                        configurationLine(
                            title: L10n.configurationAfkThresholdLabel,
                            value: L10n.seconds(store.draftConfiguration.idleThresholdSeconds)
                        )
                    }
                    .controlSize(.small)
                }

                Toggle(isOn: $store.draftConfiguration.enableLog) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.configurationEnableLogTitle)
                        Text(L10n.configurationEnableLogSubtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if let validationMessage = store.validationMessage, !validationMessage.isEmpty {
                    Text(validationMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
                } else {
                    Text(L10n.configurationValidationSuccess)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func configurationLine(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

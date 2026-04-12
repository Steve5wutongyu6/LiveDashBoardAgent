//
//  StatusOverviewSection.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import SwiftUI

struct StatusOverviewSection: View {
    let runtimeState: AgentRuntimeState

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        PanelSection(
            title: L10n.statusPanelTitle
        ) {
            LazyVGrid(columns: columns, spacing: 8) {
                MetricCard(
                    title: L10n.statusMetricLifecycleTitle,
                    value: runtimeState.lifecycle.localizedTitle,
                    accentColor: lifecycleColor
                )

                MetricCard(
                    title: L10n.statusMetricLastReportTitle,
                    value: runtimeState.lastReportDisplay,
                    accentColor: .blue
                )

                MetricCard(
                    title: L10n.statusMetricCurrentAppTitle,
                    value: runtimeState.currentAppDisplay,
                    accentColor: .green
                )

                MetricCard(
                    title: L10n.statusMetricIdleDurationTitle,
                    value: L10n.seconds(Int(runtimeState.idleSeconds)),
                    accentColor: .orange
                )

                MetricCard(
                    title: L10n.statusMetricBatteryTitle,
                    value: runtimeState.batteryDisplay,
                    accentColor: .mint
                )

                MetricCard(
                    title: L10n.statusMetricMusicTitle,
                    value: runtimeState.musicDisplay,
                    accentColor: .pink
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                KeyValueRow(key: L10n.statusRowWindowTitle, value: runtimeState.currentWindowDisplay)
                KeyValueRow(key: L10n.statusRowConfigurationPath, value: runtimeState.configurationSource)
                KeyValueRow(
                    key: L10n.statusRowPermissionStatus,
                    value: runtimeState.accessibilityGranted ? L10n.permissionStatusShortGranted : L10n.permissionStatusShortDenied
                )
                KeyValueRow(
                    key: L10n.statusRowBackoffWait,
                    value: runtimeState.reportBackoffSeconds > 0 ? L10n.seconds(runtimeState.reportBackoffSeconds) : L10n.commonNone
                )
                KeyValueRow(key: L10n.statusRowExemption, value: exemptionDescription)

                if let lastErrorMessage = runtimeState.lastErrorMessage, !lastErrorMessage.isEmpty {
                    Text(lastErrorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.red.opacity(0.08))
                        )
                }
            }
        }
    }

    private var lifecycleColor: Color {
        switch runtimeState.lifecycle {
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

    private var exemptionDescription: String {
        if runtimeState.fullscreenVideoExemption {
            return L10n.statusExemptionFullscreen
        }

        if runtimeState.audioPlaying {
            return L10n.statusExemptionAudio
        }

        return L10n.commonNone
    }
}

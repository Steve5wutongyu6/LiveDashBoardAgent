//
//  PermissionStatusSection.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import SwiftUI

struct PermissionStatusSection: View {
    let runtimeState: AgentRuntimeState
    let onRequestPermission: () -> Void

    var body: some View {
        PanelSection(title: L10n.permissionPanelTitle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: runtimeState.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(runtimeState.accessibilityGranted ? .green : .orange)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text(runtimeState.accessibilityGranted ? L10n.permissionGrantedTitle : L10n.permissionDeniedTitle)
                        .font(.subheadline.weight(.semibold))

                    Text(
                        runtimeState.accessibilityGranted
                        ? L10n.permissionGrantedDescription
                        : L10n.permissionDeniedDescription
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if !runtimeState.accessibilityGranted {
                        Button(L10n.requestAccessibilityPermissionAction, action: onRequestPermission)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

//
//  AgentRuntimeState.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation

enum AgentLifecycleState: Equatable, Sendable {
    case configurationRequired
    case waitingPermission
    case running
    case away
    case stopped
    case error

    var localizedTitle: String {
        switch self {
        case .configurationRequired:
            return NSLocalizedString("lifecycle.configuration_required", comment: "")
        case .waitingPermission:
            return NSLocalizedString("lifecycle.waiting_permission", comment: "")
        case .running:
            return NSLocalizedString("lifecycle.running", comment: "")
        case .away:
            return NSLocalizedString("lifecycle.away", comment: "")
        case .stopped:
            return NSLocalizedString("lifecycle.stopped", comment: "")
        case .error:
            return NSLocalizedString("lifecycle.error", comment: "")
        }
    }
}

struct ForegroundWindowSnapshot: Equatable, Sendable {
    let appName: String
    let windowTitle: String
    let bundleIdentifier: String?
    let isFullscreen: Bool
}

struct MusicSnapshot: Codable, Equatable, Sendable {
    let app: String
    let title: String
    let artist: String?

    var displayName: String {
        if let artist, !artist.isEmpty {
            return L10n.musicSummary(title: title, artist: artist)
        }
        return title
    }
}

struct BatterySnapshot: Equatable, Sendable {
    let percentage: Int
    let isCharging: Bool
}

struct AgentReportExtra: Codable, Equatable, Sendable {
    let batteryPercent: Int?
    let batteryCharging: Bool?
    let music: MusicSnapshot?

    enum CodingKeys: String, CodingKey {
        case batteryPercent = "battery_percent"
        case batteryCharging = "battery_charging"
        case music
    }
}

struct AgentRuntimeState: Equatable, Sendable {
    var lifecycle: AgentLifecycleState
    var currentAppName: String
    var currentWindowTitle: String
    var lastReportAt: Date?
    var idleSeconds: Double
    var accessibilityGranted: Bool
    var audioPlaying: Bool
    var fullscreenVideoExemption: Bool
    var batterySnapshot: BatterySnapshot?
    var musicSnapshot: MusicSnapshot?
    var lastErrorMessage: String?
    var reportBackoffSeconds: Int
    var configurationSource: String
    var isMonitoring: Bool

    static let initial = AgentRuntimeState(
        lifecycle: .stopped,
        currentAppName: "",
        currentWindowTitle: "",
        lastReportAt: nil,
        idleSeconds: 0,
        accessibilityGranted: false,
        audioPlaying: false,
        fullscreenVideoExemption: false,
        batterySnapshot: nil,
        musicSnapshot: nil,
        lastErrorMessage: nil,
        reportBackoffSeconds: 0,
        configurationSource: L10n.commonNotLoaded,
        isMonitoring: false
    )

    var currentAppDisplay: String {
        currentAppName.isEmpty ? L10n.statusAppNone : currentAppName
    }

    var currentWindowDisplay: String {
        currentWindowTitle.isEmpty ? L10n.statusWindowNone : currentWindowTitle
    }

    var batteryDisplay: String {
        guard let batterySnapshot else {
            return L10n.statusBatteryUnavailable
        }

        return L10n.batterySummary(
            percentage: batterySnapshot.percentage,
            isCharging: batterySnapshot.isCharging
        )
    }

    var musicDisplay: String {
        musicSnapshot?.displayName ?? L10n.statusMusicNone
    }

    var lastReportDisplay: String {
        guard let lastReportAt else {
            return L10n.statusReportNone
        }
        return lastReportAt.formatted(date: .omitted, time: .standard)
    }
}

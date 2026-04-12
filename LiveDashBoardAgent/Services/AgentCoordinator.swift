//
//  AgentCoordinator.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation

typealias AgentRuntimeUpdateHandler = @Sendable (AgentRuntimeState) async -> Void

actor AgentCoordinator {
    private let accessibilityPermissionService = AccessibilityPermissionService()
    private let foregroundWorkspaceService = ForegroundWorkspaceService()
    private let idleTimeService = IdleTimeService()
    private let batteryInfoService = BatteryInfoService()
    private let audioPlaybackService = AudioPlaybackService()
    private let musicDetectionService = MusicDetectionService()
    private let networkReporter = NetworkReporter()

    private var monitoringTask: Task<Void, Never>?

    /**
     * 启动新的监控任务，若旧任务仍在运行会先安全停止，确保同一时间只有一个轮询循环
     *
     * - Parameters:
     *   - configuration: 已校验通过的运行配置
     *   - configurationSource: 当前配置来源路径，用于 UI 展示
     *   - updateHandler: 状态更新回调，供 SwiftUI 实时刷新菜单栏面板
     */
    func startMonitoring(
        with configuration: AgentConfiguration,
        configurationSource: String,
        updateHandler: @escaping AgentRuntimeUpdateHandler
    ) async {
        await stopMonitoring()
        monitoringTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.runMonitoringLoop(
                configuration: configuration.sanitized(),
                configurationSource: configurationSource,
                updateHandler: updateHandler
            )
        }
    }

    /**
     * 停止当前监控任务，供保存配置、退出应用或切换配置时复用
     *
     * - Returns: 无返回值
     */
    func stopMonitoring() async {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /**
     * 执行完整的监控循环，负责 AFK 判定、心跳上报、应用变化上报和失败退避
     *
     * - Parameters:
     *   - configuration: 当前生效配置
     *   - configurationSource: 配置来源路径
     *   - updateHandler: 状态更新回调
     */
    private func runMonitoringLoop(
        configuration: AgentConfiguration,
        configurationSource: String,
        updateHandler: @escaping AgentRuntimeUpdateHandler
    ) async {
        var previousAppName: String?
        var previousWindowTitle: String?
        var lastReportAt: Date?

        await AppLogger.shared.info(
            "开始监控循环",
            category: "Agent",
            metadata: [
                "interval": "\(configuration.intervalSeconds)",
                "heartbeat": "\(configuration.heartbeatSeconds)",
                "idle": "\(configuration.idleThresholdSeconds)"
            ]
        )

        while !Task.isCancelled {
            let accessibilityGranted = accessibilityPermissionService.isTrusted(promptIfNeeded: false)
            let idleSeconds = idleTimeService.idleSeconds()
            let batterySnapshot = batteryInfoService.currentBatterySnapshot()
            let audioPlaying = await audioPlaybackService.isAudioPlaying()
            let foregroundSnapshot = foregroundWorkspaceService.currentSnapshot(accessibilityGranted: accessibilityGranted)
            let fullscreen = foregroundSnapshot?.isFullscreen ?? false
            let isAway = idleSeconds >= Double(configuration.idleThresholdSeconds) && !audioPlaying && !fullscreen
            let musicSnapshot = isAway ? nil : await musicDetectionService.currentMusicSnapshot()
            let heartbeatDue = lastReportAt == nil || Date().timeIntervalSince(lastReportAt ?? .distantPast) >= Double(configuration.heartbeatSeconds)

            if isAway {
                var runtimeState = buildRuntimeState(
                    lifecycle: .away,
                    foregroundSnapshot: foregroundSnapshot,
                    configurationSource: configurationSource,
                    lastReportAt: lastReportAt,
                    idleSeconds: idleSeconds,
                    accessibilityGranted: accessibilityGranted,
                    audioPlaying: audioPlaying,
                    batterySnapshot: batterySnapshot,
                    musicSnapshot: nil,
                    lastErrorMessage: nil,
                    backoffSeconds: 0,
                    isMonitoring: true
                )

                if heartbeatDue {
                    let extra = buildExtraPayload(batterySnapshot: batterySnapshot, musicSnapshot: nil)
                    let reportResult = await networkReporter.send(
                        appIdentifier: "idle",
                        windowTitle: "User is away",
                        extra: extra,
                        configuration: configuration
                    )

                    switch reportResult {
                    case .success:
                        lastReportAt = Date()
                        runtimeState.lastReportAt = lastReportAt
                    case let .failure(backoffSeconds, message):
                        runtimeState.lastErrorMessage = message
                        runtimeState.reportBackoffSeconds = backoffSeconds
                        await updateHandler(runtimeState)
                        await sleep(seconds: max(backoffSeconds, configuration.intervalSeconds))
                        continue
                    }
                }

                await updateHandler(runtimeState)
                await sleep(seconds: configuration.intervalSeconds)
                continue
            }

            guard let foregroundSnapshot else {
                let runtimeState = buildRuntimeState(
                    lifecycle: accessibilityGranted ? .error : .waitingPermission,
                    foregroundSnapshot: nil,
                    configurationSource: configurationSource,
                    lastReportAt: lastReportAt,
                    idleSeconds: idleSeconds,
                    accessibilityGranted: accessibilityGranted,
                    audioPlaying: audioPlaying,
                    batterySnapshot: batterySnapshot,
                    musicSnapshot: musicSnapshot,
                    lastErrorMessage: accessibilityGranted ? L10n.coordinatorForegroundUnavailable : L10n.coordinatorWindowUnavailable,
                    backoffSeconds: 0,
                    isMonitoring: true
                )
                await updateHandler(runtimeState)
                await sleep(seconds: configuration.intervalSeconds)
                continue
            }

            let changed = foregroundSnapshot.appName != previousAppName || foregroundSnapshot.windowTitle != previousWindowTitle
            var runtimeState = buildRuntimeState(
                lifecycle: accessibilityGranted ? .running : .waitingPermission,
                foregroundSnapshot: foregroundSnapshot,
                configurationSource: configurationSource,
                lastReportAt: lastReportAt,
                idleSeconds: idleSeconds,
                accessibilityGranted: accessibilityGranted,
                audioPlaying: audioPlaying,
                batterySnapshot: batterySnapshot,
                musicSnapshot: musicSnapshot,
                lastErrorMessage: accessibilityGranted ? nil : L10n.coordinatorAccessibilityDegraded,
                backoffSeconds: 0,
                isMonitoring: true
            )

            if changed || heartbeatDue {
                let extra = buildExtraPayload(batterySnapshot: batterySnapshot, musicSnapshot: musicSnapshot)
                let reportResult = await networkReporter.send(
                    appIdentifier: foregroundSnapshot.appName,
                    windowTitle: foregroundSnapshot.windowTitle,
                    extra: extra,
                    configuration: configuration
                )

                switch reportResult {
                case .success:
                    previousAppName = foregroundSnapshot.appName
                    previousWindowTitle = foregroundSnapshot.windowTitle
                    lastReportAt = Date()
                    runtimeState.lastReportAt = lastReportAt

                    if changed {
                        await AppLogger.shared.info(
                            "已上报前台窗口变化",
                            category: "Agent",
                            metadata: [
                                "app": foregroundSnapshot.appName,
                                "title": String(foregroundSnapshot.windowTitle.prefix(80))
                            ]
                        )
                    }
                case let .failure(backoffSeconds, message):
                    runtimeState.lastErrorMessage = message
                    runtimeState.reportBackoffSeconds = backoffSeconds
                    await updateHandler(runtimeState)
                    await sleep(seconds: max(backoffSeconds, configuration.intervalSeconds))
                    continue
                }
            }

            await updateHandler(runtimeState)
            await sleep(seconds: configuration.intervalSeconds)
        }

        let stoppedState = buildRuntimeState(
            lifecycle: .stopped,
            foregroundSnapshot: nil,
            configurationSource: configurationSource,
            lastReportAt: lastReportAt,
            idleSeconds: 0,
            accessibilityGranted: accessibilityPermissionService.isTrusted(promptIfNeeded: false),
            audioPlaying: false,
            batterySnapshot: batteryInfoService.currentBatterySnapshot(),
            musicSnapshot: nil,
            lastErrorMessage: nil,
            backoffSeconds: 0,
            isMonitoring: false
        )
        await updateHandler(stoppedState)
        await AppLogger.shared.info("监控循环已停止", category: "Agent")
    }

    /**
     * 构建统一的运行态快照，避免 UI 层需要直接拼装底层字段
     *
     * - Parameters:
     *   - lifecycle: 当前生命周期状态
     *   - foregroundSnapshot: 前台窗口快照
     *   - configurationSource: 当前配置来源路径
     *   - lastReportAt: 最近一次成功上报时间
     *   - idleSeconds: 当前空闲秒数
     *   - accessibilityGranted: 是否具备辅助功能权限
     *   - audioPlaying: 是否存在活跃音频
     *   - batterySnapshot: 当前电池快照
     *   - musicSnapshot: 当前音乐快照
     *   - lastErrorMessage: 最近一次错误说明
     *   - backoffSeconds: 当前退避秒数
     *   - isMonitoring: 当前是否处于监控循环中
     * - Returns: 可直接用于 SwiftUI 刷新的运行态对象
     */
    private func buildRuntimeState(
        lifecycle: AgentLifecycleState,
        foregroundSnapshot: ForegroundWindowSnapshot?,
        configurationSource: String,
        lastReportAt: Date?,
        idleSeconds: Double,
        accessibilityGranted: Bool,
        audioPlaying: Bool,
        batterySnapshot: BatterySnapshot?,
        musicSnapshot: MusicSnapshot?,
        lastErrorMessage: String?,
        backoffSeconds: Int,
        isMonitoring: Bool
    ) -> AgentRuntimeState {
        AgentRuntimeState(
            lifecycle: lifecycle,
            currentAppName: foregroundSnapshot?.appName ?? "",
            currentWindowTitle: foregroundSnapshot?.windowTitle ?? "",
            lastReportAt: lastReportAt,
            idleSeconds: idleSeconds,
            accessibilityGranted: accessibilityGranted,
            audioPlaying: audioPlaying,
            fullscreenVideoExemption: foregroundSnapshot?.isFullscreen ?? false,
            batterySnapshot: batterySnapshot,
            musicSnapshot: musicSnapshot,
            lastErrorMessage: lastErrorMessage,
            reportBackoffSeconds: backoffSeconds,
            configurationSource: configurationSource,
            isMonitoring: isMonitoring
        )
    }

    /**
     * 把电池和音乐信息整理成后端 `extra` 字段，和 Python 版本的载荷结构保持一致
     *
     * - Parameters:
     *   - batterySnapshot: 当前电池快照
     *   - musicSnapshot: 当前音乐快照
     * - Returns: 可编码的附加信息对象
     */
    private func buildExtraPayload(batterySnapshot: BatterySnapshot?, musicSnapshot: MusicSnapshot?) -> AgentReportExtra {
        AgentReportExtra(
            batteryPercent: batterySnapshot?.percentage,
            batteryCharging: batterySnapshot?.isCharging,
            music: musicSnapshot
        )
    }

    /**
     * 执行轮询间隔或失败退避等待，并在取消时尽快返回
     *
     * - Parameter seconds: 需要等待的秒数
     */
    private func sleep(seconds: Int) async {
        guard seconds > 0 else {
            return
        }

        let nanoseconds = UInt64(seconds) * 1_000_000_000
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

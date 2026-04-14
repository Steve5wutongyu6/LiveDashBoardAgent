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
    private let systemBroadcastReceiver = SystemBroadcastReceiver()

    private var monitoringTask: Task<Void, Never>?
    private var activeMonitoringSessionID: UUID?
    private var activeConfiguration: AgentConfiguration?
    private var activeConfigurationSource = ""
    private var activeUpdateHandler: AgentRuntimeUpdateHandler?
    private var previousAppName: String?
    private var previousWindowTitle: String?
    private var previousAwayState = false
    private var lastReportAt: Date?
    private var isScreenLocked = false
    private var pendingImmediateEvaluation = false
    private var pendingForcedReport = false

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

        let sessionID = UUID()
        activeMonitoringSessionID = sessionID
        activeConfiguration = configuration.sanitized()
        activeConfigurationSource = configurationSource
        activeUpdateHandler = updateHandler
        previousAppName = nil
        previousWindowTitle = nil
        previousAwayState = false
        lastReportAt = nil
        isScreenLocked = false
        pendingImmediateEvaluation = true
        pendingForcedReport = false

        systemBroadcastReceiver.start { [weak self] event in
            Task { [weak self] in
                await self?.handleSystemBroadcast(event, sessionID: sessionID)
            }
        }

        monitoringTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.runMonitoringLoop(sessionID: sessionID)
        }
    }

    /**
     * 停止当前监控任务，供保存配置、退出应用或切换配置时复用
     *
     * - Returns: 无返回值
     */
    func stopMonitoring() async {
        activeMonitoringSessionID = nil
        activeConfiguration = nil
        activeConfigurationSource = ""
        activeUpdateHandler = nil
        previousAppName = nil
        previousWindowTitle = nil
        previousAwayState = false
        lastReportAt = nil
        isScreenLocked = false
        pendingImmediateEvaluation = false
        pendingForcedReport = false

        systemBroadcastReceiver.stop()
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /**
     * 在辅助功能授权变化后主动刷新监控状态，避免 UI 和实际上报状态长时间滞后
     *
     * - Parameter isGranted: 当前最新的辅助功能授权状态
     * - Returns: 无返回值
     */
    func handleAccessibilityPermissionChanged(isGranted: Bool) async {
        await AppLogger.shared.info(
            "辅助功能权限状态已变化",
            category: "Permission",
            metadata: ["granted": "\(isGranted)"]
        )

        guard monitoringTask != nil else {
            return
        }

        queueImmediateEvaluation(forceReport: isGranted)
    }

    /**
     * 执行完整的监控循环，负责 AFK 判定、心跳上报、应用变化上报和失败退避
     *
     * - Parameter sessionID: 当前监控会话标识，用于避免旧任务误写入新状态
     * - Returns: 无返回值
     */
    private func runMonitoringLoop(sessionID: UUID) async {
        guard let configuration = activeConfiguration,
              activeMonitoringSessionID == sessionID else {
            return
        }

        let reportRedactor = ReportKeywordRedactor(keywords: configuration.keywordFilters)

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
            guard activeMonitoringSessionID == sessionID,
                  let configuration = activeConfiguration,
                  let updateHandler = activeUpdateHandler else {
                return
            }

            let forceReport = pendingForcedReport
            pendingForcedReport = false
            pendingImmediateEvaluation = false

            let accessibilityGranted = accessibilityPermissionService.isTrusted(promptIfNeeded: false)
            let idleSeconds = idleTimeService.idleSeconds()
            let batterySnapshot = batteryInfoService.currentBatterySnapshot()
            let audioPlaying = await audioPlaybackService.isAudioPlaying()
            let foregroundSnapshot = foregroundWorkspaceService.currentSnapshot(accessibilityGranted: accessibilityGranted)
            let fullscreen = foregroundSnapshot?.isFullscreen ?? false
            let isAway = isScreenLocked || (idleSeconds >= Double(configuration.idleThresholdSeconds) && !audioPlaying && !fullscreen)
            let musicSnapshot = isAway ? nil : await musicDetectionService.currentMusicSnapshot()
            let heartbeatDue = lastReportAt == nil || Date().timeIntervalSince(lastReportAt ?? .distantPast) >= Double(configuration.heartbeatSeconds)
            let awayStateChanged = isAway != previousAwayState

            if awayStateChanged {
                await AppLogger.shared.info(
                    isAway ? "检测到 AFK 状态变化，进入 AFK" : "检测到 AFK 状态变化，结束 AFK",
                    category: "Agent",
                    metadata: [
                        "idle": "\(Int(idleSeconds))",
                        "locked": "\(isScreenLocked)"
                    ]
                )
            }

            if isAway {
                var runtimeState = buildRuntimeState(
                    lifecycle: .away,
                    foregroundSnapshot: foregroundSnapshot,
                    configurationSource: activeConfigurationSource,
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

                if heartbeatDue || awayStateChanged || forceReport {
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
                        await sleep(seconds: max(backoffSeconds, configuration.intervalSeconds), sessionID: sessionID)
                        continue
                    }
                }

                previousAwayState = true
                await updateHandler(runtimeState)
                await sleep(seconds: configuration.intervalSeconds, sessionID: sessionID)
                continue
            }

            guard let foregroundSnapshot else {
                let runtimeState = buildRuntimeState(
                    lifecycle: accessibilityGranted ? .error : .waitingPermission,
                    foregroundSnapshot: nil,
                    configurationSource: activeConfigurationSource,
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

                previousAwayState = false
                await updateHandler(runtimeState)
                await sleep(seconds: configuration.intervalSeconds, sessionID: sessionID)
                continue
            }

            let changed = foregroundSnapshot.appName != previousAppName || foregroundSnapshot.windowTitle != previousWindowTitle
            var runtimeState = buildRuntimeState(
                lifecycle: accessibilityGranted ? .running : .waitingPermission,
                foregroundSnapshot: foregroundSnapshot,
                configurationSource: activeConfigurationSource,
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

            if changed || heartbeatDue || awayStateChanged || forceReport {
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
                                "app": reportRedactor.redact(foregroundSnapshot.appName),
                                "title": String(reportRedactor.redact(foregroundSnapshot.windowTitle).prefix(80))
                            ]
                        )
                    }
                case let .failure(backoffSeconds, message):
                    runtimeState.lastErrorMessage = message
                    runtimeState.reportBackoffSeconds = backoffSeconds
                    await updateHandler(runtimeState)
                    await sleep(seconds: max(backoffSeconds, configuration.intervalSeconds), sessionID: sessionID)
                    continue
                }
            }

            previousAwayState = false
            await updateHandler(runtimeState)
            await sleep(seconds: configuration.intervalSeconds, sessionID: sessionID)
        }

        guard activeMonitoringSessionID == sessionID,
              let updateHandler = activeUpdateHandler else {
            return
        }

        let stoppedState = buildRuntimeState(
            lifecycle: .stopped,
            foregroundSnapshot: nil,
            configurationSource: activeConfigurationSource,
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
     * 处理来自系统广播接收器的事件，并按事件类型唤醒监控循环或清理退避状态
     *
     * - Parameters:
     *   - event: 当前收到的系统广播事件
     *   - sessionID: 触发回调时所属的监控会话标识
     * - Returns: 无返回值
     */
    private func handleSystemBroadcast(_ event: SystemBroadcastEvent, sessionID: UUID) async {
        guard activeMonitoringSessionID == sessionID else {
            return
        }

        switch event {
        case let .networkChanged(current, previous):
            await AppLogger.shared.info(
                "检测到网络状态变化",
                category: "Receiver",
                metadata: [
                    "current": current.summary,
                    "previous": previous?.summary ?? "unknown"
                ]
            )

            guard current.isReachable else {
                return
            }

            await networkReporter.resetFailureState(reason: "network_changed")
            queueImmediateEvaluation(forceReport: true)
        case let .screenLockChanged(isLocked):
            guard isScreenLocked != isLocked else {
                return
            }

            isScreenLocked = isLocked
            await AppLogger.shared.info(
                isLocked ? "检测到系统锁屏，准备立即进入 AFK" : "检测到系统解锁，准备立即结束 AFK",
                category: "Receiver"
            )
            queueImmediateEvaluation(forceReport: true)
        }
    }

    /**
     * 标记下一轮循环需要提前执行，并按需强制做一次即时上报
     *
     * - Parameter forceReport: 是否在下一轮忽略心跳限制立即尝试上报
     * - Returns: 无返回值
     */
    private func queueImmediateEvaluation(forceReport: Bool) {
        pendingImmediateEvaluation = true
        pendingForcedReport = pendingForcedReport || forceReport
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
     * 执行轮询间隔或失败退避等待，并在收到系统广播或取消信号时尽快返回
     *
     * - Parameters:
     *   - seconds: 需要等待的秒数
     *   - sessionID: 当前监控会话标识
     * - Returns: 无返回值
     */
    private func sleep(seconds: Int, sessionID: UUID) async {
        guard seconds > 0 else {
            return
        }

        let deadline = Date().addingTimeInterval(Double(seconds))

        while Date() < deadline {
            guard activeMonitoringSessionID == sessionID,
                  !pendingImmediateEvaluation,
                  !pendingForcedReport,
                  !Task.isCancelled else {
                return
            }

            let remainingSeconds = min(deadline.timeIntervalSinceNow, 0.25)
            guard remainingSeconds > 0 else {
                return
            }

            let nanoseconds = UInt64(remainingSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }
}

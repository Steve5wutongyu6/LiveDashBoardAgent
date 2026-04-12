//
//  AgentDashboardStore.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import AppKit
import Combine
import Foundation

@MainActor
final class AgentDashboardStore: ObservableObject {
    @Published var draftConfiguration: AgentConfiguration {
        didSet {
            synchronizeDraftValidation()
        }
    }

    @Published private(set) var persistedConfiguration: AgentConfiguration
    @Published private(set) var runtimeState: AgentRuntimeState
    @Published private(set) var validationMessage: String?
    @Published private(set) var bannerMessage: String?

    private let accessibilityPermissionService = AccessibilityPermissionService()
    private let configurationStore = ConfigurationStore()
    private let coordinator = AgentCoordinator()

    private var currentConfigurationFileURL: URL?

    /**
     * 初始化菜单栏状态仓库，并在应用启动后自动加载配置和启动监控
     */
    init() {
        self.persistedConfiguration = .default
        self.draftConfiguration = .default
        self.runtimeState = .initial
        self.validationMessage = AgentConfiguration.default.validationMessage()
        self.bannerMessage = nil

        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    deinit {
        let coordinator = self.coordinator
        Task {
            await coordinator.stopMonitoring()
        }
    }

    var hasUnsavedChanges: Bool {
        draftConfiguration.sanitized() != persistedConfiguration.sanitized()
    }

    /**
     * 首次加载配置并配置日志系统，然后决定是否启动监控循环
     *
     * - Returns: 无返回值
     */
    func bootstrap() async {
        let loadedConfiguration = await configurationStore.loadConfiguration()
        currentConfigurationFileURL = loadedConfiguration.fileURL
        persistedConfiguration = loadedConfiguration.configuration
        draftConfiguration = loadedConfiguration.configuration
        runtimeState.configurationSource = loadedConfiguration.displayPath

        await AppLogger.shared.configure(
            baseDirectoryURL: loadedConfiguration.directoryURL,
            fileLoggingEnabled: loadedConfiguration.configuration.enableLog
        )

        synchronizeDraftValidation()
        await restartMonitoringIfPossible()
    }

    /**
     * 保存当前编辑中的配置，并在成功后重启监控流程让新配置立即生效
     *
     * - Returns: 无返回值
     */
    func saveConfiguration() {
        Task { [weak self] in
            await self?.saveConfigurationTask()
        }
    }

    /**
     * 从磁盘重新读取配置文件，适合用户手动改 JSON 后快速刷新界面
     *
     * - Returns: 无返回值
     */
    func reloadConfigurationFromDisk() {
        Task { [weak self] in
            await self?.reloadConfigurationTask()
        }
    }

    /**
     * 放弃当前未保存的修改，恢复到最后一次已保存配置
     *
     * - Returns: 无返回值
     */
    func discardUnsavedChanges() {
        draftConfiguration = persistedConfiguration
        bannerMessage = L10n.bannerConfigurationRestored
    }

    /**
     * 主动请求辅助功能权限，让系统弹出授权指引
     *
     * - Returns: 无返回值
     */
    func requestAccessibilityPermission() {
        let granted = accessibilityPermissionService.isTrusted(promptIfNeeded: true)
        runtimeState.accessibilityGranted = granted
        bannerMessage = granted
            ? L10n.bannerPermissionAvailable
            : L10n.bannerPermissionPrompted

        Task { [weak self] in
            await self?.restartMonitoringIfPossible()
        }
    }

    /**
     * 打开当前配置文件所在目录，便于用户直接查看 `config.json` 和日志文件
     *
     * - Returns: 无返回值
     */
    func openConfigurationDirectory() {
        Task { [weak self] in
            guard let self else {
                return
            }

            let fallbackURL = await self.configurationStore.defaultConfigurationFileURL()
            let fileURL = self.currentConfigurationFileURL ?? fallbackURL
            await MainActor.run {
                _ = NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
            }
        }
    }

    /**
     * 结束当前应用进程，和 Python 版本的“安全退出”菜单行为保持一致
     *
     * - Returns: 无返回值
     */
    func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    /**
     * 执行真正的保存逻辑，避免 UI 线程直接承担文件写入和监控重启
     *
     * - Returns: 无返回值
     */
    private func saveConfigurationTask() async {
        let sanitizedConfiguration = draftConfiguration.sanitized()

        if let validationMessage = sanitizedConfiguration.validationMessage() {
            bannerMessage = validationMessage
            return
        }

        do {
            let savedConfiguration = try await configurationStore.saveConfiguration(
                sanitizedConfiguration,
                preferredFileURL: currentConfigurationFileURL
            )

            currentConfigurationFileURL = savedConfiguration.fileURL
            persistedConfiguration = savedConfiguration.configuration
            draftConfiguration = savedConfiguration.configuration
            runtimeState.configurationSource = savedConfiguration.displayPath
            bannerMessage = L10n.bannerConfigurationSaved

            await AppLogger.shared.configure(
                baseDirectoryURL: savedConfiguration.directoryURL,
                fileLoggingEnabled: savedConfiguration.configuration.enableLog
            )

            await restartMonitoringIfPossible()
        } catch {
            bannerMessage = L10n.configurationSaveFailed(error.localizedDescription)
            await AppLogger.shared.error(
                "配置保存失败",
                category: "Configuration",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    /**
     * 执行真正的重新加载逻辑，让磁盘上的外部修改可以同步回菜单栏面板
     *
     * - Returns: 无返回值
     */
    private func reloadConfigurationTask() async {
        let loadedConfiguration = await configurationStore.loadConfiguration()
        currentConfigurationFileURL = loadedConfiguration.fileURL
        persistedConfiguration = loadedConfiguration.configuration
        draftConfiguration = loadedConfiguration.configuration
        runtimeState.configurationSource = loadedConfiguration.displayPath
        bannerMessage = L10n.bannerConfigurationReloaded

        await AppLogger.shared.configure(
            baseDirectoryURL: loadedConfiguration.directoryURL,
            fileLoggingEnabled: loadedConfiguration.configuration.enableLog
        )

        await restartMonitoringIfPossible()
    }

    /**
     * 根据草稿配置实时更新校验提示，避免用户点击保存后才发现明显错误
     *
     * - Returns: 无返回值
     */
    private func synchronizeDraftValidation() {
        validationMessage = draftConfiguration.sanitized().validationMessage()
    }

    /**
     * 按当前已保存配置决定是否启动监控，配置非法时改为提示用户修正
     *
     * - Returns: 无返回值
     */
    private func restartMonitoringIfPossible() async {
        let configuration = persistedConfiguration.sanitized()
        let configurationSource = runtimeState.configurationSource
        let accessibilityGranted = accessibilityPermissionService.isTrusted(promptIfNeeded: false)

        if let validationMessage = configuration.validationMessage() {
            await coordinator.stopMonitoring()
            runtimeState = AgentRuntimeState(
                lifecycle: .configurationRequired,
                currentAppName: runtimeState.currentAppName,
                currentWindowTitle: runtimeState.currentWindowTitle,
                lastReportAt: runtimeState.lastReportAt,
                idleSeconds: runtimeState.idleSeconds,
                accessibilityGranted: accessibilityGranted,
                audioPlaying: runtimeState.audioPlaying,
                fullscreenVideoExemption: runtimeState.fullscreenVideoExemption,
                batterySnapshot: runtimeState.batterySnapshot,
                musicSnapshot: runtimeState.musicSnapshot,
                lastErrorMessage: validationMessage,
                reportBackoffSeconds: 0,
                configurationSource: configurationSource,
                isMonitoring: false
            )
            return
        }

        await coordinator.startMonitoring(with: configuration, configurationSource: configurationSource) { [weak self] runtimeState in
            guard let self else {
                return
            }

            await MainActor.run {
                self.runtimeState = runtimeState
            }
        }
    }
}

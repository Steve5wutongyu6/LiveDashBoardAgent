//
//  L10n.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation

enum L10n {
    static let commonNone = tr("common.none")
    static let commonNotLoaded = tr("common.not_loaded")
    static let appHeaderTitle = tr("app.header.title")
    static let appQuitAction = tr("app.action.quit")
    static let quickActionsTitle = tr("app.panel.quick_actions.title")
    static let saveConfigurationAction = tr("app.action.save_configuration")
    static let reloadFromDiskAction = tr("app.action.reload_from_disk")
    static let discardUnsavedAction = tr("app.action.discard_unsaved")
    static let openConfigurationDirectoryAction = tr("app.action.open_configuration_directory")
    static let configurationPanelTitle = tr("configuration.panel.title")
    static let configurationServerURLLabel = tr("configuration.server_url.label")
    static let configurationServerURLPlaceholder = tr("configuration.server_url.placeholder")
    static let configurationTokenLabel = tr("configuration.token.label")
    static let configurationTokenPlaceholder = tr("configuration.token.placeholder")
    static let configurationIntervalLabel = tr("configuration.interval.label")
    static let configurationHeartbeatLabel = tr("configuration.heartbeat.label")
    static let configurationAfkThresholdLabel = tr("configuration.afk_threshold.label")
    static let configurationEnableLogTitle = tr("configuration.enable_log.title")
    static let configurationEnableLogSubtitle = tr("configuration.enable_log.subtitle")
    static let configurationKeywordFilterTitle = tr("configuration.keyword_filter.title")
    static let configurationKeywordFilterSubtitle = tr("configuration.keyword_filter.subtitle")
    static let configurationKeywordFilterLabel = tr("configuration.keyword_filter.label")
    static let configurationKeywordFilterPlaceholder = tr("configuration.keyword_filter.placeholder")
    static let configurationKeywordFilterEmptyHint = tr("configuration.keyword_filter.empty_hint")
    static let configurationValidationSuccess = tr("configuration.validation.success")
    static let permissionPanelTitle = tr("permission.panel.title")
    static let permissionGrantedTitle = tr("permission.granted.title")
    static let permissionDeniedTitle = tr("permission.denied.title")
    static let permissionGrantedDescription = tr("permission.granted.description")
    static let permissionDeniedDescription = tr("permission.denied.description")
    static let requestAccessibilityPermissionAction = tr("permission.action.request")
    static let permissionStatusShortGranted = tr("permission.status.short.granted")
    static let permissionStatusShortDenied = tr("permission.status.short.denied")
    static let statusPanelTitle = tr("status.panel.title")
    static let statusMetricLifecycleTitle = tr("status.metric.lifecycle")
    static let statusMetricLastReportTitle = tr("status.metric.last_report")
    static let statusMetricCurrentAppTitle = tr("status.metric.current_app")
    static let statusMetricIdleDurationTitle = tr("status.metric.idle_duration")
    static let statusMetricBatteryTitle = tr("status.metric.battery")
    static let statusMetricMusicTitle = tr("status.metric.music")
    static let statusRowWindowTitle = tr("status.row.window_title")
    static let statusRowConfigurationPath = tr("status.row.configuration_path")
    static let statusRowPermissionStatus = tr("status.row.permission_status")
    static let statusRowBackoffWait = tr("status.row.backoff_wait")
    static let statusRowExemption = tr("status.row.exemption")
    static let statusExemptionFullscreen = tr("status.exemption.fullscreen")
    static let statusExemptionAudio = tr("status.exemption.audio")
    static let bannerConfigurationRestored = tr("banner.configuration.restored")
    static let bannerPermissionAvailable = tr("banner.permission.available")
    static let bannerPermissionPrompted = tr("banner.permission.prompted")
    static let bannerConfigurationSaved = tr("banner.configuration.saved")
    static let bannerConfigurationReloaded = tr("banner.configuration.reloaded")
    static let validationServerURLEmpty = tr("validation.server_url.empty")
    static let validationTokenEmpty = tr("validation.token.empty")
    static let validationServerURLInvalid = tr("validation.server_url.invalid")
    static let validationServerURLScheme = tr("validation.server_url.scheme")
    static let validationServerURLHTTPSRequired = tr("validation.server_url.https_required")
    static let statusAppNone = tr("status.app.none")
    static let statusWindowNone = tr("status.window.none")
    static let statusBatteryUnavailable = tr("status.battery.unavailable")
    static let statusBatteryCharging = tr("status.battery.charging")
    static let statusBatteryNotCharging = tr("status.battery.not_charging")
    static let statusMusicNone = tr("status.music.none")
    static let statusReportNone = tr("status.report.none")
    static let coordinatorForegroundUnavailable = tr("coordinator.foreground.unavailable")
    static let coordinatorWindowUnavailable = tr("coordinator.accessibility.window_unavailable")
    static let coordinatorAccessibilityDegraded = tr("coordinator.accessibility.degraded")

    /**
     * 把秒数格式化为统一的本地化时长文案，避免各处重复拼接单位。
     *
     * - Parameter seconds: 需要展示的秒数
     * - Returns: 当前语言环境下的秒数字符串
     */
    static func seconds(_ seconds: Int) -> String {
        tr("common.seconds_format", Int64(seconds))
    }

    /**
     * 生成菜单栏状态图标的辅助功能文案，便于 VoiceOver 正确播报当前状态。
     *
     * - Parameter lifecycleTitle: 当前生命周期显示名称
     * - Returns: 完整的辅助功能标签
     */
    static func menuBarStatusAccessibility(_ lifecycleTitle: String) -> String {
        tr("menu_bar.status.accessibility_format", lifecycleTitle)
    }

    /**
     * 生成电池状态摘要，统一处理百分比和充电状态的本地化拼装。
     *
     * - Parameters:
     *   - percentage: 当前电量百分比
     *   - isCharging: 当前是否正在充电
     * - Returns: 面向用户展示的电池文案
     */
    static func batterySummary(percentage: Int, isCharging: Bool) -> String {
        tr(
            "status.battery.summary_format",
            Int64(percentage),
            isCharging ? statusBatteryCharging : statusBatteryNotCharging
        )
    }

    /**
     * 生成歌曲标题和歌手的展示文案，统一处理分隔符本地化。
     *
     * - Parameters:
     *   - title: 当前曲目标题
     *   - artist: 当前曲目歌手
     * - Returns: 面向用户展示的音乐信息
     */
    static func musicSummary(title: String, artist: String) -> String {
        tr("status.music.track_artist_format", title, artist)
    }

    /**
     * 生成保存失败提示，保留底层错误描述，方便用户排查配置写入问题。
     *
     * - Parameter reason: 保存失败原因
     * - Returns: 完整的失败提示文案
     */
    static func configurationSaveFailed(_ reason: String) -> String {
        tr("banner.configuration.save_failed", reason)
    }

    /**
     * 生成关键词过滤配置的摘要文案，方便用户确认当前会参与脱敏的关键词数量
     *
     * - Parameter count: 当前生效的关键词数量
     * - Returns: 配置页中展示的数量说明文案
     */
    static func configurationKeywordFilterEnabledCount(_ count: Int) -> String {
        tr("configuration.keyword_filter.enabled_count_format", Int64(count))
    }

    /**
     * 生成服务端错误摘要，统一处理状态码和响应体截断后的展示格式。
     *
     * - Parameters:
     *   - statusCode: HTTP 状态码
     *   - responseText: 截断后的响应体文本
     * - Returns: 面向用户展示的服务端错误文案
     */
    static func networkServerError(statusCode: Int, responseText: String) -> String {
        tr("network.server_error_format", Int64(statusCode), responseText)
    }

    /**
     * 生成长暂停提示，让用户明确当前因为连续失败进入了保护性暂停。
     *
     * - Parameters:
     *   - failureCount: 连续失败次数
     *   - pauseSeconds: 暂停秒数
     * - Returns: 面向用户展示的暂停提示文案
     */
    static func networkPauseAfterFailures(failureCount: Int, pauseSeconds: Int) -> String {
        tr("network.pause_after_failures", Int64(failureCount), Int64(pauseSeconds))
    }

    /**
     * 从 `Localizable.xcstrings` 里读取普通字符串，作为项目统一的文案访问入口。
     *
     * - Parameter key: 字符串资源 key
     * - Returns: 当前语言环境下的文案
     */
    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /**
     * 读取并格式化带参数的字符串，避免各业务模块重复写 `String(format:)`。
     *
     * - Parameters:
     *   - key: 字符串资源 key
     *   - arguments: 需要插入文案的参数数组
     * - Returns: 替换占位符后的本地化文案
     */
    private static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: arguments)
    }
}

//
//  NetworkReporter.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation

enum ReportSendResult: Sendable {
    case success
    case failure(backoffSeconds: Int, message: String)
}

actor NetworkReporter {
    private enum Constants {
        static let maxBackoffSeconds = 60
        static let pauseAfterFailureCount = 5
        static let pauseDurationSeconds = 300
    }

    private struct ReportRequestPayload: Encodable {
        let appID: String
        let windowTitle: String
        let timestamp: Int64
        let extra: AgentReportExtra?

        enum CodingKeys: String, CodingKey {
            case appID = "app_id"
            case windowTitle = "window_title"
            case timestamp
            case extra
        }
    }

    private let session: URLSession
    private let encoder = JSONEncoder()
    private var consecutiveFailures = 0
    private var currentBackoffSeconds = 0

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    /**
     * 向后端发送一次使用状态上报，并按 Python 版本规则执行指数退避与长暂停
     *
     * - Parameters:
     *   - appIdentifier: 当前应用标识，AFK 时会传 `idle`
     *   - windowTitle: 当前窗口标题或 AFK 描述
     *   - extra: 电量、音乐等附加字段
     *   - configuration: 当前生效配置
     * - Returns: 上报结果，失败时包含退避时间和错误说明
     */
    func send(
        appIdentifier: String,
        windowTitle: String,
        extra: AgentReportExtra?,
        configuration: AgentConfiguration
    ) async -> ReportSendResult {
        guard let serverURL = configuration.serverURL else {
            return .failure(backoffSeconds: 0, message: L10n.validationServerURLInvalid)
        }

        let endpoint = serverURL.appending(path: "api/report")
        let reportRedactor = ReportKeywordRedactor(keywords: configuration.keywordFilters)
        let payload = ReportRequestPayload(
            appID: reportRedactor.redact(appIdentifier),
            windowTitle: String(reportRedactor.redact(windowTitle).prefix(256)),
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            extra: reportRedactor.redact(extra: extra)
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(configuration.token.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if [200, 201, 409].contains(statusCode) {
                consecutiveFailures = 0
                currentBackoffSeconds = 0
                return .success
            }

            let responseText = String(data: data, encoding: .utf8) ?? ""
            let message = L10n.networkServerError(
                statusCode: statusCode,
                responseText: String(responseText.prefix(200))
            )
            return await handleFailure(message: message)
        } catch {
            return await handleFailure(message: error.localizedDescription)
        }
    }

    /**
     * 更新失败统计并按策略返回退避信息，必要时执行长时间暂停保护
     *
     * - Parameter message: 当前失败的原因说明
     * - Returns: 带退避时间的失败结果
     */
    private func handleFailure(message: String) async -> ReportSendResult {
        consecutiveFailures += 1
        currentBackoffSeconds = currentBackoffSeconds == 0
            ? 5
            : min(currentBackoffSeconds * 2, Constants.maxBackoffSeconds)

        await AppLogger.shared.warning(
            "状态上报失败",
            category: "Reporter",
            metadata: [
                "failures": "\(consecutiveFailures)",
                "backoff": "\(currentBackoffSeconds)",
                "reason": message
            ]
        )

        if consecutiveFailures >= Constants.pauseAfterFailureCount {
            await AppLogger.shared.warning(
                "连续上报失败次数过多，开始长暂停",
                category: "Reporter",
                metadata: ["pause": "\(Constants.pauseDurationSeconds)"]
            )
            await sleep(seconds: Constants.pauseDurationSeconds)
            consecutiveFailures = 0
            currentBackoffSeconds = 0
            return .failure(
                backoffSeconds: 0,
                message: L10n.networkPauseAfterFailures(
                    failureCount: Constants.pauseAfterFailureCount,
                    pauseSeconds: Constants.pauseDurationSeconds
                )
            )
        }

        return .failure(backoffSeconds: currentBackoffSeconds, message: message)
    }

    /**
     * 执行异步秒级等待，供指数退避和长暂停复用
     *
     * - Parameter seconds: 等待秒数，`0` 时直接返回
     */
    private func sleep(seconds: Int) async {
        guard seconds > 0 else {
            return
        }

        let nanoseconds = UInt64(seconds) * 1_000_000_000
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

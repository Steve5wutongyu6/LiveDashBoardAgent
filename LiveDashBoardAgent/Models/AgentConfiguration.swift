//
//  AgentConfiguration.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation

struct AgentConfiguration: Codable, Equatable, Sendable {
    var serverURLString: String = ""
    var token: String = ""
    var intervalSeconds: Int = 5
    var heartbeatSeconds: Int = 60
    var idleThresholdSeconds: Int = 300
    var enableLog: Bool = false

    static let `default` = AgentConfiguration()

    var serverURL: URL? {
        URL(string: serverURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /**
     * 清洗配置里的字符串和数值范围，避免 UI 中的临时脏值直接进入监控流程
     *
     * - Returns: 适合保存和运行的配置副本
     */
    func sanitized() -> AgentConfiguration {
        AgentConfiguration(
            serverURLString: serverURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            intervalSeconds: intervalSeconds.clamped(to: 1...300),
            heartbeatSeconds: heartbeatSeconds.clamped(to: 10...600),
            idleThresholdSeconds: idleThresholdSeconds.clamped(to: 30...3600),
            enableLog: enableLog
        )
    }

    /**
     * 校验配置是否满足后端和本地 Agent 的运行要求
     *
     * - Returns: 校验失败时返回中文错误提示，成功时返回 `nil`
     */
    func validationMessage() -> String? {
        let value = sanitized()
        let trimmedURL = value.serverURLString
        let trimmedToken = value.token

        guard !trimmedURL.isEmpty else {
            return L10n.validationServerURLEmpty
        }

        guard !trimmedToken.isEmpty, trimmedToken != "YOUR_TOKEN_HERE" else {
            return L10n.validationTokenEmpty
        }

        guard let components = URLComponents(string: trimmedURL),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty else {
            return L10n.validationServerURLInvalid
        }

        guard scheme == "http" || scheme == "https" else {
            return L10n.validationServerURLScheme
        }

        if scheme == "http" && !host.isLikelyPrivateNetworkHost {
            return L10n.validationServerURLHTTPSRequired
        }

        return nil
    }
}

private extension Int {
    /**
     * 把输入整数限制到指定闭区间内，防止非法间隔导致轮询过快或过慢
     *
     * - Parameter range: 允许的整数范围
     * - Returns: 限制后的整数值
     */
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension String {
    /**
     * 用轻量规则判断主机名是否属于本地或内网地址，避免误把公网 HTTP 当作合法配置
     *
     * - Returns: `true` 代表看起来像内网主机，`false` 代表更接近公网主机
     */
    var isLikelyPrivateNetworkHost: Bool {
        let host = lowercased()

        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4 {
            switch (octets[0], octets[1]) {
            case (10, _):
                return true
            case (127, _):
                return true
            case (172, 16...31):
                return true
            case (192, 168):
                return true
            default:
                return false
            }
        }

        if host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:") {
            return true
        }

        return false
    }
}

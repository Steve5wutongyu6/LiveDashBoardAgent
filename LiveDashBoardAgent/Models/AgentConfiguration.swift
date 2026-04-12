//
//  AgentConfiguration.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation

struct AgentConfiguration: Codable, Equatable, Sendable {
    var serverURLString: String
    var token: String
    var intervalSeconds: Int
    var heartbeatSeconds: Int
    var idleThresholdSeconds: Int
    var enableLog: Bool
    var keywordFilterText: String

    enum CodingKeys: String, CodingKey {
        case serverURLString
        case token
        case intervalSeconds
        case heartbeatSeconds
        case idleThresholdSeconds
        case enableLog
        case keywordFilterText
    }

    /**
     * 初始化一份可保存、可运行的 Agent 配置，兼容默认值和旧版本配置文件缺省字段
     *
     * - Parameters:
     *   - serverURLString: 服务端基础地址
     *   - token: 上报鉴权令牌
     *   - intervalSeconds: 前台轮询间隔
     *   - heartbeatSeconds: 心跳上报间隔
     *   - idleThresholdSeconds: AFK 判定阈值
     *   - enableLog: 是否启用文件日志
     *   - keywordFilterText: 关键词过滤文本，多个关键词使用 `|` 分隔
     */
    init(
        serverURLString: String = "",
        token: String = "",
        intervalSeconds: Int = 5,
        heartbeatSeconds: Int = 60,
        idleThresholdSeconds: Int = 300,
        enableLog: Bool = false,
        keywordFilterText: String = ""
    ) {
        self.serverURLString = serverURLString
        self.token = token
        self.intervalSeconds = intervalSeconds
        self.heartbeatSeconds = heartbeatSeconds
        self.idleThresholdSeconds = idleThresholdSeconds
        self.enableLog = enableLog
        self.keywordFilterText = keywordFilterText
    }

    /**
     * 从磁盘配置中解码运行参数，对新增字段提供默认值，避免旧版 `config.json` 读取失败
     *
     * - Parameter decoder: Swift 解码器
     * - Throws: 当基础字段类型不匹配时抛出解码错误
     */
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.serverURLString = try container.decodeIfPresent(String.self, forKey: .serverURLString) ?? ""
        self.token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        self.intervalSeconds = try container.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? 5
        self.heartbeatSeconds = try container.decodeIfPresent(Int.self, forKey: .heartbeatSeconds) ?? 60
        self.idleThresholdSeconds = try container.decodeIfPresent(Int.self, forKey: .idleThresholdSeconds) ?? 300
        self.enableLog = try container.decodeIfPresent(Bool.self, forKey: .enableLog) ?? false
        self.keywordFilterText = try container.decodeIfPresent(String.self, forKey: .keywordFilterText) ?? ""
    }

    static let `default` = AgentConfiguration()

    var serverURL: URL? {
        URL(string: serverURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /**
     * 返回当前配置实际会生效的关键词数组，供 UI 预览和上报脱敏共用
     *
     * - Returns: 去空格、去空项后的关键词列表
     */
    var keywordFilters: [String] {
        Self.normalizedKeywordFilterText(keywordFilterText)
            .split(separator: "|")
            .map(String.init)
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
            enableLog: enableLog,
            keywordFilterText: Self.normalizedKeywordFilterText(keywordFilterText)
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

    /**
     * 规范化关键词过滤文本，统一去掉空项和首尾空白，避免保存无效分隔符
     *
     * - Parameter text: 用户输入的原始关键词文本
     * - Returns: 可直接保存和运行的关键词字符串
     */
    private static func normalizedKeywordFilterText(_ text: String) -> String {
        text
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "|")
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

//
//  ReportKeywordRedactor.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation

struct ReportKeywordRedactor: Sendable {
    private let regularExpression: NSRegularExpression?

    /**
     * 根据配置中的关键词列表构建统一脱敏器，保证上报链路和日志摘要复用同一套规则
     *
     * - Parameter keywords: 已解析的关键词数组
     */
    init(keywords: [String]) {
        let normalizedKeywords = Self.normalizedKeywords(from: keywords)

        guard !normalizedKeywords.isEmpty else {
            self.regularExpression = nil
            return
        }

        let pattern = normalizedKeywords
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        self.regularExpression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /**
     * 将文本中的敏感关键词替换为 `***`，未配置关键词时直接返回原文
     *
     * - Parameter text: 原始文本
     * - Returns: 关键词命中后替换完成的文本
     */
    func redact(_ text: String) -> String {
        guard let regularExpression, !text.isEmpty else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regularExpression.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "***"
        )
    }

    /**
     * 对音乐快照中的文本字段做统一脱敏，避免歌名或歌手信息透出配置关键词
     *
     * - Parameter snapshot: 原始音乐快照
     * - Returns: 脱敏后的音乐快照；为空时返回 `nil`
     */
    func redact(musicSnapshot snapshot: MusicSnapshot?) -> MusicSnapshot? {
        guard let snapshot else {
            return nil
        }

        return MusicSnapshot(
            app: redact(snapshot.app),
            title: redact(snapshot.title),
            artist: snapshot.artist.map { redact($0) }
        )
    }

    /**
     * 对上报附加字段中的文本内容做统一脱敏，避免附加信息绕过主标题过滤
     *
     * - Parameter extra: 原始附加字段
     * - Returns: 脱敏后的附加字段；为空时返回 `nil`
     */
    func redact(extra: AgentReportExtra?) -> AgentReportExtra? {
        guard let extra else {
            return nil
        }

        return AgentReportExtra(
            batteryPercent: extra.batteryPercent,
            batteryCharging: extra.batteryCharging,
            music: redact(musicSnapshot: extra.music)
        )
    }

    /**
     * 规范化关键词数组，统一去空白并按忽略大小写方式去重，避免重复匹配浪费性能
     *
     * - Parameter keywords: 原始关键词数组
     * - Returns: 可用于正则构建的关键词列表
     */
    private static func normalizedKeywords(from keywords: [String]) -> [String] {
        var normalizedKeywords: [String] = []
        var seenKeywords = Set<String>()

        for keyword in keywords {
            let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            let dedupeKey = trimmedKeyword.lowercased()

            guard !trimmedKeyword.isEmpty, seenKeywords.insert(dedupeKey).inserted else {
                continue
            }

            normalizedKeywords.append(trimmedKeyword)
        }

        return normalizedKeywords
    }
}

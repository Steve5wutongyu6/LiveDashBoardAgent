//
//  AppLogger.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation
import OSLog

actor AppLogger {
    static let shared = AppLogger()

    private let subsystem = Bundle.main.bundleIdentifier ?? "LiveDashBoardAgent"
    private let calendar = Calendar(identifier: .gregorian)
    private let fileManager = FileManager.default
    private let timestampFormatter = ISO8601DateFormatter()

    private var baseDirectoryURL: URL?
    private var fileLoggingEnabled = false

    /**
     * 配置日志输出目录和文件开关，确保设置页保存后日志行为立即生效
     *
     * - Parameters:
     *   - baseDirectoryURL: 当前配置文件所在目录，日志会写入它下面的 `Logs`
     *   - fileLoggingEnabled: 是否启用文件日志
     */
    func configure(baseDirectoryURL: URL, fileLoggingEnabled: Bool) async {
        self.baseDirectoryURL = baseDirectoryURL
        self.fileLoggingEnabled = fileLoggingEnabled

        if fileLoggingEnabled {
            do {
                try fileManager.createDirectory(at: logsDirectoryURL(), withIntermediateDirectories: true)
                try pruneExpiredLogs(referenceDate: Date())
            } catch {
                let logger = Logger(subsystem: subsystem, category: "Logging")
                logger.error("日志目录初始化失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /**
     * 输出普通信息日志，便于记录状态流转和轮询结果
     *
     * - Parameters:
     *   - message: 主要日志内容
     *   - category: 日志模块分类
     *   - metadata: 额外上下文字段
     */
    func info(_ message: String, category: String = "Agent", metadata: [String: String] = [:]) async {
        await log(level: "INFO", category: category, message: message, metadata: metadata)
    }

    /**
     * 输出告警日志，便于记录可恢复失败和权限异常
     *
     * - Parameters:
     *   - message: 主要日志内容
     *   - category: 日志模块分类
     *   - metadata: 额外上下文字段
     */
    func warning(_ message: String, category: String = "Agent", metadata: [String: String] = [:]) async {
        await log(level: "WARN", category: category, message: message, metadata: metadata)
    }

    /**
     * 输出错误日志，便于定位失败链路和不可恢复问题
     *
     * - Parameters:
     *   - message: 主要日志内容
     *   - category: 日志模块分类
     *   - metadata: 额外上下文字段
     */
    func error(_ message: String, category: String = "Agent", metadata: [String: String] = [:]) async {
        await log(level: "ERROR", category: category, message: message, metadata: metadata)
    }

    /**
     * 按级别输出结构化日志，并在开启文件日志时落盘
     *
     * - Parameters:
     *   - level: 文本化日志级别
     *   - category: 日志模块分类
     *   - message: 主要日志内容
     *   - metadata: 额外上下文字段
     */
    private func log(level: String, category: String, message: String, metadata: [String: String]) async {
        let logger = Logger(subsystem: subsystem, category: category)
        let line = formatLine(level: level, category: category, message: message, metadata: metadata)

        switch level {
        case "WARN":
            logger.warning("\(line, privacy: .public)")
        case "ERROR":
            logger.error("\(line, privacy: .public)")
        default:
            logger.info("\(line, privacy: .public)")
        }

        guard fileLoggingEnabled else {
            return
        }

        do {
            try append(line: line)
        } catch {
            logger.error("日志写入失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /**
     * 生成最终写入控制台和文件的日志文本
     *
     * - Parameters:
     *   - level: 文本化日志级别
     *   - category: 日志模块分类
     *   - message: 主要日志内容
     *   - metadata: 额外上下文字段
     * - Returns: 带时间戳和上下文的单行日志
     */
    private func formatLine(level: String, category: String, message: String, metadata: [String: String]) -> String {
        let timestamp = timestampFormatter.string(from: Date())
        let metadataText = metadata.isEmpty
            ? ""
            : " | " + metadata
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
        return "\(timestamp) [\(level)] [\(category)] \(message)\(metadataText)"
    }

    /**
     * 把一条日志追加到当天文件中，并顺手执行过期清理
     *
     * - Parameter line: 已经格式化完成的单行日志
     * - Throws: 当目录创建、文件打开或写入失败时抛出对应错误
     */
    private func append(line: String) throws {
        let directoryURL = logsDirectoryURL()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try pruneExpiredLogs(referenceDate: Date())

        let fileURL = logFileURL(for: Date())
        let data = Data((line + "\n").utf8)

        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: data)
            return
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /**
     * 返回日志目录路径，默认位于配置目录下的 `Logs`
     *
     * - Returns: 日志目录 URL
     */
    private func logsDirectoryURL() -> URL {
        let rootDirectory = baseDirectoryURL ?? FileManager.default.temporaryDirectory
        return rootDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    /**
     * 计算指定日期对应的日志文件名，按天滚动避免单文件持续膨胀
     *
     * - Parameter date: 需要写入的目标日期
     * - Returns: 当天日志文件 URL
     */
    private func logFileURL(for date: Date) -> URL {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let name = String(format: "agent-%04d-%02d-%02d.log", year, month, day)
        return logsDirectoryURL().appendingPathComponent(name)
    }

    /**
     * 删除两天前的旧日志文件，控制磁盘占用并保持与 Python 版本相近的保留周期
     *
     * - Parameter referenceDate: 当前参考时间
     * - Throws: 当目录枚举或删除失败时抛出对应错误
     */
    private func pruneExpiredLogs(referenceDate: Date) throws {
        let cutoffDate = calendar.date(byAdding: .day, value: -2, to: referenceDate) ?? referenceDate
        let urls = try fileManager.contentsOfDirectory(
            at: logsDirectoryURL(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension == "log" {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if modifiedAt < cutoffDate {
                try fileManager.removeItem(at: url)
            }
        }
    }
}

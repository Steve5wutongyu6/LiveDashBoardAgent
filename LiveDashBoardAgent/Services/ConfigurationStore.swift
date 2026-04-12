//
//  ConfigurationStore.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation

struct LoadedConfiguration: Sendable {
    let configuration: AgentConfiguration
    let fileURL: URL
    let displayPath: String
    let directoryURL: URL
}

actor ConfigurationStore {
    private let fileManager = FileManager.default

    /**
     * 读取当前可用的配置文件，优先使用外置 `config.json`，不存在时回落到 Application Support
     *
     * - Returns: 包含配置内容和来源路径的结果对象
     */
    func loadConfiguration() async -> LoadedConfiguration {
        for fileURL in candidateConfigurationURLs() where fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoded = try JSONDecoder().decode(AgentConfiguration.self, from: data).sanitized()
                return makeLoadedConfiguration(configuration: decoded, fileURL: fileURL)
            } catch {
                await AppLogger.shared.error(
                    "配置文件读取失败，已回退默认配置",
                    category: "Configuration",
                    metadata: ["path": fileURL.path, "error": error.localizedDescription]
                )
                return makeLoadedConfiguration(configuration: .default, fileURL: defaultConfigurationFileURL())
            }
        }

        return makeLoadedConfiguration(configuration: .default, fileURL: defaultConfigurationFileURL())
    }

    /**
     * 把最新配置安全写入磁盘，避免半写入状态破坏 JSON 内容
     *
     * - Parameters:
     *   - configuration: 已经准备保存的配置对象
     *   - preferredFileURL: 当前优先使用的配置文件路径，通常来自上一次加载结果
     * - Returns: 保存后的完整配置结果
     * - Throws: 当目录创建、编码或原子替换失败时抛出对应错误
     */
    func saveConfiguration(_ configuration: AgentConfiguration, preferredFileURL: URL?) async throws -> LoadedConfiguration {
        let targetURL = preferredFileURL ?? defaultConfigurationFileURL()
        try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration.sanitized())

        let temporaryURL = targetURL
            .deletingLastPathComponent()
            .appendingPathComponent(".config-\(UUID().uuidString).tmp")

        try data.write(to: temporaryURL, options: .atomic)

        if fileManager.fileExists(atPath: targetURL.path) {
            _ = try fileManager.replaceItemAt(targetURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
        }

        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetURL.path)
        return makeLoadedConfiguration(configuration: configuration.sanitized(), fileURL: targetURL)
    }

    /**
     * 返回默认配置文件路径，供首次保存和打开目录按钮使用
     *
     * - Returns: 位于 Application Support 中的 `config.json` 路径
     */
    func defaultConfigurationFileURL() -> URL {
        applicationSupportDirectoryURL().appendingPathComponent("config.json")
    }

    /**
     * 汇总所有候选配置路径，保持“外置配置优先、应用私有目录兜底”的读取顺序
     *
     * - Returns: 去重后的候选路径数组
     */
    private func candidateConfigurationURLs() -> [URL] {
        var urls: [URL] = []
        let bundleParentURL = Bundle.main.bundleURL.deletingLastPathComponent()
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        for candidate in [
            bundleParentURL.appendingPathComponent("config.json"),
            currentDirectoryURL.appendingPathComponent("config.json"),
            defaultConfigurationFileURL()
        ] where !urls.contains(candidate) {
            urls.append(candidate)
        }

        return urls
    }

    /**
     * 生成 Application Support 下的应用工作目录，用于存放默认配置和日志
     *
     * - Returns: 应用私有工作目录
     */
    private func applicationSupportDirectoryURL() -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent("LiveDashBoardAgent", isDirectory: true)
    }

    /**
     * 把配置对象和路径信息整理成统一结果，便于 UI 和监控层直接消费
     *
     * - Parameters:
     *   - configuration: 已读取或已保存的配置对象
     *   - fileURL: 配置文件路径
     * - Returns: 包含展示路径和目录信息的完整配置结果
     */
    private func makeLoadedConfiguration(configuration: AgentConfiguration, fileURL: URL) -> LoadedConfiguration {
        LoadedConfiguration(
            configuration: configuration,
            fileURL: fileURL,
            displayPath: fileURL.path,
            directoryURL: fileURL.deletingLastPathComponent()
        )
    }
}

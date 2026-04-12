//
//  AppleScriptMusicService.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import AppKit
import Foundation

actor MusicDetectionService {
    private static let scripts: [(appName: String, source: String)] = [
        (
            appName: "Spotify",
            source: """
            tell application "System Events"
                if not (exists process "Spotify") then return "NOT_RUNNING"
            end tell
            tell application "Spotify"
                if player state is not playing then return "NOT_PLAYING"
                set t to name of current track
                set a to artist of current track
                return t & "|SEP|" & a
            end tell
            """
        ),
        (
            appName: "Music",
            source: """
            tell application "System Events"
                if not (exists process "Music") then return "NOT_RUNNING"
            end tell
            tell application "Music"
                if player state is not playing then return "NOT_PLAYING"
                set t to name of current track
                set a to artist of current track
                return t & "|SEP|" & a
            end tell
            """
        ),
        (
            appName: "QQ音乐",
            source: """
            tell application "System Events"
                if not (exists process "QQMusic") then return "NOT_RUNNING"
                tell process "QQMusic"
                    set t to title of front window
                end tell
                return t
            end tell
            """
        ),
        (
            appName: "网易云音乐",
            source: """
            tell application "System Events"
                if not (exists process "NeteaseMusic") then return "NOT_RUNNING"
                tell process "NeteaseMusic"
                    set t to title of front window
                end tell
                return t
            end tell
            """
        )
    ]

    /**
     * 顺序查询支持的音乐应用，返回第一条正在播放的音乐信息
     *
     * - Returns: 歌曲快照，没有任何播放内容时返回 `nil`
     */
    func currentMusicSnapshot() async -> MusicSnapshot? {
        for script in Self.scripts {
            guard let output = await executeAppleScript(script.source, appName: script.appName) else {
                continue
            }

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "NOT_RUNNING", trimmed != "NOT_PLAYING" else {
                continue
            }

            return parseMusicOutput(trimmed, appName: script.appName)
        }

        return nil
    }

    /**
     * 执行内联 AppleScript，并把错误写入结构化日志方便排查权限问题
     *
     * - Parameters:
     *   - source: AppleScript 源码
     *   - appName: 当前脚本对应的音乐应用名
     * - Returns: AppleScript 返回的文本，执行失败时返回 `nil`
     */
    private func executeAppleScript(_ source: String, appName: String) async -> String? {
        var executionError: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        let descriptor = script.executeAndReturnError(&executionError)

        if let executionError {
            await AppLogger.shared.warning(
                "音乐脚本执行失败",
                category: "Music",
                metadata: [
                    "app": appName,
                    "error": executionError.description
                ]
            )
            return nil
        }

        return descriptor.stringValue
    }

    /**
     * 解析各音乐应用返回的文本结果，统一转成后端上报所需的数据结构
     *
     * - Parameters:
     *   - output: AppleScript 返回文本
     *   - appName: 当前音乐应用名
     * - Returns: 解析成功的歌曲快照
     */
    private func parseMusicOutput(_ output: String, appName: String) -> MusicSnapshot {
        if output.contains("|SEP|") {
            let components = output.components(separatedBy: "|SEP|")
            let title = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let artist = components.dropFirst().joined(separator: "|SEP|").trimmingCharacters(in: .whitespacesAndNewlines)
            return MusicSnapshot(
                app: appName,
                title: String(title.prefix(256)),
                artist: artist.isEmpty ? nil : String(artist.prefix(256))
            )
        }

        if output.contains(" - ") {
            let components = output.components(separatedBy: " - ")
            let title = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? output
            let artist = components.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
            return MusicSnapshot(
                app: appName,
                title: String(title.prefix(256)),
                artist: artist.isEmpty ? nil : String(artist.prefix(256))
            )
        }

        return MusicSnapshot(app: appName, title: String(output.prefix(256)), artist: nil)
    }
}

//
//  ForegroundWorkspaceService.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import AppKit
import ApplicationServices
import Foundation

struct AccessibilityPermissionService {
    /**
     * 查询当前进程是否拥有辅助功能权限，并按需触发系统授权弹窗
     *
     * - Parameter promptIfNeeded: 是否在权限缺失时让系统弹出授权提示
     * - Returns: `true` 代表已经具备权限，`false` 代表仍然缺失权限
     */
    func isTrusted(promptIfNeeded: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

struct ForegroundWorkspaceService {
    /**
     * 读取当前前台应用和聚焦窗口信息，用于决定上报的应用名、窗口标题和全屏状态
     *
     * - Parameter accessibilityGranted: 当前是否具备辅助功能权限
     * - Returns: 成功时返回前台窗口快照，失败时返回 `nil`
     */
    func currentSnapshot(accessibilityGranted: Bool) -> ForegroundWindowSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = application.localizedName ?? application.bundleIdentifier ?? "Unknown"
        guard accessibilityGranted else {
            return ForegroundWindowSnapshot(
                appName: appName,
                windowTitle: "",
                bundleIdentifier: application.bundleIdentifier,
                isFullscreen: false
            )
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let windowElement = focusedWindowElement(for: applicationElement)
        let windowTitle = windowElement.flatMap { stringValue(from: $0, attribute: kAXTitleAttribute as CFString) } ?? ""
        let isFullscreen = windowElement.flatMap { booleanValue(from: $0, attribute: "AXFullScreen" as CFString) } ?? false

        return ForegroundWindowSnapshot(
            appName: appName,
            windowTitle: windowTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: application.bundleIdentifier,
            isFullscreen: isFullscreen
        )
    }

    /**
     * 读取前台应用的聚焦窗口元素，方便后续取窗口标题和全屏属性
     *
     * - Parameter applicationElement: 前台应用对应的辅助功能元素
     * - Returns: 聚焦窗口元素，不存在时返回 `nil`
     */
    private func focusedWindowElement(for applicationElement: AXUIElement) -> AXUIElement? {
        guard let value = attributeValue(from: applicationElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    /**
     * 从辅助功能元素读取字符串属性，适用于窗口标题等文案字段
     *
     * - Parameters:
     *   - element: 目标辅助功能元素
     *   - attribute: 需要读取的属性名
     * - Returns: 成功时返回字符串，失败时返回 `nil`
     */
    private func stringValue(from element: AXUIElement, attribute: CFString) -> String? {
        attributeValue(from: element, attribute: attribute) as? String
    }

    /**
     * 从辅助功能元素读取布尔属性，适用于全屏状态等开关字段
     *
     * - Parameters:
     *   - element: 目标辅助功能元素
     *   - attribute: 需要读取的属性名
     * - Returns: 成功时返回布尔值，失败时返回 `nil`
     */
    private func booleanValue(from element: AXUIElement, attribute: CFString) -> Bool? {
        attributeValue(from: element, attribute: attribute) as? Bool
    }

    /**
     * 从辅助功能元素拷贝原始属性值，统一封装底层 AX API 的错误处理
     *
     * - Parameters:
     *   - element: 目标辅助功能元素
     *   - attribute: 需要读取的属性名
     * - Returns: 底层复制到的 Core Foundation 值，失败时返回 `nil`
     */
    private func attributeValue(from element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }
        return value
    }
}

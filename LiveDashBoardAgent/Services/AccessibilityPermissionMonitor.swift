//
//  AccessibilityPermissionMonitor.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/14.
//

import Foundation

final class AccessibilityPermissionMonitor {
    private let permissionService = AccessibilityPermissionService()
    private var pollingTask: Task<Void, Never>?

    deinit {
        pollingTask?.cancel()
    }

    /**
     * 启动辅助功能权限轮询，确保用户在系统设置中授权后界面能尽快刷新
     *
     * - Parameters:
     *   - pollIntervalSeconds: 轮询间隔秒数
     *   - onChange: 权限状态变化或首次读取后的回调
     */
    func startMonitoring(
        pollIntervalSeconds: Double = 1,
        onChange: @escaping @Sendable (Bool) async -> Void
    ) {
        stopMonitoring()

        pollingTask = Task { [weak self] in
            guard let self else {
                return
            }

            var lastKnownGranted = self.permissionService.isTrusted(promptIfNeeded: false)
            await onChange(lastKnownGranted)

            while !Task.isCancelled {
                let nanoseconds = UInt64(max(pollIntervalSeconds, 0.2) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)

                let currentGranted = self.permissionService.isTrusted(promptIfNeeded: false)
                guard currentGranted != lastKnownGranted else {
                    continue
                }

                lastKnownGranted = currentGranted
                await onChange(currentGranted)
            }
        }
    }

    /**
     * 停止权限轮询任务，供应用退出或仓库释放时回收资源
     *
     * - Returns: 无返回值
     */
    func stopMonitoring() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}

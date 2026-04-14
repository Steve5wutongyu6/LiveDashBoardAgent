//
//  SystemBroadcastReceiver.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/14.
//

import AppKit
import Foundation
import Network

enum NetworkReachabilityState: String, Equatable, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

struct NetworkPathSnapshot: Equatable, Sendable {
    let state: NetworkReachabilityState
    let interfaceTypes: [String]
    let isExpensive: Bool
    let isConstrained: Bool

    var isReachable: Bool {
        state == .satisfied
    }

    var summary: String {
        let interfaces = interfaceTypes.isEmpty ? "none" : interfaceTypes.joined(separator: "+")
        return "\(state.rawValue), interfaces=\(interfaces), expensive=\(isExpensive), constrained=\(isConstrained)"
    }
}

enum SystemBroadcastEvent: Sendable {
    case networkChanged(current: NetworkPathSnapshot, previous: NetworkPathSnapshot?)
    case screenLockChanged(isLocked: Bool)
}

final class SystemBroadcastReceiver {
    private enum Constants {
        static let networkQueueLabel = "com.livedashboardagent.network-monitor"
        static let screenLockedNotification = Notification.Name("com.apple.screenIsLocked")
        static let screenUnlockedNotification = Notification.Name("com.apple.screenIsUnlocked")
    }

    private let networkQueue = DispatchQueue(label: Constants.networkQueueLabel)

    private var networkMonitor: NWPathMonitor?
    private var latestNetworkSnapshot: NetworkPathSnapshot?
    private var latestScreenLocked = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    /**
     * 启动系统事件监听，统一接收网络变化和锁屏状态变化
     *
     * - Parameter onEvent: 广播事件回调
     */
    func start(onEvent: @escaping @Sendable (SystemBroadcastEvent) -> Void) {
        stop()
        latestNetworkSnapshot = nil
        latestScreenLocked = false

        startNetworkMonitoring(onEvent: onEvent)
        startScreenLockMonitoring(onEvent: onEvent)
    }

    /**
     * 停止全部系统事件监听，避免重复注册和资源泄漏
     *
     * - Returns: 无返回值
     */
    func stop() {
        networkMonitor?.cancel()
        networkMonitor = nil
        latestNetworkSnapshot = nil

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        workspaceObservers.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.forEach { distributedCenter.removeObserver($0) }
        distributedObservers.removeAll()
    }

    /**
     * 启动网络状态监听，在网络可达性或链路类型变化时触发回调
     *
     * - Parameter onEvent: 广播事件回调
     */
    private func startNetworkMonitoring(onEvent: @escaping @Sendable (SystemBroadcastEvent) -> Void) {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkPathUpdate(path, onEvent: onEvent)
        }
        monitor.start(queue: networkQueue)
        networkMonitor = monitor
    }

    /**
     * 把系统 `NWPath` 转成可比较快照，并在真正变化时向上层派发事件
     *
     * - Parameters:
     *   - path: 当前网络路径对象
     *   - onEvent: 广播事件回调
     */
    private func handleNetworkPathUpdate(_ path: NWPath, onEvent: @escaping @Sendable (SystemBroadcastEvent) -> Void) {
        let currentSnapshot = NetworkPathSnapshot(
            state: networkReachabilityState(from: path.status),
            interfaceTypes: [.wifi, .wiredEthernet, .cellular, .loopback, .other]
                .filter { path.usesInterfaceType($0) }
                .map(\.displayName),
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )

        let previousSnapshot = latestNetworkSnapshot
        latestNetworkSnapshot = currentSnapshot

        guard let previousSnapshot, previousSnapshot != currentSnapshot else {
            return
        }

        onEvent(.networkChanged(current: currentSnapshot, previous: previousSnapshot))
    }

    /**
     * 启动锁屏/解锁监听，同时兼容登录窗口广播和工作区会话通知
     *
     * - Parameter onEvent: 广播事件回调
     */
    private func startScreenLockMonitoring(onEvent: @escaping @Sendable (SystemBroadcastEvent) -> Void) {
        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.append(
            distributedCenter.addObserver(forName: Constants.screenLockedNotification, object: nil, queue: .main) { [weak self] _ in
                self?.emitScreenLockChange(true, onEvent: onEvent)
            }
        )
        distributedObservers.append(
            distributedCenter.addObserver(forName: Constants.screenUnlockedNotification, object: nil, queue: .main) { [weak self] _ in
                self?.emitScreenLockChange(false, onEvent: onEvent)
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.emitScreenLockChange(true, onEvent: onEvent)
            }
        )
        workspaceObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.emitScreenLockChange(false, onEvent: onEvent)
            }
        )
    }

    /**
     * 对锁屏状态变化做去重，避免同一状态被多个系统通知重复派发
     *
     * - Parameters:
     *   - isLocked: 当前是否处于锁屏态
     *   - onEvent: 广播事件回调
     */
    private func emitScreenLockChange(_ isLocked: Bool, onEvent: @escaping @Sendable (SystemBroadcastEvent) -> Void) {
        guard latestScreenLocked != isLocked else {
            return
        }

        latestScreenLocked = isLocked
        onEvent(.screenLockChanged(isLocked: isLocked))
    }

    /**
     * 把 `NWPath.Status` 转成项目内部可序列化的网络状态枚举
     *
     * - Parameter status: 系统网络可达性状态
     * - Returns: 项目内部统一状态
     */
    private func networkReachabilityState(from status: NWPath.Status) -> NetworkReachabilityState {
        switch status {
        case .satisfied:
            return .satisfied
        case .requiresConnection:
            return .requiresConnection
        default:
            return .unsatisfied
        }
    }
}

private extension NWInterface.InterfaceType {
    var displayName: String {
        switch self {
        case .wifi:
            return "wifi"
        case .wiredEthernet:
            return "ethernet"
        case .cellular:
            return "cellular"
        case .loopback:
            return "loopback"
        default:
            return "other"
        }
    }
}

//
//  SystemEnvironmentService.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import Foundation
import IOKit
import IOKit.ps

struct IdleTimeService {
    /**
     * 读取系统自上次键鼠输入以来的空闲秒数，用于 AFK 判定
     *
     * - Returns: 空闲秒数，读取失败时返回 `0`
     */
    func idleSeconds() -> Double {
        let matchingDictionary = IOServiceMatching("IOHIDSystem")
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator)

        guard result == KERN_SUCCESS else {
            return 0
        }

        defer { IOObjectRelease(iterator) }
        let entry = IOIteratorNext(iterator)

        guard entry != 0 else {
            return 0
        }

        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return 0
        }

        if let number = value as? NSNumber {
            return number.doubleValue / 1_000_000_000
        }

        if let data = value as? Data {
            var nanoseconds: UInt64 = 0
            let count = min(data.count, MemoryLayout<UInt64>.size)
            _ = withUnsafeMutableBytes(of: &nanoseconds) { buffer in
                data.copyBytes(to: buffer.bindMemory(to: UInt8.self), count: count)
            }
            return Double(nanoseconds) / 1_000_000_000
        }

        return 0
    }
}

struct BatteryInfoService {
    /**
     * 读取 Mac 电池电量和充电状态，没有内置电池时返回 `nil`
     *
     * - Returns: 电池快照，桌面机或读取失败时返回 `nil`
     */
    func currentBatterySnapshot() -> BatterySnapshot? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as Array

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int else {
                continue
            }

            let percentage = maxCapacity > 0
                ? Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
                : currentCapacity

            let isCharging = (description[kIOPSIsChargingKey as String] as? Bool) ?? false
            return BatterySnapshot(percentage: percentage, isCharging: isCharging)
        }

        return nil
    }
}

actor AudioPlaybackService {
    /**
     * 检查系统当前是否存在活跃音频输出，用于“看视频/听歌不进 AFK”的豁免逻辑
     *
     * - Returns: `true` 代表检测到活跃音频，`false` 代表未检测到
     */
    func isAudioPlaying() async -> Bool {
        guard let output = executeProcess(executablePath: "/usr/bin/pmset", arguments: ["-g", "assertions"]) else {
            return false
        }

        return output
            .split(separator: "\n")
            .map { $0.lowercased() }
            .contains { $0.contains("preventuseridlesleep") && $0.contains("coreaudiod") }
    }

    /**
     * 执行只读系统命令并拿到标准输出，供音频状态检测等轻量查询复用
     *
     * - Parameters:
     *   - executablePath: 可执行文件完整路径
     *   - arguments: 命令参数列表
     * - Returns: 标准输出文本，执行失败时返回 `nil`
     */
    private func executeProcess(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

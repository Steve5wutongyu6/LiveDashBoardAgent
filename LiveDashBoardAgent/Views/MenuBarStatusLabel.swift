//
//  MenuBarStatusLabel.swift
//  LiveDashBoardAgent
//
//  Created by Codex on 2026/4/12.
//

import AppKit
import SwiftUI

struct MenuBarStatusLabel: View {
    let runtimeState: AgentRuntimeState

    var body: some View {
        Image(nsImage: statusIcon)
            .renderingMode(.original)
            .frame(width: 12, height: 12)
            .padding(.horizontal, 4)
            .accessibilityLabel(Text(L10n.menuBarStatusAccessibility(runtimeState.lifecycle.localizedTitle)))
    }

    private var statusIcon: NSImage {
        MenuBarStatusIconFactory.makeStatusIcon(for: runtimeState.lifecycle)
    }
}

enum MenuBarStatusIconFactory {
    /**
     * 根据运行时生命周期生成菜单栏状态图标。
     * 图标使用矢量路径绘制，避免位图缩放后模糊。
     *
     * - Parameter lifecycle: 当前运行态生命周期
     * - Returns: 可直接用于菜单栏的状态图标
     */
    static func makeStatusIcon(for lifecycle: AgentLifecycleState) -> NSImage {
        switch lifecycle {
        case .running:
            return makeCircleImage(fillColor: .systemGreen)
        case .stopped:
            return makeCircleImage(fillColor: .systemRed)
        case .away, .waitingPermission, .configurationRequired, .error:
            return makeCircleImage(fillColor: .systemYellow)
        }
    }

    /**
     * 使用矢量圆形路径绘制菜单栏状态图标。
     * 通过关闭模板模式，确保菜单栏显示实际颜色而不是系统单色模板。
     *
     * - Parameter fillColor: 圆点填充颜色
     * - Returns: 绘制完成的菜单栏圆点图标
     */
    private static func makeCircleImage(fillColor: NSColor) -> NSImage {
        let canvasSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: canvasSize)
        image.isTemplate = false

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

        let insetRect = NSRect(origin: .zero, size: canvasSize).insetBy(dx: 3, dy: 3)
        let circlePath = NSBezierPath(ovalIn: insetRect)
        fillColor.setFill()
        circlePath.fill()

        NSColor.black.withAlphaComponent(0.16).setStroke()
        circlePath.lineWidth = 1
        circlePath.stroke()

        return image
    }
}

struct SvgCircleShape: Shape {
    /**
     * 用矢量路径绘制圆形状态图标，缩放时保持和 SVG 一样的清晰度
     *
     * - Parameter rect: SwiftUI 提供的绘制区域
     * - Returns: 圆形图标对应的矢量路径
     */
    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        return Path(ellipseIn: insetRect)
    }
}

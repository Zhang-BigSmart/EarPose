import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// 唯一调用 `CGEvent` 的出口。未获辅助功能时全部空操作并返回 false。
enum PointerDriver {
    /// 是否已在「辅助功能」中勾选本 App。
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统辅助功能提示（若尚未授权）。
    /// - Returns: 调用后立刻查询的结果；用户可能还没勾选。
    @discardableResult
    static func promptIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// 打开系统设置里的辅助功能页。打不开则静默失败。
    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    /// 打开运动与健身相关设置（macOS 隐私页）。
    static func openMotionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 把指针移到 Quartz 坐标。
    /// - Returns: 未授权时 false，不发事件。
    @discardableResult
    static func move(to point: CGPoint) -> Bool {
        guard isTrusted() else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
        return true
    }

    /// 向前台窗口敲一次按键（按下 + 抬起）。不改指针位置。
    /// - Parameter keyCode: macOS 虚拟键码。
    /// - Returns: 未授权时 false，不发事件。
    @discardableResult
    static func keyTap(_ keyCode: CGKeyCode) -> Bool {
        guard isTrusted() else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return true
    }

    /// 在给定点发一次左键按下抬起。不先改位置。
    /// - Returns: 未授权时 false。
    @discardableResult
    static func leftClick(at point: CGPoint) -> Bool {
        guard isTrusted() else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return true
    }
}

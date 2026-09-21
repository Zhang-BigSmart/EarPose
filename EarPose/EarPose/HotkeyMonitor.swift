import AppKit
import Foundation

/// 全局快捷键：⌃⌥⌘H 开始/停止，⌃⌥⌘R 校准，⌃⌥⌘P 手动暂停。
final class HotkeyMonitor {
    var onToggleSession: (() -> Void)?
    var onRecenter: (() -> Void)?
    var onToggleManualPause: (() -> Void)?

    private var monitors: [Any] = []

    /// 安装监听。重复调用先移除旧的。
    func start() {
        stop()
        let handler: (NSEvent) -> Void = { [weak self] event in
            self?.handle(event)
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(l)
        }
    }

    /// 移除本地与全局按键监听。不再需要快捷键时调用。
    func stop() {
        for m in monitors {
            NSEvent.removeMonitor(m)
        }
        monitors.removeAll()
    }

    /// 仅响应 ⌃⌥⌘ 且 keyCode 为 H=4、R=15、P=35（ANSI）。其它组合忽略。
    /// - Parameter event: 按键事件。
    private func handle(_ event: NSEvent) {
        let need: NSEvent.ModifierFlags = [.control, .option, .command]
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == need else { return }
        switch event.keyCode {
        case 4: onToggleSession?()
        case 15: onRecenter?()
        case 35: onToggleManualPause?()
        default: break
        }
    }
}

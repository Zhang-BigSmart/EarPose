import AppKit
import Foundation

/// 外设一动，头控让路 1.0 秒。不改手动暂停，不改校准原点。
final class PeripheralYield {
    private let slop: CGFloat = 2
    private let window: TimeInterval = 1.0
    /// 头控刚写入后，这段时间内不把指针偏差当成外设（事件回投 / 系统指针滞后）。
    private let postSettle: TimeInterval = 0.12
    private var lastPosted: CGPoint?
    private var lastPostedAt: TimeInterval = -1
    private var lastExternalAt: TimeInterval?
    private var posting = false
    private var ignoreMonitorUntil: TimeInterval = 0
    private var postGeneration = 0
    private var monitors: [Any] = []

    /// 开始监听全局指针事件。重复调用会先 `stop`。
    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .scrollWheel
        ]
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.handleMonitor()
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(l)
        }
    }

    /// 结束监听。停止追踪时调用。
    func stop() {
        for m in monitors {
            NSEvent.removeMonitor(m)
        }
        monitors.removeAll()
        lastPosted = nil
        lastPostedAt = -1
        lastExternalAt = nil
        posting = false
        ignoreMonitorUntil = 0
        postGeneration += 1
    }

    /// `PointerDriver.move` 即将/刚刚 post 时包一层，避免把自己当成外设。
    /// `CGEvent.post` 返回后事件可能下一拍才进 monitor，故保持 `posting` 到下一个主队列回合。
    func performingPost(_ body: () -> Void) {
        posting = true
        postGeneration += 1
        let gen = postGeneration
        body()
        ignoreMonitorUntil = ProcessInfo.processInfo.systemUptime + postSettle
        DispatchQueue.main.async { [weak self] in
            guard let self, self.postGeneration == gen else { return }
            self.posting = false
        }
    }

    /// 记录头控写下的位置，作为 2px 对比基线。让路期间基线会被改成指针静止点。
    func notePosted(_ point: CGPoint) {
        lastPosted = point
        lastPostedAt = ProcessInfo.processInfo.systemUptime
    }

    /// 判断是否处于外设让路窗口。
    /// - Parameters:
    ///   - now: `ProcessInfo.processInfo.systemUptime`。
    ///   - currentPointer: 当前 Quartz 指针。
    /// - Returns: 距离最近一次外设活动不足 1.0s 则为 `true`。
    /// - 边界: 头控刚写入 0.12s 内忽略 2px 偏差，避免自己的移动被当成外设而一卡一卡。
    ///   超过 2px 且已过静默期才算外设，随后把基线改到当前点；停在新位置不再每帧续命。
    func isYielding(now: TimeInterval, currentPointer: CGPoint) -> Bool {
        if let posted = lastPosted, now - lastPostedAt >= postSettle {
            let d = hypot(currentPointer.x - posted.x, currentPointer.y - posted.y)
            if d > slop {
                lastExternalAt = now
                lastPosted = currentPointer
            }
        }
        if let lastExternalAt, now - lastExternalAt < window {
            return true
        }
        return false
    }

    /// 非本进程意图的指针事件。头控刚 post 的回投直接丢掉。
    private func handleMonitor() {
        if posting { return }
        if ProcessInfo.processInfo.systemUptime < ignoreMonitorUntil { return }
        lastExternalAt = ProcessInfo.processInfo.systemUptime
    }
}

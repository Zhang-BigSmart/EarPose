import Foundation

/// 平滑后的低头角超过「垂直满屏 + 8°」并保持 0.40s 则自动暂停。
/// 不处理手动暂停、不处理外设让路。
struct LookDownPause {
    private var enteredAt: TimeInterval?
    private var exitedAt: TimeInterval?
    private var active = false

    private let holdToEnter: TimeInterval = 0.40
    private let holdToExit: TimeInterval = 0.15

    /// 开始新会话时清空计时。
    mutating func reset() {
        enteredAt = nil
        exitedAt = nil
        active = false
    }

    /// - Parameters:
    ///   - pitchDownRadians: 平滑后、已乘符号，低头为正。
    ///   - thresholdRadians: `ScreenMapper.lookDownThresholdRadians`。
    ///   - now: 单调时钟，`ProcessInfo.processInfo.systemUptime`。
    /// - Returns: 当前是否处于低头自动暂停。
    mutating func update(pitchDownRadians: Double, thresholdRadians: Double, now: TimeInterval) -> Bool {
        if pitchDownRadians >= thresholdRadians {
            exitedAt = nil
            if enteredAt == nil { enteredAt = now }
            if let enteredAt, now - enteredAt >= holdToEnter {
                active = true
            }
        } else {
            enteredAt = nil
            if active {
                if exitedAt == nil { exitedAt = now }
                if let exitedAt, now - exitedAt >= holdToExit {
                    active = false
                    self.exitedAt = nil
                }
            }
        }
        return active
    }
}

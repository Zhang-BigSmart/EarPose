import Foundation

/// 未平滑相对姿态上的点头 → 一次左键意图。不自己发系统点击。
struct NodClickDetector {
    private struct Stamp {
        var time: TimeInterval
        var yaw: Double
        var pitch: Double
    }

    private var history: [Stamp] = []
    private var nodStart: Stamp?
    private var peakDown: Double = 0
    private var maxAbsYawDelta: Double = 0
    private var lastClickAt: TimeInterval = -1

    private let baselineWindow: TimeInterval = 0.150
    private let minDownDegrees = 8.0
    private let returnDegrees = 3.0
    private let minDuration: TimeInterval = 0.120
    private let maxDuration: TimeInterval = 0.450
    private let maxYawDegrees = 10.0
    private let cooldown: TimeInterval = 0.300

    /// 停止或断开时清空，避免跨会话误点。
    mutating func reset() {
        history.removeAll()
        nodStart = nil
        peakDown = 0
        maxAbsYawDelta = 0
        lastClickAt = -1
    }

    /// - Parameters:
    ///   - yaw: 未平滑相对偏航，弧度，未乘屏幕符号。
    ///   - pitchDown: 未平滑相对俯仰，弧度。低头为正（调用方乘 pitchSign）。
    ///   - now: ProcessInfo.processInfo.systemUptime。
    /// - Returns: 本帧是否应发一次左键。
    /// - 边界: 调用方必须在未暂停时才调用；本类型不查询暂停状态。
    mutating func update(yaw: Double, pitchDown: Double, now: TimeInterval) -> Bool {
        history.append(Stamp(time: now, yaw: yaw, pitch: pitchDown))
        history.removeAll { now - $0.time > baselineWindow + maxDuration }

        if now - lastClickAt < cooldown {
            nodStart = nil
            return false
        }

        if nodStart == nil {
            let baseline = baselinePitch(now: now)
            let downDeg = (pitchDown - baseline) * 180.0 / .pi
            if downDeg >= 2 {
                nodStart = Stamp(time: now, yaw: yaw, pitch: baseline)
                peakDown = (pitchDown - baseline) * 180.0 / .pi
                maxAbsYawDelta = 0
            }
            return false
        }

        guard let start = nodStart else { return false }
        let offsetFromStartDeg = (pitchDown - start.pitch) * 180.0 / .pi
        peakDown = max(peakDown, offsetFromStartDeg)
        maxAbsYawDelta = max(maxAbsYawDelta, abs(yaw - start.yaw) * 180.0 / .pi)
        let dt = now - start.time
        let backDeg = abs(offsetFromStartDeg)

        if dt > maxDuration {
            nodStart = nil
            return false
        }

        let returned = backDeg <= returnDegrees
        if returned && dt >= minDuration && peakDown >= minDownDegrees && maxAbsYawDelta <= maxYawDegrees {
            nodStart = nil
            lastClickAt = now
            return true
        }
        return false
    }

    private func baselinePitch(now: TimeInterval) -> Double {
        let window = history.filter { now - $0.time <= baselineWindow && now - $0.time >= 0 }
        if window.isEmpty { return history.last?.pitch ?? 0 }
        return window.map(\.pitch).reduce(0, +) / Double(window.count)
    }
}

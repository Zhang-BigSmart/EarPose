import CoreGraphics
import Foundation

/// 头部朝向 → 方向键的滞回状态机。只产出「本帧该敲哪个方向键」，不自己发系统事件。
/// 交互模型是「甩一下再回正」：出键后上锁，回到中立区才能出下一个键。
/// 这样甩头回正途中的轴间耦合（转头往往带一点抬头）不会被误判成第二个方向。
/// 垂直阈值比水平小：人低头抬头的可用幅度本就不如左右转头。
struct DirectionKeyMapper {
    /// 四个方向及其 macOS 虚拟键码。
    enum Direction {
        case left
        case right
        case up
        case down

        /// macOS 虚拟键码（ANSI 方向键）。
        var keyCode: CGKeyCode {
            switch self {
            case .left: return 123
            case .right: return 124
            case .down: return 125
            case .up: return 126
            }
        }
    }

    private let enterYawDegrees = 8.0
    private let exitYawDegrees = 4.0
    private let enterPitchDegrees = 6.0
    private let exitPitchDegrees = 3.0
    /// 越过阈值即出键，不再多等一帧确认。垂直方向的快甩常常只有一两帧落在区内，
    /// 多等一帧就会整个漏掉，这是「上下没反应」的主因。
    private let confirmFrames = 1
    /// 出键后要连续多少帧停在中立区才解锁。25Hz 下 3 帧约 120ms。
    /// 甩头回正几乎必有过冲，而过冲只是扫过中立区、不会停住，因此不会解锁。
    private let neutralFrames = 3

    private var needsNeutral = false
    private var neutralStreak = 0
    private var candidate: Direction?
    private var candidateFrames = 0

    /// 清空中立锁与各项计数。开始、停止、校准、切换控制方式时调用。
    mutating func reset() {
        needsNeutral = false
        neutralStreak = 0
        candidate = nil
        candidateFrames = 0
    }

    /// 判定本帧是否应敲一次方向键。
    /// - Parameters:
    ///   - yawRadians: 未平滑、已乘符号的水平角，正值对应屏幕右。
    ///   - pitchRadians: 未平滑、已乘符号的垂直角，正值对应屏幕上。
    /// - Returns: 应敲的方向；本帧不该敲则为 `nil`。
    /// - 边界: 每出一次键就上锁，必须两轴一起在中立区「停稳」才解锁，只是快速扫过不算，
    ///   因此回正过冲不会补出一个反方向键；两轴同时越界只取超出阈值比例更大的一轴，不产出对角。
    mutating func update(yawRadians: Double, pitchRadians: Double) -> Direction? {
        let yawDeg = yawRadians * 180.0 / .pi
        let pitchDeg = pitchRadians * 180.0 / .pi

        if abs(yawDeg) < exitYawDegrees, abs(pitchDeg) < exitPitchDegrees {
            neutralStreak += 1
            if neutralStreak >= neutralFrames {
                needsNeutral = false
            }
            candidate = nil
            candidateFrames = 0
            return nil
        }
        neutralStreak = 0

        guard !needsNeutral,
              let zone = dominantDirection(yawDeg: yawDeg, pitchDeg: pitchDeg) else {
            candidate = nil
            candidateFrames = 0
            return nil
        }
        if candidate == zone {
            candidateFrames += 1
        } else {
            candidate = zone
            candidateFrames = 1
        }
        guard candidateFrames >= confirmFrames else { return nil }
        needsNeutral = true
        neutralStreak = 0
        candidate = nil
        candidateFrames = 0
        return zone
    }

    /// 取「超出各自阈值的比例」更大的一轴，保证同一时刻只有一个方向。
    /// 两轴阈值不同，必须先各自归一化再比，否则水平轴会一直压过垂直轴。
    /// - Returns: 两轴都没达到各自进入阈值时为 `nil`。
    private func dominantDirection(yawDeg: Double, pitchDeg: Double) -> Direction? {
        let yawRatio = abs(yawDeg) / enterYawDegrees
        let pitchRatio = abs(pitchDeg) / enterPitchDegrees
        if yawRatio < 1, pitchRatio < 1 { return nil }
        if yawRatio >= pitchRatio {
            return yawDeg > 0 ? .right : .left
        }
        return pitchDeg > 0 ? .up : .down
    }
}

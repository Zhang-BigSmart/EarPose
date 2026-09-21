import AppKit
import CoreGraphics
import Foundation

/// 把相对 yaw/pitch 映射到系统主屏（菜单栏所在屏）的 Quartz 坐标。
/// 平滑与死区只在这里做。点头检测不要用这里的平滑值。
struct ScreenMapper {
    static let deadzoneDegrees = 2.0
    static let minYawDegrees = 12.0
    static let maxYawDegreesLimit = 40.0
    static let defaultYawDegrees = 22.0
    static let pitchOverYaw = 14.0 / 22.0
    /// 指数滑动平均的新值权重。越大越跟手，越小越稳。
    static let smoothNewWeight = 0.55

    /// 水平满屏角，度，范围 12...40，默认 22。
    var maxYawDegrees: Double = ScreenMapper.defaultYawDegrees {
        didSet {
            maxYawDegrees = min(
                Self.maxYawDegreesLimit,
                max(Self.minYawDegrees, maxYawDegrees)
            )
        }
    }

    /// 左右符号。向右转头指针应向右。本机实测 IMU 偏航与屏幕左右相反，故为 `-1`。
    var yawSign: Double = -1
    /// 上下符号。抬头指针应向上（Quartz Y 变小）；实测相反则改为 `-1`。
    var pitchSign: Double = 1

    private var smoothedYaw: Double?
    private var smoothedPitch: Double?

    /// 垂直满屏角，度。随水平灵敏度按 14/22 比例变化。
    var maxPitchDegrees: Double { maxYawDegrees * Self.pitchOverYaw }

    /// 低头自动暂停阈值（垂直满屏角 + 8°），弧度。
    var lookDownThresholdRadians: Double {
        (maxPitchDegrees + 8.0) * .pi / 180.0
    }

    /// 丢弃平滑历史。开始、停止、重新校准时调用。
    mutating func resetSmoothing() {
        smoothedYaw = nil
        smoothedPitch = nil
    }

    /// 映射一帧。
    /// - Parameters:
    ///   - rawYaw: 未平滑相对偏航，弧度。
    ///   - rawPitch: 未平滑相对俯仰，弧度。
    /// - Returns: Quartz 点（左上原点、Y 向下）、平滑后的 yaw/pitch（弧度，已乘符号，低头为正 pitch）。
    /// - 边界: 超出满屏角夹在主屏边缘，不进入其它显示器。
    mutating func map(rawYaw: Double, rawPitch: Double) -> (point: CGPoint, smoothYaw: Double, smoothPitch: Double) {
        let y0 = smoothedYaw ?? rawYaw
        let p0 = smoothedPitch ?? rawPitch
        let sy = Self.smoothNewWeight * rawYaw + (1 - Self.smoothNewWeight) * y0
        let sp = Self.smoothNewWeight * rawPitch + (1 - Self.smoothNewWeight) * p0
        smoothedYaw = sy
        smoothedPitch = sp

        let signedYaw = sy * yawSign
        let signedPitch = sp * pitchSign
        let tX = axisT(radians: signedYaw, maxDegrees: maxYawDegrees)
        let tY = axisT(radians: signedPitch, maxDegrees: maxPitchDegrees)
        return (point: quartzPoint(tX: tX, tY: tY), smoothYaw: signedYaw, smoothPitch: signedPitch)
    }

    /// 单轴：死区 2° 外线性映射到 [-1, 1]。
    private func axisT(radians: Double, maxDegrees: Double) -> Double {
        let deg = radians * 180.0 / .pi
        let absDeg = abs(deg)
        if absDeg <= Self.deadzoneDegrees { return 0 }
        let span = max(maxDegrees - Self.deadzoneDegrees, 0.0001)
        let t = (absDeg - Self.deadzoneDegrees) / span
        return max(-1, min(1, (deg >= 0 ? 1 : -1) * t))
    }

    /// tX=-1 左缘，tX=1 右缘；tY=1 上缘（抬头），tY=-1 下缘。
    private func quartzPoint(tX: Double, tY: Double) -> CGPoint {
        let screen = Self.menuBarScreen()
        let frame = screen.frame
        let cocoaX = frame.minX + (tX + 1) * 0.5 * frame.width
        let cocoaY = frame.minY + (tY + 1) * 0.5 * frame.height
        let quartzY = Self.cocoaYToQuartz(cocoaY)
        return CGPoint(x: cocoaX, y: quartzY)
    }

    /// 菜单栏所在屏；找不到则退回 `NSScreen.main` 或第一块屏。
    static func menuBarScreen() -> NSScreen {
        if let s = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return s
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// AppKit 全局 Y（上为正方向、原点在主屏左下）转到 Quartz Y（主屏左上、向下为正）。
    static func cocoaYToQuartz(_ cocoaY: Double) -> Double {
        let main = menuBarScreen()
        return main.frame.maxY - cocoaY
    }

    /// 当前指针的 Quartz 坐标，与 `CGEvent` 写入同一坐标系，避免换算误差触发误让路。
    static func currentQuartzPointer() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}

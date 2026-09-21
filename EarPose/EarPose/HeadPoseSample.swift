import CoreMotion
import Foundation

/// 一帧相对校准原点的耳机姿态。校准完成前不得构造并送给映射层。
struct HeadPoseSample: Equatable {
    /// 运动数据时间戳，秒。
    var timestamp: TimeInterval
    /// 相对左右，弧度。
    var yaw: Double
    /// 相对上下，弧度。
    var pitch: Double
    /// 相对滚转，弧度。
    var roll: Double
    /// 绕设备 X 轴角速度，弧度/秒。
    var rotationRateX: Double
    /// 绕设备 Y 轴角速度，弧度/秒。
    var rotationRateY: Double
    /// 绕设备 Z 轴角速度，弧度/秒。
    var rotationRateZ: Double
    /// 本帧姿态数据来源的传感器位置（如左/右耳）。
    var sensorLocation: CMDeviceMotion.SensorLocation
    /// 本帧是否仍视为已连接。
    var connected: Bool
}

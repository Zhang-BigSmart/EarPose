import CoreMotion
import Foundation

/// 耳机运动回调。`didUpdate` 在私有 motion 队列触发；连/断跟随 Core Motion 连接状态调度（常为 main）。UI 须自行切回主线程。
protocol HeadMotionSourceDelegate: AnyObject {
    /// 耳机连上或戴回。
    func headMotionSourceDidConnect(_ source: HeadMotionSource)
    /// 耳机断开或摘下。调用后不应再收到 `didUpdate`。
    func headMotionSourceDidDisconnect(_ source: HeadMotionSource)
    /// 已校准后的相对姿态。未校准不回调。
    func headMotionSource(_ source: HeadMotionSource, didUpdate sample: HeadPoseSample)
}

/// 读 `CMHeadphoneMotionManager`，负责连接与相对原点。不映射屏幕、不发鼠标事件。
final class HeadMotionSource: NSObject, CMHeadphoneMotionManagerDelegate {
    weak var delegate: HeadMotionSourceDelegate?

    private let manager = CMHeadphoneMotionManager()
    private let queue = OperationQueue()
    private var origin: CMAttitude?
    private var running = false

    override init() {
        super.init()
        queue.name = "local.edison.earpose.motion"
        queue.maxConcurrentOperationCount = 1
        manager.delegate = self
    }

    /// 当前系统是否认为「这副已连接的耳机」能出头部运动数据。
    /// - Returns: 未连兼容耳机时为 `false`（含部分 Intel Mac 上 API 不可用）。
    var isDeviceMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    /// 运动与健身授权。未定局时，首次 `start` 会弹出系统对话框。
    var authorizationStatus: CMAuthorizationStatus {
        CMHeadphoneMotionManager.authorizationStatus()
    }

    /// 开始推流。若 `calibrateNow` 为真，下一帧姿态锁为原点。
    /// - Parameters:
    ///   - calibrateNow: 开始会话时必须为 true；仅重连内部不要用。
    /// - 边界: `authorizationStatus == .denied` 或 `isDeviceMotionAvailable == false` 时不调用 `startDeviceMotionUpdates`。
    func start(calibrateNow: Bool) {
        if authorizationStatus == .denied { return }
        if !manager.isDeviceMotionAvailable { return }
        if calibrateNow { origin = nil }
        running = true
        manager.startConnectionStatusUpdates()
        guard !manager.isDeviceMotionActive else { return }
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            self?.handle(motion)
        }
    }

    /// 停止推流并丢弃原点。之后不再回调 `didUpdate`。
    func stop() {
        running = false
        origin = nil
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        manager.stopConnectionStatusUpdates()
    }

    /// 把当前姿态重新锁为原点。未 `start` 时无效果。
    func recenter() {
        origin = nil
    }

    /// - Parameter manager: 系统传入的管理器。
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        delegate?.headMotionSourceDidConnect(self)
    }

    /// 摘下或蓝牙断开。停止姿态推流、清空原点，通知上层进入「断开」；不断开连接状态监听。
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        running = false
        origin = nil
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        delegate?.headMotionSourceDidDisconnect(self)
    }

    /// 将当前 `CMDeviceMotion` 转成相对样本。无原点时先锁原点，本帧不外送。
    private func handle(_ motion: CMDeviceMotion?) {
        guard running, let motion else { return }
        if origin == nil {
            origin = motion.attitude.copy() as? CMAttitude
            return
        }
        guard let origin, let relative = motion.attitude.copy() as? CMAttitude else { return }
        relative.multiply(byInverseOf: origin)
        let sample = HeadPoseSample(
            timestamp: motion.timestamp,
            yaw: relative.yaw,
            pitch: relative.pitch,
            roll: relative.roll,
            rotationRateX: motion.rotationRate.x,
            rotationRateY: motion.rotationRate.y,
            rotationRateZ: motion.rotationRate.z,
            sensorLocation: motion.sensorLocation,
            connected: true
        )
        delegate?.headMotionSource(self, didUpdate: sample)
    }
}

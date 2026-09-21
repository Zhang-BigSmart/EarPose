import Combine
import CoreMotion
import Foundation
import SwiftUI

/// 菜单栏可见的四态，不可合并。
enum SessionPhase: Equatable {
    case off
    case tracking
    case paused
    case disconnected
}

/// 头控的两种输出方式，同一时刻只有一种生效。
enum ControlMode: String, CaseIterable, Identifiable {
    /// 激光笔：头指哪指针到哪，点头单击，低头与外设会暂停。
    case pointer
    /// 方向键：头越过阈值敲一次方向键，指针不动，不做点头与低头暂停。
    case directionKeys

    var id: String { rawValue }

    /// 菜单显示名，跟随系统语言。
    var title: String {
        switch self {
        case .pointer: return L10n.s("mode.pointer")
        case .directionKeys: return L10n.s("mode.arrows")
        }
    }
}

/// 会话状态机：校准、三种暂停、映射、点击。不直接持有 `CMHeadphoneMotionManager`。
@MainActor
final class AppState: ObservableObject {
    @Published var phase: SessionPhase = .off
    @Published var yawDegrees: Double?
    @Published var pitchDegrees: Double?
    @Published var manualPause = false
    @Published var lookDownPauseActive = false
    @Published var peripheralYieldActive = false
    @Published var motionStatusText = L10n.s("motion.unknown")
    @Published var accessibilityTrusted = false
    @Published var startHint = ""

    /// 控制方式。切换时清空两套判定，避免残留锁定或暂停标志。
    @Published var controlMode: ControlMode = .pointer {
        didSet {
            guard oldValue != controlMode else { return }
            direction.reset()
            nod.reset()
            lookDown.reset()
            lookDownPauseActive = false
            peripheralYieldActive = false
            applyPausePhase()
        }
    }

    /// 水平满屏角，写入 UserDefaults。范围 12...40，默认 22。
    @Published var maxYawDegrees: Double = ScreenMapper.defaultYawDegrees {
        didSet {
            mapper.maxYawDegrees = maxYawDegrees
            UserDefaults.standard.set(maxYawDegrees, forKey: Self.yawKey)
        }
    }

    private static let yawKey = "maxYawDegrees"

    private let motion = HeadMotionSource()
    private lazy var bridge: MotionBridge = MotionBridge(owner: self)
    private var mapper = ScreenMapper()
    private var lookDown = LookDownPause()
    private var nod = NodClickDetector()
    private var direction = DirectionKeyMapper()
    private let yield = PeripheralYield()
    private let hotkeys = HotkeyMonitor()

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.yawKey) as? Double
        maxYawDegrees = stored ?? ScreenMapper.defaultYawDegrees
        mapper.maxYawDegrees = maxYawDegrees
        motion.delegate = bridge
        hotkeys.onToggleSession = { [weak self] in self?.toggleSession() }
        hotkeys.onRecenter = { [weak self] in self?.recenter() }
        hotkeys.onToggleManualPause = { [weak self] in self?.toggleManualPause() }
        hotkeys.start()
        refreshPermissions()
    }

    /// 菜单栏模板图资源名。四态不可合并。
    var menuBarImageName: String {
        switch phase {
        case .off: return "MenuBarOff"
        case .tracking: return "MenuBarTracking"
        case .paused: return "MenuBarPaused"
        case .disconnected: return "MenuBarDisconnected"
        }
    }

    /// 暂停原因文案，优先：手动 ＞ 低头 ＞ 外设。跟随系统语言。
    var statusText: String {
        switch phase {
        case .off:
            return L10n.s("status.off")
        case .disconnected:
            return L10n.s("status.disconnected")
        case .tracking:
            if !accessibilityTrusted {
                return L10n.f("status.tracking.no_ax", controlMode.title)
            }
            return L10n.f("status.tracking", controlMode.title)
        case .paused:
            if manualPause { return L10n.s("status.pause.manual") }
            if lookDownPauseActive { return L10n.s("status.pause.lookdown") }
            if peripheralYieldActive { return L10n.s("status.pause.yield") }
            return L10n.s("status.paused")
        }
    }

    /// 会话是否处于开着（追踪、暂停或断开）。关为 false。
    var isRunning: Bool {
        phase == .tracking || phase == .paused || phase == .disconnected
    }

    /// 刷新运动授权文案与辅助功能勾选状态。不弹系统提示。
    func refreshPermissions() {
        accessibilityTrusted = PointerDriver.isTrusted()
        switch motion.authorizationStatus {
        case .authorized: motionStatusText = L10n.s("motion.authorized")
        case .denied: motionStatusText = L10n.s("motion.denied")
        case .restricted: motionStatusText = L10n.s("motion.restricted")
        case .notDetermined: motionStatusText = L10n.s("motion.ask")
        @unknown default: motionStatusText = L10n.s("motion.unknown")
        }
    }

    /// 关/断开 → 尝试开始；追踪/暂停 → 停止到关。
    func toggleSession() {
        if phase == .off || phase == .disconnected {
            start()
        } else {
            stop()
        }
    }

    /// 开始追踪。运动拒绝则留在关；耳机不可用则断开。
    func start() {
        refreshPermissions()
        startHint = ""
        if motion.authorizationStatus == .denied {
            startHint = L10n.s("hint.motion")
            phase = .off
            return
        }
        if !motion.isDeviceMotionAvailable {
            startHint = L10n.s("hint.headphones")
            phase = .disconnected
            return
        }
        mapper.resetSmoothing()
        lookDown.reset()
        nod.reset()
        direction.reset()
        yield.start()
        motion.start(calibrateNow: true)
        manualPause = false
        lookDownPauseActive = false
        peripheralYieldActive = false
        phase = .tracking
        if !accessibilityTrusted {
            PointerDriver.promptIfNeeded()
            startHint = controlMode == .directionKeys
                ? L10n.s("hint.ax.arrows")
                : L10n.s("hint.ax.pointer")
        }
    }

    /// 停止。指针留在原地。
    func stop() {
        motion.stop()
        yield.stop()
        mapper.resetSmoothing()
        lookDown.reset()
        nod.reset()
        direction.reset()
        phase = .off
        yawDegrees = nil
        pitchDegrees = nil
        manualPause = false
        lookDownPauseActive = false
        peripheralYieldActive = false
        startHint = ""
    }

    /// 仅追踪或暂停有效。暂停中只更新原点，不移动指针。
    func recenter() {
        guard phase == .tracking || phase == .paused else { return }
        motion.recenter()
        mapper.resetSmoothing()
        nod.reset()
        lookDown.reset()
        direction.reset()
        if phase == .tracking, accessibilityTrusted, controlMode == .pointer {
            let screen = ScreenMapper.menuBarScreen().frame
            let center = CGPoint(
                x: screen.midX,
                y: ScreenMapper.cocoaYToQuartz(screen.midY)
            )
            yield.performingPost {
                _ = PointerDriver.move(to: center)
            }
            yield.notePosted(center)
        }
    }

    /// 在追踪或暂停时切换手动暂停。其它相位忽略。
    func toggleManualPause() {
        guard phase == .tracking || phase == .paused else { return }
        manualPause.toggle()
        applyPausePhase()
    }

    /// 耳机连上。规格：重新戴上不自动恢复。保持断开，等用户点开始。
    fileprivate func handleConnect() {
        // 规格：重新戴上不自动恢复。保持断开，等用户点开始。
    }

    /// 摘下或蓝牙断开：停推流、进断开态。关着时忽略。
    fileprivate func handleDisconnect() {
        guard phase != .off else { return }
        motion.stop()
        yield.stop()
        nod.reset()
        lookDown.reset()
        direction.reset()
        phase = .disconnected
        yawDegrees = nil
        pitchDegrees = nil
    }

    /// 一帧相对姿态：更新角、映射，再按控制方式分流。
    /// - Parameter sample: 已相对原点的姿态；关或断开时忽略。
    /// - 边界: 方向键模式下只保留手动暂停，不跑低头暂停、外设让路与点头，指针不动。
    fileprivate func handleSample(_ sample: HeadPoseSample) {
        guard phase != .off else { return }
        if phase == .disconnected { return }

        yawDegrees = sample.yaw * 180.0 / .pi
        pitchDegrees = sample.pitch * 180.0 / .pi

        let mapped = mapper.map(rawYaw: sample.yaw, rawPitch: sample.pitch)
        let now = ProcessInfo.processInfo.systemUptime

        if controlMode == .directionKeys {
            handleDirectionKeys(sample: sample)
            return
        }

        lookDownPauseActive = lookDown.update(
            pitchDownRadians: mapped.smoothPitch,
            thresholdRadians: mapper.lookDownThresholdRadians,
            now: now
        )
        let pointer = ScreenMapper.currentQuartzPointer()
        peripheralYieldActive = yield.isYielding(now: now, currentPointer: pointer)
        applyPausePhase()

        let blocked = manualPause || lookDownPauseActive || peripheralYieldActive
        guard !blocked, accessibilityTrusted else { return }

        let pitchDownRaw = sample.pitch * mapper.pitchSign
        yield.performingPost {
            _ = PointerDriver.move(to: mapped.point)
        }
        yield.notePosted(mapped.point)
        if nod.update(yaw: sample.yaw, pitchDown: pitchDownRaw, now: now) {
            yield.performingPost {
                _ = PointerDriver.leftClick(at: mapped.point)
            }
        }
    }

    /// 方向键模式下的一帧：只受手动暂停约束，越过阈值敲一次方向键。
    /// 用未平滑角度，绕开 `ScreenMapper` 的指数平均，省掉游戏里最难受的那段延迟。
    /// - Parameter sample: 未平滑的相对姿态；符号沿用指针模式，保证两种模式的上下左右一致。
    private func handleDirectionKeys(sample: HeadPoseSample) {
        lookDownPauseActive = false
        peripheralYieldActive = false
        applyPausePhase()
        guard !manualPause, accessibilityTrusted else { return }
        if let key = direction.update(
            yawRadians: sample.yaw * mapper.yawSign,
            pitchRadians: sample.pitch * mapper.pitchSign
        ) {
            _ = PointerDriver.keyTap(key.keyCode)
        }
    }

    /// 按三种暂停标志在追踪/暂停之间切换。关与断开不动。
    private func applyPausePhase() {
        if phase == .off || phase == .disconnected { return }
        let blocked = manualPause || lookDownPauseActive || peripheralYieldActive
        phase = blocked ? .paused : .tracking
    }
}

/// CoreMotion 回调不在主线程。桥接到 `AppState`。
private final class MotionBridge: HeadMotionSourceDelegate {
    weak var owner: AppState?

    init(owner: AppState) {
        self.owner = owner
    }

    func headMotionSourceDidConnect(_ source: HeadMotionSource) {
        DispatchQueue.main.async { self.owner?.handleConnect() }
    }

    func headMotionSourceDidDisconnect(_ source: HeadMotionSource) {
        DispatchQueue.main.async { self.owner?.handleDisconnect() }
    }

    func headMotionSource(_ source: HeadMotionSource, didUpdate sample: HeadPoseSample) {
        DispatchQueue.main.async { self.owner?.handleSample(sample) }
    }
}

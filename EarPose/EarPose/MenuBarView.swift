import AppKit
import SwiftUI

/// 菜单栏弹出内容。文案跟随系统语言。快捷键只展示，不在此重复实现。
struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EarPose")
                .font(.headline)
            Text(L10n.s("tagline"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(state.statusText)
            if !state.startHint.isEmpty {
                Text(state.startHint).foregroundStyle(.secondary)
            }
            Text(angleText)
            Divider()
            if state.phase == .off || state.phase == .disconnected {
                Button(L10n.s("start")) { state.start() }
            } else {
                Button(L10n.s("stop")) { state.stop() }
            }
            Button(L10n.s("recenter")) { state.recenter() }
                .disabled(state.phase != .tracking && state.phase != .paused)
            Button(state.manualPause ? L10n.s("resume") : L10n.s("pause")) {
                state.toggleManualPause()
            }
            .disabled(state.phase != .tracking && state.phase != .paused)
            Divider()
            Picker(L10n.s("control.mode"), selection: $state.controlMode) {
                ForEach(ControlMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            Divider()
            Text(L10n.f("sensitivity", Int(state.maxYawDegrees.rounded())))
            Slider(value: $state.maxYawDegrees, in: ScreenMapper.minYawDegrees...ScreenMapper.maxYawDegreesLimit)
            Text(L10n.s("sensitivity.hint")).font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(state.motionStatusText)
            Text(state.accessibilityTrusted ? L10n.s("ax.on") : L10n.s("ax.off"))
            Button(L10n.s("open.motion")) { PointerDriver.openMotionSettings() }
            Button(L10n.s("open.ax")) { PointerDriver.openAccessibilitySettings() }
            Divider()
            Text(L10n.f("shortcut.start", "⌃⌥⌘H")).font(.caption)
            Text(L10n.f("shortcut.recenter", "⌃⌥⌘R")).font(.caption)
            Text(L10n.f("shortcut.pause", "⌃⌥⌘P")).font(.caption)
            Divider()
            Button(L10n.s("quit")) { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
        .frame(minWidth: 280)
        .onAppear { state.refreshPermissions() }
    }

    /// 相对原点的左右/上下角；关或断开无数据时显示破折号。
    private var angleText: String {
        if let yaw = state.yawDegrees, let pitch = state.pitchDegrees {
            return L10n.f("angles.value", yaw, pitch)
        }
        return L10n.s("angles.empty")
    }
}

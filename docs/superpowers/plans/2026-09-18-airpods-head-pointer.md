# 头部指针 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做一个 macOS 14+ 菜单栏 App：兼容耳机的相对姿态映射到主屏指针（激光笔），点头左键，低头/手动/外设三种暂停。

**Architecture:** 单 target SwiftUI 菜单栏 App。`HeadMotionSource` 只出相对姿态；`ScreenMapper` / `LookDownPause` / `NodClickDetector` / `PeripheralYield` / `PointerDriver` 各管一件事；`AppState` 是唯一状态机。不写第二种映射，不为游戏加开关。

**Tech Stack:** Swift 5.9+ / SwiftUI `MenuBarExtra` / CoreMotion `CMHeadphoneMotionManager` / CoreGraphics `CGEvent` / ApplicationServices 辅助功能。部署 macOS 14.0，Universal。无第三方包。

**规格：** `docs/superpowers/specs/2026-09-18-airpods-head-pointer-design.md`

**本计划与用户规则的对齐：** 第一版不写自动化测试文件，验证用 `xcodebuild` + spec §9 手动清单。未经用户要求不 `git commit`。实现前本机需已安装 **Xcode 26.3 Universal**（或同代仍支持 Sequoia 15.6 的 Universal）。

---

## 文件结构

全部新建，根目录下的 `HeadPointer/` 是 Xcode 工程（不要改笔记 md）。

| 路径 | 职责 |
| --- | --- |
| `HeadPointer/HeadPointer.xcodeproj/project.pbxproj` | 工程；文件系统同步组，之后加 Swift 不必改 pbxproj |
| `HeadPointer/HeadPointer/Info.plist` | `NSMotionUsageDescription`、`LSUIElement`、bundle id |
| `HeadPointer/HeadPointer/HeadPointer.entitlements` | 不沙盒，否则 `CGEvent` 发不出去 |
| `HeadPointer/HeadPointer/HeadPoseSample.swift` | 一帧相对姿态 |
| `HeadPointer/HeadPointer/HeadMotionSource.swift` | 读耳机、校准原点、连接回调 |
| `HeadPointer/HeadPointer/ScreenMapper.swift` | 平滑 + 死区 + 灵敏度 → 主屏 Quartz 坐标 |
| `HeadPointer/HeadPointer/LookDownPause.swift` | 平滑后低头角保持 0.4s |
| `HeadPointer/HeadPointer/NodClickDetector.swift` | 未平滑点头 → 单击意图 |
| `HeadPointer/HeadPointer/PointerDriver.swift` | 唯一 `CGEvent` 出口 |
| `HeadPointer/HeadPointer/PeripheralYield.swift` | 外设活动让路 1.0s |
| `HeadPointer/HeadPointer/HotkeyMonitor.swift` | ⌃⌥⌘H / R / P |
| `HeadPointer/HeadPointer/AppState.swift` | 会话状态机，接线 |
| `HeadPointer/HeadPointer/MenuBarView.swift` | 中文菜单 |
| `HeadPointer/HeadPointer/HeadPointerApp.swift` | `@main` 入口 |

---

### Task 1: 确认 Xcode 并搭工程壳

**Files:**
- Create: `HeadPointer/HeadPointer/Info.plist`
- Create: `HeadPointer/HeadPointer/HeadPointer.entitlements`
- Create: `HeadPointer/HeadPointer.xcodeproj/project.pbxproj`
- Create: `HeadPointer/HeadPointer/HeadPointerApp.swift`

- [ ] **Step 1: 确认编译器是完整 Xcode，不是 Command Line Tools**

Run:

```bash
xcode-select -p
xcodebuild -version
```

Expected: 路径为 `/Applications/Xcode.app/Contents/Developer`（或你安装 Xcode.app 的位置）。`xcodebuild -version` 能印出 `Xcode 16` 或 `Xcode 26` 字样。若仍是 `/Library/Developer/CommandLineTools`，先装 Xcode 26.3 Universal，再执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

本步失败则后面所有 `xcodebuild` 都不要跑。

- [ ] **Step 2: 写 Info.plist**

创建 `HeadPointer/HeadPointer/Info.plist`，全文：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh-Hans</string>
	<key>CFBundleDisplayName</key>
	<string>头部指针</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>头部指针</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSMotionUsageDescription</key>
	<string>读取 AirPods 头部姿态，用来移动鼠标指针。</string>
</dict>
</plist>
```

缺 `NSMotionUsageDescription` 会在 `startDeviceMotionUpdates` 时被系统杀掉，视为缺陷。

- [ ] **Step 3: 写 entitlements（关闭沙盒）**

创建 `HeadPointer/HeadPointer/HeadPointer.entitlements`，全文：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
</dict>
</plist>
```

- [ ] **Step 4: 写最小 SwiftUI 入口（先能编过）**

创建 `HeadPointer/HeadPointer/HeadPointerApp.swift`，全文：

```swift
import SwiftUI

/// 菜单栏入口。无 Dock 图标（Info.plist `LSUIElement`）。
@main
struct HeadPointerApp: App {
    var body: some Scene {
        MenuBarExtra("头部指针", systemImage: "dot.scope") {
            Text("工程壳")
        }
    }
}
```

- [ ] **Step 5: 写 pbxproj（Xcode 16+ 同步根目录，之后加 .swift 不用改工程文件）**

创建 `HeadPointer/HeadPointer.xcodeproj/project.pbxproj`，全文：

```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXFileSystemSynchronizedRootGroup section */
		AA0000000000000000000001 /* HeadPointer */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = HeadPointer;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFileReference section */
		AA0000000000000000000002 /* HeadPointer.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = HeadPointer.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		AA0000000000000000000003 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		AA0000000000000000000004 = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000001 /* HeadPointer */,
				AA0000000000000000000005 /* Products */,
			);
			sourceTree = "<group>";
		};
		AA0000000000000000000005 /* Products */ = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000002 /* HeadPointer.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		AA0000000000000000000006 /* HeadPointer */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000007 /* Build configuration list for PBXNativeTarget "HeadPointer" */;
			buildPhases = (
				AA0000000000000000000008 /* Sources */,
				AA0000000000000000000003 /* Frameworks */,
				AA0000000000000000000009 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				AA0000000000000000000001 /* HeadPointer */,
			);
			name = HeadPointer;
			productName = HeadPointer;
			productReference = AA0000000000000000000002 /* HeadPointer.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		AA000000000000000000000A /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			};
			buildConfigurationList = AA000000000000000000000B /* Build configuration list for PBXProject "HeadPointer" */;
			developmentRegion = "zh-Hans";
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				"zh-Hans",
			);
			mainGroup = AA0000000000000000000004;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = AA0000000000000000000005 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				AA0000000000000000000006 /* HeadPointer */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		AA0000000000000000000009 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		AA0000000000000000000008 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		AA000000000000000000000C /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		AA000000000000000000000D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
			};
			name = Release;
		};
		AA000000000000000000000E /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ARCHS = "$(ARCHS_STANDARD)";
				CODE_SIGN_ENTITLEMENTS = HeadPointer/HeadPointer.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = HeadPointer/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = local.edison.headpointer;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		AA000000000000000000000F /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ARCHS = "$(ARCHS_STANDARD)";
				CODE_SIGN_ENTITLEMENTS = HeadPointer/HeadPointer.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = HeadPointer/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 1.0;
				ONLY_ACTIVE_ARCH = NO;
				PRODUCT_BUNDLE_IDENTIFIER = local.edison.headpointer;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		AA000000000000000000000B /* Build configuration list for PBXProject "HeadPointer" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA000000000000000000000C /* Debug */,
				AA000000000000000000000D /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		AA0000000000000000000007 /* Build configuration list for PBXNativeTarget "HeadPointer" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA000000000000000000000E /* Debug */,
				AA000000000000000000000F /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = AA000000000000000000000A /* Project object */;
}
```

- [ ] **Step 6: 编译工程壳**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。失败则先修 pbxproj / 路径，不要进入 Task 2。

---

### Task 2: HeadPoseSample + HeadMotionSource

**Files:**
- Create: `HeadPointer/HeadPointer/HeadPoseSample.swift`
- Create: `HeadPointer/HeadPointer/HeadMotionSource.swift`

- [ ] **Step 1: 写 HeadPoseSample.swift**

```swift
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
    var rotationRateX: Double
    var rotationRateY: Double
    var rotationRateZ: Double
    var sensorLocation: CMDeviceMotion.SensorLocation
    /// 本帧是否仍视为已连接。
    var connected: Bool
}
```

- [ ] **Step 2: 写 HeadMotionSource.swift**

```swift
import CoreMotion
import Foundation

/// 耳机运动回调。全部在 `HeadMotionSource` 的队列触发，UI 层自行切回主线程。
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
        queue.name = "local.edison.headpointer.motion"
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

    /// 摘下或蓝牙断开。清空原点缓冲，通知上层进入「断开」。
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        origin = nil
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
```

- [ ] **Step 3: 编译确认两个新文件进同步组**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。

---

### Task 3: ScreenMapper

**Files:**
- Create: `HeadPointer/HeadPointer/ScreenMapper.swift`

- [ ] **Step 1: 写 ScreenMapper.swift**

```swift
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
    static let smoothNewWeight = 0.35

    /// 水平满屏角，度，范围 12...40，默认 22。
    var maxYawDegrees: Double = ScreenMapper.defaultYawDegrees {
        didSet {
            maxYawDegrees = min(
                Self.maxYawDegreesLimit,
                max(Self.minYawDegrees, maxYawDegrees)
            )
        }
    }

    /// 左右符号。向右转头指针应向右；实测相反则改为 `-1`。
    var yawSign: Double = 1
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

    /// 当前指针的 Quartz 坐标。
    static func currentQuartzPointer() -> CGPoint {
        let cocoa = NSEvent.mouseLocation
        return CGPoint(x: cocoa.x, y: cocoaYToQuartz(cocoa.y))
    }
}
```

- [ ] **Step 2: 编译**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。

---

### Task 4: LookDownPause

**Files:**
- Create: `HeadPointer/HeadPointer/LookDownPause.swift`

- [ ] **Step 1: 写 LookDownPause.swift**

```swift
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
```

- [ ] **Step 2: 编译**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。

---

### Task 5: NodClickDetector

**Files:**
- Create: `HeadPointer/HeadPointer/NodClickDetector.swift`

- [ ] **Step 1: 写 NodClickDetector.swift**

规格：未平滑 pitch；相对点头开始前 150ms 基线向下 ≥ 8°；总时长 120...450ms 回到基线 ±3°；过程 yaw 偏移 ≤ 10°；成功后冷却 300ms。

```swift
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
    ///   - pitch: 未平滑相对俯仰，弧度。低头方向与 `pitchSign` 一致时传入 `pitch * pitchSign`（低头为正）。
    ///   - now: `ProcessInfo.processInfo.systemUptime`。
    /// - Returns: 本帧是否应发一次左键。
    /// - 边界: 调用方必须在未暂停时才调用；本类型不查询暂停状态。
    mutating func update(yaw: Double, pitchDown: Double, now: TimeInterval) -> Bool {
        history.append(Stamp(time: now, yaw: yaw, pitch: pitchDown))
        history.removeAll { now - $0.time > baselineWindow + maxDuration }

        if now - lastClickAt < cooldown {
            nodStart = nil
            return false
        }

        let baseline = baselinePitch(now: now)
        let downDeg = (pitchDown - baseline) * 180.0 / .pi

        if nodStart == nil {
            if downDeg >= 2 {
                nodStart = Stamp(time: now, yaw: yaw, pitch: baseline)
                peakDown = downDeg
                maxAbsYawDelta = 0
            }
            return false
        }

        guard let start = nodStart else { return false }
        peakDown = max(peakDown, downDeg)
        maxAbsYawDelta = max(maxAbsYawDelta, abs(yaw - start.yaw) * 180.0 / .pi)
        let dt = now - start.time
        let backDeg = abs((pitchDown - start.pitch) * 180.0 / .pi)

        if dt > maxDuration {
            nodStart = nil
            return false
        }

        let returned = backDeg <= returnDegrees && pitchDown <= start.pitch + 1 * .pi / 180.0
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
```

- [ ] **Step 2: 编译**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。

---

### Task 6: PointerDriver

**Files:**
- Create: `HeadPointer/HeadPointer/PointerDriver.swift`

- [ ] **Step 1: 写 PointerDriver.swift**

```swift
import ApplicationServices
import CoreGraphics
import Foundation

/// 唯一调用 `CGEvent` 的出口。未获辅助功能时全部空操作并返回 false。
enum PointerDriver {
    /// 是否已在「辅助功能」中勾选本 App。
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统辅助功能提示（若尚未授权）。
    /// - Returns: 调用后立刻查询的结果；用户可能还没勾选。
    @discardableResult
    static func promptIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// 打开系统设置里的辅助功能页。打不开则静默失败。
    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    /// 打开运动与健身相关设置（macOS 隐私页）。
    static func openMotionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 把指针移到 Quartz 坐标。
    /// - Returns: 未授权时 false，不发事件。
    @discardableResult
    static func move(to point: CGPoint) -> Bool {
        guard isTrusted() else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
        return true
    }

    /// 在当前点发一次左键按下抬起。不先改位置。
    /// - Returns: 未授权时 false。
    @discardableResult
    static func leftClick(at point: CGPoint) -> Bool {
        guard isTrusted() else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return true
    }
}

import AppKit
```

把 `import AppKit` 挪到文件顶部，与其它 import 放一起（不要放在文件末尾）。最终文件头应为：

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
```

- [ ] **Step 2: 编译**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。

---

### Task 7: PeripheralYield

**Files:**
- Create: `HeadPointer/HeadPointer/PeripheralYield.swift`

- [ ] **Step 1: 写 PeripheralYield.swift**

用「我们刚写下的点」对比当前指针，并监听非本进程意图的按键/滚轮。`posting` 标志排除自己的 `CGEvent` 触发的 monitor。

```swift
import AppKit
import Foundation

/// 外设一动，头控让路 1.0 秒。不改手动暂停，不改校准原点。
final class PeripheralYield {
    private let slop: CGFloat = 2
    private let window: TimeInterval = 1.0
    private var lastPosted: CGPoint?
    private var lastExternalAt: TimeInterval?
    private var posting = false
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
        lastExternalAt = nil
        posting = false
    }

    /// `PointerDriver.move` 即将/刚刚 post 时包一层，避免把自己当成外设。
    func performingPost(_ body: () -> Void) {
        posting = true
        body()
        posting = false
    }

    /// 记录头控写下的位置，供下一帧对比。
    func notePosted(_ point: CGPoint) {
        lastPosted = point
    }

    /// - Parameters:
    ///   - now: `ProcessInfo.processInfo.systemUptime`。
    ///   - currentPointer: 当前 Quartz 指针。
    /// - Returns: 是否处于让路窗口。
    func isYielding(now: TimeInterval, currentPointer: CGPoint) -> Bool {
        if let posted = lastPosted {
            let d = hypot(currentPointer.x - posted.x, currentPointer.y - posted.y)
            if d > slop {
                lastExternalAt = now
            }
        }
        if let lastExternalAt, now - lastExternalAt < window {
            return true
        }
        return false
    }

    private func handleMonitor() {
        if posting { return }
        lastExternalAt = ProcessInfo.processInfo.systemUptime
    }
}
```

- [ ] **Step 2: 编译**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。

---

### Task 8: HotkeyMonitor

**Files:**
- Create: `HeadPointer/HeadPointer/HotkeyMonitor.swift`

- [ ] **Step 1: 写 HotkeyMonitor.swift**

H=4、R=15、P=35（ANSI）。本地+全局监听，避免菜单栏 App 无焦点时丢键。

```swift
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

    func stop() {
        for m in monitors {
            NSEvent.removeMonitor(m)
        }
        monitors.removeAll()
    }

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
```

- [ ] **Step 2: 编译**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。

---

### Task 9: AppState 状态机

**Files:**
- Create: `HeadPointer/HeadPointer/AppState.swift`

- [ ] **Step 1: 写 AppState.swift（唯一接线处）**

```swift
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

/// 会话状态机：校准、三种暂停、映射、点击。不直接持有 `CMHeadphoneMotionManager`。
@MainActor
final class AppState: ObservableObject {
    @Published var phase: SessionPhase = .off
    @Published var yawDegrees: Double?
    @Published var pitchDegrees: Double?
    @Published var manualPause = false
    @Published var lookDownPauseActive = false
    @Published var peripheralYieldActive = false
    @Published var motionStatusText = "运动权限：未知"
    @Published var accessibilityTrusted = false
    @Published var startHint = ""

    /// 水平满屏角，写入 UserDefaults。范围 12...40，默认 22。
    @Published var maxYawDegrees: Double = ScreenMapper.defaultYawDegrees {
        didSet {
            mapper.maxYawDegrees = maxYawDegrees
            UserDefaults.standard.set(maxYawDegrees, forKey: Self.yawKey)
        }
    }

    private static let yawKey = "maxYawDegrees"

    private let motion = HeadMotionSource()
    private var mapper = ScreenMapper()
    private var lookDown = LookDownPause()
    private var nod = NodClickDetector()
    private let yield = PeripheralYield()
    private let hotkeys = HotkeyMonitor()

    init() {
        let stored = UserDefaults.standard.object(forKey: Self.yawKey) as? Double
        maxYawDegrees = stored ?? ScreenMapper.defaultYawDegrees
        mapper.maxYawDegrees = maxYawDegrees
        motion.delegate = MotionBridge(owner: self)
        hotkeys.onToggleSession = { [weak self] in self?.toggleSession() }
        hotkeys.onRecenter = { [weak self] in self?.recenter() }
        hotkeys.onToggleManualPause = { [weak self] in self?.toggleManualPause() }
        hotkeys.start()
        refreshPermissions()
    }

    /// 图标四态。
    var iconName: String {
        switch phase {
        case .off: return "dot.scope"
        case .tracking: return "dot.scope.display"
        case .paused: return "pause.circle"
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    /// 暂停原因文案，优先：手动 ＞ 低头 ＞ 外设。
    var statusText: String {
        switch phase {
        case .off:
            return "已关闭"
        case .disconnected:
            return "未连接兼容耳机，或本机无法提供头部运动数据"
        case .tracking:
            if !accessibilityTrusted {
                return "追踪中（未授权辅助功能，指针不会动）"
            }
            return "追踪中"
        case .paused:
            if manualPause { return "手动暂停" }
            if lookDownPauseActive { return "低头暂停" }
            if peripheralYieldActive { return "外设优先" }
            return "已暂停"
        }
    }

    var isRunning: Bool {
        phase == .tracking || phase == .paused || phase == .disconnected
    }

    func refreshPermissions() {
        accessibilityTrusted = PointerDriver.isTrusted()
        switch motion.authorizationStatus {
        case .authorized: motionStatusText = "运动权限：已允许"
        case .denied: motionStatusText = "运动权限：已拒绝"
        case .restricted: motionStatusText = "运动权限：受限制"
        case .notDetermined: motionStatusText = "运动权限：未决定（点开始时会询问）"
        @unknown default: motionStatusText = "运动权限：未知"
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
            startHint = "请在系统设置中允许「运动与健身」。"
            phase = .off
            return
        }
        if !motion.isDeviceMotionAvailable {
            startHint = "需要支持动态头部追踪的耳机，且本机系统能提供头部运动数据。"
            phase = .disconnected
            return
        }
        mapper.resetSmoothing()
        lookDown.reset()
        nod.reset()
        yield.start()
        motion.start(calibrateNow: true)
        manualPause = false
        lookDownPauseActive = false
        peripheralYieldActive = false
        phase = .tracking
        if !accessibilityTrusted {
            PointerDriver.promptIfNeeded()
            startHint = "未授权辅助功能，指针不会动。"
        }
    }

    /// 停止。指针留在原地。
    func stop() {
        motion.stop()
        yield.stop()
        mapper.resetSmoothing()
        lookDown.reset()
        nod.reset()
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
        if phase == .tracking, accessibilityTrusted {
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

    func toggleManualPause() {
        guard phase == .tracking || phase == .paused else { return }
        manualPause.toggle()
        applyPausePhase()
    }

    fileprivate func handleConnect() {
        // 规格：重新戴上不自动恢复。保持断开，等用户点开始。
    }

    fileprivate func handleDisconnect() {
        guard phase != .off else { return }
        motion.stop()
        yield.stop()
        nod.reset()
        lookDown.reset()
        phase = .disconnected
        yawDegrees = nil
        pitchDegrees = nil
    }

    fileprivate func handleSample(_ sample: HeadPoseSample) {
        guard phase != .off else { return }
        if phase == .disconnected { return }

        yawDegrees = sample.yaw * 180.0 / .pi
        pitchDegrees = sample.pitch * 180.0 / .pi

        let mapped = mapper.map(rawYaw: sample.yaw, rawPitch: sample.pitch)
        let now = ProcessInfo.processInfo.systemUptime
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
```

`HeadMotionSource.delegate` 是 `weak`，`MotionBridge` 必须被 `AppState` 强持有。把 `AppState` 里的这一行：

```swift
motion.delegate = MotionBridge(owner: self)
```

改成属性：

```swift
private let motion = HeadMotionSource()
private lazy var bridge: MotionBridge = MotionBridge(owner: self)
```

`init` 中：

```swift
motion.delegate = bridge
```

并让 `MotionBridge` 不要标成仅 fileprivate 看不见——保持本文件内 `private final class MotionBridge` 即可。

- [ ] **Step 2: 编译**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。若报 `MotionBridge` 立刻释放，检查 `bridge` 已被强引用。

---

### Task 10: 菜单栏 UI 接上入口

**Files:**
- Create: `HeadPointer/HeadPointer/MenuBarView.swift`
- Modify: `HeadPointer/HeadPointer/HeadPointerApp.swift`（整文件替换）

- [ ] **Step 1: 写 MenuBarView.swift**

```swift
import SwiftUI

/// 菜单栏弹出内容。中文。快捷键只展示，不在此重复实现。
struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.statusText)
            if !state.startHint.isEmpty {
                Text(state.startHint).foregroundStyle(.secondary)
            }
            Text(angleText)
            Divider()
            if state.phase == .off || state.phase == .disconnected {
                Button("开始") { state.start() }
            } else {
                Button("停止") { state.stop() }
            }
            Button("重新校准") { state.recenter() }
                .disabled(state.phase != .tracking && state.phase != .paused)
            Button(state.manualPause ? "继续（取消手动暂停）" : "暂停") {
                state.toggleManualPause()
            }
            .disabled(state.phase != .tracking && state.phase != .paused)
            Divider()
            Text("灵敏度（满屏水平角 \(Int(state.maxYawDegrees.rounded()))°）")
            Slider(value: $state.maxYawDegrees, in: ScreenMapper.minYawDegrees...ScreenMapper.maxYawDegreesLimit)
            Text("灵敏 ← → 迟钝").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text(state.motionStatusText)
            Text(state.accessibilityTrusted ? "辅助功能：已允许" : "辅助功能：未允许")
            Button("打开运动与健身设置") { PointerDriver.openMotionSettings() }
            Button("打开辅助功能设置") { PointerDriver.openAccessibilitySettings() }
            Divider()
            Text("⌃⌥⌘H 开始/停止").font(.caption)
            Text("⌃⌥⌘R 重新校准").font(.caption)
            Text("⌃⌥⌘P 手动暂停").font(.caption)
            Divider()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .padding(8)
        .frame(minWidth: 280)
        .onAppear { state.refreshPermissions() }
    }

    private var angleText: String {
        if let yaw = state.yawDegrees, let pitch = state.pitchDegrees {
            return String(format: "左右 %.1f°   上下 %.1f°", yaw, pitch)
        }
        return "左右 —   上下 —"
    }
}

import AppKit
```

将 `import AppKit` 移到文件顶。

- [ ] **Step 2: 替换 HeadPointerApp.swift**

```swift
import SwiftUI

/// 菜单栏入口。无 Dock 图标。
@main
struct HeadPointerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(systemName: state.iconName)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3: 编译**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build
```

Expected: `BUILD SUCCEEDED`。

---

### Task 11: 安装到 /Applications 并对照 spec §9

**Files:** 无新代码（若左右/上下反了，只改 `ScreenMapper` 的 `yawSign` / `pitchSign` 默认值）。

- [ ] **Step 1: Debug 构建并定位 .app**

Run:

```bash
xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug build -showBuildSettings | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/ {print $2}'
```

Expected: 打出 `DerivedData/.../Build/Products/Debug`。该目录下应有 `HeadPointer.app`。

复制到 `/Applications`（辅助功能要认稳定路径）：

```bash
APP=$(xcodebuild -project HeadPointer/HeadPointer.xcodeproj -scheme HeadPointer -configuration Debug -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/ {print $2; exit}')
cp -R "$APP/HeadPointer.app" /Applications/
open /Applications/HeadPointer.app
```

Expected: 菜单栏出现准星类图标，无 Dock 图标。

- [ ] **Step 2: 按 spec §9 手动过一遍（实现者勾）**

1. 戴兼容耳机作 Mac 音频输出；点开始；授权运动。Intel 上若 `isDeviceMotionAvailable == false`，菜单必须显示断开说明，进程不能崩。
2. 看主屏中心点开始：指针到中心附近。
3. 头转向四角：指针到对应象限；头停指针停。若左右或上下反了，把 `ScreenMapper.yawSign` 或 `pitchSign` 改为 `-1`，重新编译，不要加第二种映射。
4. 对着图标短点头：一次左键；300ms 内连点无效。
5. 低头看桌面 ≥ 0.4s：状态「低头暂停」，点头不点击。
6. 抬头：恢复，指针跳到当前朝向。
7. 灵敏度滑杆两端：到边缘所需转头明显变小/变大。
8. 摘耳机：状态断开，指针停。
9. 关掉辅助功能再开始：角度可动，指针不动。
10. 追踪中用外接鼠标挪走并点击：跟手；点头无效；停手 1 秒后头控恢复并可能跳回脸朝向。

- [ ] **Step 3: 确认非目标没有做进去**

打开工程搜一遍，不得出现：第二种 Mapper、游戏开关、多屏扩展、沙盒 true、开机自启、右键/拖拽/双击。

---

## 规格覆盖（自审）

| spec | 任务 |
| --- | --- |
| §3 部署 14.0、Universal、bundle、中文名、灵敏度 UserDefaults | 1, 9, 10 |
| §3 / §8 `isDeviceMotionAvailable`、Intel 文案 | 2, 9 |
| §4 菜单项、四态图标、快捷键、角度、权限入口 | 8, 9, 10 |
| §5 / §5.2 组件边界与相对姿态 | 2–9 |
| §6.1 开始停止校准 | 9 |
| §6.2 激光笔公式、死区、平滑 | 3 |
| §6.3 点头 | 5, 9 |
| §6.4 三种暂停 + 断开 | 4, 7, 9 |
| §6.5 外设让路 1.0s / 2px | 7, 9 |
| §6.6 CGEvent 非 Warp | 6 |
| §7 Info.plist 文案、非脚本 .app | 1 |
| §9 十条验证 | 11 |
| §10 不实现第二种映射 | 11 Step 3 |

无 TBD。`yawSign`/`pitchSign` 默认 `1`，反了只改这两个常量（Task 11 Step 2）。

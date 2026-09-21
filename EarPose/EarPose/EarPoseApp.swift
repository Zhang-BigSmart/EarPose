import SwiftUI

/// EarPose 菜单栏入口。无 Dock 图标。
@main
struct EarPoseApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(state.menuBarImageName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.window)
    }
}

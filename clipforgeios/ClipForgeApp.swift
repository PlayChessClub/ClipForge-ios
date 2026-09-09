import SwiftUI

@main
struct ClipForgeiOSApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            TabView {
                ImageView()
                    .tabItem { Label("图片", systemImage: "photo") }
                VideoView()
                    .tabItem { Label("视频", systemImage: "video") }
                VoiceView()
                    .tabItem { Label("语音", systemImage: "waveform") }
                StudioView()
                    .tabItem { Label("时间线", systemImage: "rectangle.stack") }
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
            .environmentObject(settings)
        }
    }
}

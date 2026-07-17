import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

struct WrapperView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("키프레임 서드파티 플러그인 래퍼")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            Text("이 앱은 파이널컷 프로(FCP) 플러그인을 macOS 시스템에\n자동 등록하기 위한 래퍼 프로그램입니다.")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Text("상태: 플러그인이 정상 등록되었습니다.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.green)
        }
        .padding(30)
        .frame(width: 400, height: 280)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }
}

@main
struct WrapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            WrapperView()
                .preferredColorScheme(.dark)
        }
    }
}

import Cocoa
import SwiftUI

/// 일반 사용자가 앱을 한 번 여는 것만으로 FxPlug 확장을 등록하도록 하는 설치 상태.
final class PluginInstallState: ObservableObject {
    @Published var message = "플러그인을 macOS에 등록하고 있습니다…"
    @Published var isSuccess = false
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let installState = PluginInstallState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        registerPluginExtension()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// build_fxplug.sh에서만 하던 PlugInKit 등록을 배포 앱에서도 실행한다.
    /// 따라서 사용자는 터미널 없이 Applications 폴더에 앱을 넣고 한 번 열면 된다.
    private func registerPluginExtension() {
        let extensionURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/PlugIns/KeyframeToolboxExtension.pluginkit")
        let identifier = "com.user.KeyframeToolboxV6.KeyframeToolboxExtension"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard FileManager.default.fileExists(atPath: extensionURL.path) else {
                self?.updateInstallState("플러그인 파일을 찾지 못했습니다. 앱을 다시 다운로드해 주세요.", success: false)
                return
            }

            do {
                let addStatus = try Self.runPluginKit(arguments: ["-a", extensionURL.path])
                let enableStatus = try Self.runPluginKit(arguments: ["-e", "use", "-i", identifier])
                guard addStatus == 0, enableStatus == 0 else {
                    self?.updateInstallState("등록에 실패했습니다. 앱을 Applications 폴더로 옮긴 뒤 다시 열어 주세요.", success: false)
                    return
                }
                try Self.installMotionTemplate()
                self?.updateInstallState("등록 완료 — Final Cut Pro/Motion을 완전히 종료 후 다시 실행하세요.", success: true)
            } catch {
                self?.updateInstallState("등록에 실패했습니다: \(error.localizedDescription)", success: false)
            }
        }
    }

    private static func runPluginKit(arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Motion Publish 효과는 FxPlug 앱과 별도로 Movies/Motion Templates에 있어야
    /// Final Cut Pro 효과 브라우저에 표시된다. 이 앱 전용 카테고리는 매번 최신
    /// 발행본으로 교체해, 오래된 템플릿과 새 FxPlug 엔진이 엇갈리지 않게 한다.
    private static func installMotionTemplate() throws {
        guard let resourceURL = Bundle.main.resourceURL,
              let moviesURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "KeyframeToolbox", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Motion 템플릿 설치 경로를 찾지 못했습니다."])
        }

        let source = resourceURL.appendingPathComponent("KeyframeToolboxMotionTemplate.zip")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw NSError(domain: "KeyframeToolbox", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "번들에 Motion 효과 템플릿 아카이브가 없습니다."])
        }

        let destinationParent = moviesURL
            .appendingPathComponent("Motion Templates.localized")
            .appendingPathComponent("Effects.localized")
        let destination = destinationParent.appendingPathComponent("Keyframe Toolbox")
        try FileManager.default.createDirectory(at: destinationParent,
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            // Keyframe Toolbox는 이 설치기가 소유하는 전용 카테고리다.
            // 이전 배포본의 .moef를 제거한 뒤 같은 경로에 최신 발행본을 복사한다.
            try FileManager.default.removeItem(at: destination)
        }
        // ZIP 안의 Finder 타입/확장 속성을 보존해 .moef를 Motion effect로 설치한다.
        let status = try runDitto(archive: source, destination: destinationParent)
        guard status == 0 else {
            throw NSError(domain: "KeyframeToolbox", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Motion 효과 템플릿 복사에 실패했습니다."])
        }
    }

    private static func runDitto(archive: URL, destination: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // 앱 다운로드에 붙은 quarantine은 템플릿에 전달하지 않고, Motion 메타데이터만 보존한다.
        process.arguments = ["-x", "-k", "--rsrc", "--extattr", "--noqtn", archive.path, destination.path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func updateInstallState(_ message: String, success: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.installState.message = message
            self?.installState.isSuccess = success
        }
    }
}

struct WrapperView: View {
    @ObservedObject var installState: PluginInstallState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 60))
                .foregroundColor(installState.isSuccess ? .green : .orange)
            Text("키프레임 서드파티 플러그인")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
            Text("이 앱은 Final Cut Pro/Motion용 FxPlug 확장을\nmacOS에 자동 등록합니다.")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Text(installState.message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(installState.isSuccess ? .green : .orange)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(width: 420, height: 280)
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }
}

@main
struct WrapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            WrapperView(installState: appDelegate.installState)
                .preferredColorScheme(.dark)
        }
    }
}

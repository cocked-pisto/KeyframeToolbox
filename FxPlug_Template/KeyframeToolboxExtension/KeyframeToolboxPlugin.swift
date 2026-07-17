import Foundation
import Cocoa
import FxPlug
import SwiftUI
import CoreImage
import CoreMedia

/// 렌더 시점에 확정된 값. pluginState로 렌더 경로에 전달한다.
/// 렌더는 백그라운드에서 불릴 수 있어 파라미터 API를 직접 만지지 않는다.
private struct RenderState: Codable {
    var scale: Double
    var positionX: Double
    var positionY: Double
    var opacity: Double
    var rotationZ: Double
    var rotationY: Double
    var rotationX: Double
    var blur: Double
    var usesOpacity: Bool

    static let neutral = RenderState(scale: 1, positionX: 0, positionY: 0,
                                     opacity: 1, rotationZ: 0, rotationY: 0, rotationX: 0,
                                     blur: 0, usesOpacity: false)
}

/// 렌더는 초당 수십 번 호출되므로 파일 I/O를 하면 재생과 컷 직후에
/// 호스트 수명주기와 불필요하게 경쟁한다. 필요할 때만 Debug 로그를 켠다.
private func kfLog(_ message: String) {
    #if DEBUG
    NSLog("KeyframeToolbox: \(message)")
    #endif
}

/// Inspector 생성 문제 전용 진단. 렌더 경로에서는 절대 호출하지 않는다.
func kfUITrace(_ message: String) {
    let line = "\(Date().timeIntervalSince1970) UI \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/kftb-ui.log")
    guard let data = line.data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        try? handle.write(contentsOf: data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

/// 파이널컷 프로 / Motion에서 호출되는 FxPlug 4.0 플러그인 클래스
@objc(KeyframeToolboxPlugin)
class KeyframeToolboxPlugin: NSObject, FxTileableEffect, FxCustomParameterViewHost_v2 {

    var apiManager: PROAPIAccessing?
    static let tracksDidChangeNotification = Notification.Name("KeyframeToolboxTracksDidChange")
    static let playheadDidChangeNotification = Notification.Name("KeyframeToolboxPlayheadDidChange")

    // 파라미터 ID
    //
    // 커스텀 파라미터 값은 FxPlug이 NSKeyedArchiver로 저장/복원한다.
    // 거기에 JSON 원본 NSData를 넣으면 읽을 때 언아카이브에 실패하며 익스텐션이 죽는다.
    // 그래서 데이터는 숨긴 문자열 파라미터에 두고, 커스텀 파라미터는 UI 호스팅에만 쓴다.
    //
    // ID 1은 그래프 UI로 고정한다. Motion 템플릿이 발행한 파라미터를 ID로 찾기 때문에,
    // 여기를 바꾸면 이미 발행된 템플릿이 엉뚱한 파라미터를 가리킨다.
    static let kParamGraphUI: UInt32 = 1      // 그래프 UI 자리 (템플릿이 발행하는 대상)
    static let kParamTracksJSON: UInt32 = 2   // 트랙 JSON (숨김, 발행하지 않음)

    // CIContext는 생성 비용이 커서 프레임마다 만들지 않는다.
    private let ciContext = CIContext(options: nil)

    // Inspector는 재생 중에 XPC 파라미터 API를 동기 호출하면 FCP와 서로 기다릴 수 있다.
    // 렌더 콜백에서 이미 읽은 값을 스냅샷으로 보관하고, UI는 이 메모리 값만 읽는다.
    private let tracksCacheLock = NSLock()
    private var cachedTracks = TrackSet.makeDefault()
    private var cachedTimeDomain: TrackTimeDomain?
    private var cachedTracksSignature = ""
    private var hasCachedTracks = false

    // 렌더는 백그라운드에서 호출된다. 재생 헤드 값만 잠깐 보호하고, UI 알림은 메인 큐로 보낸다.
    private let playheadLock = NSLock()
    private var lastPublishedPlayhead = -1.0

    required init?(apiManager: PROAPIAccessing) {
        NSLog("=== KeyframeToolboxPlugin: init ===")
        self.apiManager = apiManager
        super.init()
        kfUITrace("plugin init")
    }

    func properties(_ properties: AutoreleasingUnsafeMutablePointer<NSDictionary>?) throws {
        let swiftProps: [String: Any] = [
            // 키프레임에 따라 시간마다 결과가 달라지므로 true여야 FCP가 매 프레임 다시 렌더한다.
            kFxPropertyKey_VariesWhenParamsAreStatic: NSNumber(booleanLiteral: true),
            kFxPropertyKey_PixelTransformSupport: NSNumber(value: kFxPixelTransform_Full)
        ]
        properties?.pointee = NSDictionary(dictionary: swiftProps)
    }

    func addParameters() throws {
        guard let apiManager = self.apiManager,
              let paramAPI = apiManager.api(for: FxParameterCreationAPI_v5.self) as? FxParameterCreationAPI_v5 else {
            NSLog("=== KeyframeToolboxPlugin: FxParameterCreationAPI 획득 실패 ===")
            return
        }

        // 그래프 에디터가 그려질 자리. 값은 쓰지 않고 UI 호스팅에만 쓴다.
        // Motion 템플릿이 발행하는 대상이라 반드시 ID 1이어야 한다.
        paramAPI.addCustomParameter(withName: "키프레임 그래프",
                                    parameterID: Self.kParamGraphUI,
                                    defaultValue: NSNumber(value: 0),
                                    // FCP 인스펙터의 레이블 폭을 제외한 전체 행을 그래프 UI에 준다.
                                    parameterFlags: FxParameterFlags(kFxParameterFlag_CUSTOM_UI |
                                                                     kFxParameterFlag_USE_FULL_VIEW_WIDTH))

        // 트랙 데이터 본체. 문자열이라 아카이버를 거치지 않는다.
        // 발행하지 않으므로 FCP 인스펙터에는 나타나지 않는다.
        let defaultJSON = String(data: TrackSet.makeDefault().encoded(), encoding: .utf8) ?? "{}"
        paramAPI.addStringParameter(withName: "Tracks",
                                    parameterID: Self.kParamTracksJSON,
                                    defaultValue: defaultJSON,
                                    parameterFlags: FxParameterFlags(kFxParameterFlag_HIDDEN | kFxParameterFlag_NOT_ANIMATABLE))
    }

    // MARK: - 커스텀 UI

    // FCP가 반환 객체를 소유하고 해제한다. 따라서 절대 캐시/재사용하지 않는다.
    // NS_RETURNS_RETAINED 계약을 Swift ARC에서도 명시적으로 보장해 caller에게 +1을 넘긴다.
    func createView(forParameterID parameterID: UInt32) -> NSView? {
        kfUITrace("createView enter id=\(parameterID)")
        guard parameterID == Self.kParamGraphUI else { return nil }
        kfUITrace("createView make hosting")
        let hostingView = NSHostingView(rootView: KeyframeToolboxView(plugin: self))
        // 초기 선호 크기일 뿐, 실제 폭은 USE_FULL_VIEW_WIDTH와 Auto Layout이 정한다.
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 680)
        hostingView.autoresizingMask = [.width, .height]
        kfUITrace("createView return retained new")
        return Unmanaged.passRetained(hostingView).takeUnretainedValue()
    }

    // MARK: - 트랙 읽기/쓰기

    /// 호스트가 이미 파라미터 접근을 허용한 시점(예: pluginState)에서만 호출한다.
    /// 저장된 게 없거나 깨졌으면 기본 트랙을 돌려준다.
    private func readTracks() -> TrackSet {
        guard let apiManager,
              let retrievalAPI = apiManager.api(for: FxParameterRetrievalAPI_v6.self) as? FxParameterRetrievalAPI_v6 else {
            kfLog("readTracks ABORT: retrieval API 없음")
            return .makeDefault()
        }
        var json: NSString = ""
        retrievalAPI.getStringParameterValue(&json, fromParameter: Self.kParamTracksJSON)
        let tracks = TrackSet.decoded(from: (json as String).data(using: .utf8))
        kfLog("readTracks bytes=\((json as String).utf8.count) scale=\(tracks.scale.keyframes.count) posX=\(tracks.positionX.keyframes.count) posY=\(tracks.positionY.keyframes.count)")
        return tracks
    }

    /// SwiftUI 커스텀 뷰에서 트랙을 읽는 진입점.
    ///
    /// FxPlug 4에서는 startAction이 호스트 파라미터를 XPC 서비스에 준비시킨 뒤에야
    /// retrieval API가 유효해진다. UI 생명주기(onAppear)는 호스트 콜백이 아니므로
    /// 반드시 이 쌍으로 감싼다.
    func loadTracksForCustomView() -> TrackSet {
        tracksCacheLock.lock()
        let tracks = cachedTracks
        let domain = cachedTimeDomain
        let isReady = hasCachedTracks
        tracksCacheLock.unlock()

        // 렌더가 아직 한 번도 돌지 않은 짧은 순간은 기본 그래프를 보여 준다.
        // 렌더 스냅샷이 도착하면 Notification으로 즉시 실제 값으로 교체된다.
        guard isReady else { return .makeDefault() }
        return domain.map { tracks.projected(for: $0) } ?? tracks
    }

    /// 렌더 준비 콜백에서는 호스트가 이미 접근 권한을 제공한다. 여기서 startAction을
    /// 다시 호출하면 렌더 경로를 UI 액션으로 오인하게 되므로 호출하지 않는다.
    private func loadTracksForRendering() -> TrackSet {
        // 렌더 스레드는 UI 상태나 NotificationCenter를 절대 건드리지 않는다.
        // FCP가 같은 순간 Inspector를 교체할 수 있기 때문이다.
        readTracks()
    }

    private func cacheTracksForInspector(_ tracks: TrackSet, currentDomain: TrackTimeDomain?) {
        let signature = String(data: tracks.encoded(), encoding: .utf8) ?? ""
        tracksCacheLock.lock()
        let changed = !hasCachedTracks || signature != cachedTracksSignature || currentDomain != cachedTimeDomain
        cachedTracks = tracks
        cachedTimeDomain = currentDomain
        cachedTracksSignature = signature
        hasCachedTracks = true
        tracksCacheLock.unlock()

        guard changed else { return }
        // UI 갱신은 메인 큐에서만, 그리고 렌더 호출이 끝난 뒤에 실행한다.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: Self.tracksDidChangeNotification, object: self)
        }
    }

    /// 모든 그래프가 공유하는 0~1 재생 위치를 UI에 전달한다.
    /// 프레임마다 중복 알림을 만들지 않도록 아주 작은 변화를 걸러낸다.
    private func publishPlayhead(_ normalizedTime: Double) {
        playheadLock.lock()
        let changed = abs(normalizedTime - lastPublishedPlayhead) >= 0.001
        if changed { lastPublishedPlayhead = normalizedTime }
        playheadLock.unlock()
        guard changed else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: Self.playheadDidChangeNotification,
                                            object: self,
                                            userInfo: ["time": normalizedTime])
        }
    }

    /// 편집한 트랙을 숨긴 문자열 파라미터에 저장한다.
    ///
    /// 커스텀 UI에서 파라미터를 바꿀 때는 반드시 startAction/endAction으로 감싸야 한다.
    /// 그 밖에서 쓴 값은 호스트가 커밋하지 않고 버리기 때문에,
    /// 화면에는 반영된 것처럼 보이지만 렌더는 예전 값을 읽고 인스펙터를 다시 열면 되돌아간다.
    func saveTracks(_ tracks: TrackSet) {
        guard let apiManager,
              let actionAPI = apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4 else {
            kfLog("saveTracks ABORT: action API 없음")
            return
        }

        // 중요: Setting API를 얻기 전에 startAction을 호출해야 한다. FxPlug 4 호스트는
        // 이 호출에서 파라미터 상태를 XPC 서비스로 보내고, endAction에서 변경을 커밋한다.
        actionAPI.startAction(self)
        defer { actionAPI.endAction(self) }

        var tracksToSave = tracks
        if let domain = currentTimeDomain() { tracksToSave.timeDomain = domain }
        guard let json = String(data: tracksToSave.encoded(), encoding: .utf8) else {
            kfLog("saveTracks ABORT: JSON 인코딩 실패")
            return
        }

        guard let settingAPI = apiManager.api(for: FxParameterSettingAPI_v5.self) as? FxParameterSettingAPI_v5 else {
            kfLog("saveTracks ABORT: setting API 없음 (startAction 이후)")
            return
        }

        let ok = settingAPI.setStringParameterValue(json, toParameter: Self.kParamTracksJSON)
        if ok { cacheTracksForInspector(tracksToSave, currentDomain: tracksToSave.timeDomain) }
        kfLog("saveTracks bytes=\(json.utf8.count) scale=\(tracksToSave.scale.keyframes.count) posX=\(tracksToSave.positionX.keyframes.count) posY=\(tracksToSave.positionY.keyframes.count) setOK=\(ok)")
    }

    /// 그래프의 0~1 위치를 현재 FCP 타임라인 시간으로 변환해 재생 헤드를 이동한다.
    /// Final Cut Pro의 input time과 timeline time은 서로 다를 수 있으므로 반드시
    /// FxTimingAPI 변환을 거친다.
    func movePlayhead(toNormalizedTime normalizedTime: Double) {
        guard let apiManager,
              let actionAPI = apiManager.api(for: FxCustomParameterActionAPI_v4.self) as? FxCustomParameterActionAPI_v4 else { return }

        actionAPI.startAction(self)
        defer { actionAPI.endAction(self) }

        guard let domain = currentTimeDomain(),
              let timingAPI = apiManager.api(for: FxTimingAPI_v4.self) as? FxTimingAPI_v4,
              let commandAPI = apiManager.api(for: FxCommandAPI_v2.self) as? FxCommandAPI_v2 else { return }

        let t = min(max(normalizedTime, 0), 1)
        let inputTime = CMTimeMakeWithSeconds(domain.start + domain.duration * t,
                                               preferredTimescale: 600)
        var timelineTime = CMTime.zero
        timingAPI.timelineTime(&timelineTime, fromInputTime: inputTime)
        do {
            try commandAPI.movePlayhead(to: timelineTime)
            kfUITrace("movePlayhead t=\(String(format: "%.3f", t)) ok=true")
        } catch {
            kfUITrace("movePlayhead failed: \(error.localizedDescription)")
        }
    }

    /// FCP의 Cmd+Z / Shift+Cmd+Z도 일반적인 파라미터 변경으로 전달된다.
    /// 렌더 값은 호스트가 자동으로 복원하지만, SwiftUI의 @State도 같은 JSON을 다시
    /// 읽어야 다음 편집에서 Undo된 값을 덮어쓰지 않는다.
    func parameterChanged(_ paramID: UInt32, at time: CMTime) throws {
        guard paramID == Self.kParamTracksJSON else { return }
        kfLog("parameterChanged Tracks: UI 동기화 요청")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: Self.tracksDidChangeNotification, object: self)
        }
    }

    /// renderTime을 클립 기준 0.0~1.0으로 환산한다.
    /// 그래프의 가로축이 곧 클립 전체 길이이므로 이 환산이 전체 동작의 기준이 된다.
    private func normalizedTime(at renderTime: CMTime) -> Double {
        guard let domain = currentTimeDomain() else { return 0 }
        return min(max((CMTimeGetSeconds(renderTime) - domain.start) / domain.duration, 0), 1)
    }

    private func currentTimeDomain() -> TrackTimeDomain? {
        guard let apiManager,
              let timingAPI = apiManager.api(for: FxTimingAPI_v4.self) as? FxTimingAPI_v4 else { return nil }
        var start = CMTime.zero
        var duration = CMTime.zero
        timingAPI.startTime(forEffect: &start)
        timingAPI.durationTime(forEffect: &duration)
        let startSeconds = CMTimeGetSeconds(start)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard startSeconds.isFinite, durationSeconds.isFinite, durationSeconds > 0 else { return nil }
        return TrackTimeDomain(start: startSeconds, duration: durationSeconds)
    }

    // MARK: - FxTileableEffect

    /// 렌더 시점의 값을 여기서 확정해 렌더 경로로 넘긴다.
    func pluginState(_ pluginState: AutoreleasingUnsafeMutablePointer<NSData>?, at renderTime: CMTime, quality qualityLevel: UInt) throws {
        let tracks = loadTracksForRendering()
        let currentDomain = currentTimeDomain()
        cacheTracksForInspector(tracks, currentDomain: currentDomain)
        let localTime: Double
        if let currentDomain {
            localTime = min(max((CMTimeGetSeconds(renderTime) - currentDomain.start) / currentDomain.duration, 0), 1)
        } else {
            localTime = 0
        }
        let evaluationTime: Double
        if let source = tracks.timeDomain,
           let current = currentDomain,
           source.duration > 1e-9 {
            evaluationTime = min(max((current.start + localTime * current.duration - source.start) / source.duration, 0), 1)
        } else {
            evaluationTime = localTime
        }
        publishPlayhead(localTime)
        let enabled = tracks.enabledProperties
        let state = RenderState(
            scale: enabled.scale ? safeScale(tracks.scale.evaluate(at: evaluationTime)) : 1,
            positionX: enabled.positionX ? tracks.positionX.evaluate(at: evaluationTime) : 0,
            positionY: enabled.positionY ? tracks.positionY.evaluate(at: evaluationTime) : 0,
            opacity: enabled.opacity ? safeOpacity(tracks.opacity.evaluate(at: evaluationTime)) : 1,
            rotationZ: enabled.rotationZ ? safeRotation(tracks.rotationZ.evaluate(at: evaluationTime), limit: 360) : 0,
            rotationY: enabled.rotationY ? safeRotation(tracks.rotationY.evaluate(at: evaluationTime), limit: 85) : 0,
            rotationX: enabled.rotationX ? safeRotation(tracks.rotationX.evaluate(at: evaluationTime), limit: 85) : 0,
            blur: enabled.blur ? safeBlur(tracks.blur.evaluate(at: evaluationTime)) : 0,
            usesOpacity: enabled.opacity)
        let data = (try? JSONEncoder().encode(state)) ?? Data()
        pluginState?.pointee = data as NSData
    }

    /// 비정상 키프레임 값이 Core Image 변환까지 전파되지 않게 한다.
    private func safeScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1.0 }
        return min(max(value, 0.01), 16.0)
    }

    private func safeOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }

    private func safeRotation(_ value: Double, limit: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, -limit), limit)
    }

    private func safeBlur(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 200)
    }

    func destinationImageRect(_ destinationImageRect: UnsafeMutablePointer<FxRect>, sourceImages: [FxImageTile], destinationImage: FxImageTile, pluginState: Data?, at renderTime: CMTime) throws {
        destinationImageRect.pointee = destinationImage.imagePixelBounds
    }

    func sourceTileRect(_ sourceTileRect: UnsafeMutablePointer<FxRect>, sourceImageIndex: UInt, sourceImages: [FxImageTile], destinationTileRect: FxRect, destinationImage: FxImageTile, pluginState: Data?, at renderTime: CMTime) throws {
        let decoded = try? JSONDecoder().decode(RenderState.self, from: pluginState ?? Data())
        let state = decoded ?? .neutral
        let scale = max(abs(state.scale), 0.01)

        // 회전/블러는 역변환의 범위가 사각형이 아니므로 원본 전체를 요구한다.
        // 일반 Scale/Position만 쓸 때는 아래의 타일 최적화가 그대로 유지된다.
        if abs(state.rotationZ) > 0.001 || abs(state.rotationX) > 0.001 ||
            abs(state.rotationY) > 0.001 || state.blur > 0.001 {
            sourceTileRect.pointee = sourceImages[Int(sourceImageIndex)].imagePixelBounds
            return
        }

        // 출력 좌표 = center + scale * (원본 좌표 - center)
        // 이 식을 역으로 풀어 현재 출력 타일에 필요한 원본 영역만 FCP에 요청한다.
        // 기존에는 NeedsFullBuffer로 매 프레임 원본 전체를 보내게 했었다.
        let bounds = destinationImage.imagePixelBounds
        let centerX = Double(bounds.left + bounds.right) * 0.5
        let centerY = Double(bounds.bottom + bounds.top) * 0.5
        // 가상 Position 100은 현재 캔버스의 폭/높이 100%에 해당한다.
        let positionX = state.positionX * Double(bounds.right - bounds.left) / 100.0
        let positionY = state.positionY * Double(bounds.top - bounds.bottom) / 100.0
        let pad = 2.0 // Core Image 샘플링 가장자리 여유

        let x0 = centerX + (Double(destinationTileRect.left) - centerX - positionX) / scale
        let x1 = centerX + (Double(destinationTileRect.right) - centerX - positionX) / scale
        let y0 = centerY + (Double(destinationTileRect.bottom) - centerY - positionY) / scale
        let y1 = centerY + (Double(destinationTileRect.top) - centerY - positionY) / scale

        let sourceBounds = sourceImages[Int(sourceImageIndex)].imagePixelBounds
        sourceTileRect.pointee.left = max(sourceBounds.left, Int32(floor(min(x0, x1) - pad)))
        sourceTileRect.pointee.right = min(sourceBounds.right, Int32(ceil(max(x0, x1) + pad)))
        sourceTileRect.pointee.bottom = max(sourceBounds.bottom, Int32(floor(min(y0, y1) - pad)))
        sourceTileRect.pointee.top = min(sourceBounds.top, Int32(ceil(max(y0, y1) + pad)))
    }

    func renderDestinationImage(_ destinationImage: FxImageTile, sourceImages: [FxImageTile], pluginState: Data?, at renderTime: CMTime) throws {
        guard let inputSurface = sourceImages.first?.ioSurface,
              let outputSurface = destinationImage.ioSurface else { return }

        let decoded = try? JSONDecoder().decode(RenderState.self, from: pluginState ?? Data())
        let state = decoded ?? .neutral
        // IOSurface에서 만든 CIImage는 extent가 (0, 0, 타일너비, 타일높이)인 서피스 로컬 좌표계다.
        // 반면 FxPlug의 tile/imagePixelBounds는 원점이 이미지 중앙인 FCP 캔버스 좌표계라
        // 두 좌표계를 섞으면 기준점이 어긋나 확대가 아니라 이미지가 밀려나간다.
        // 따라서 먼저 소스 타일을 FCP 좌표계로 옮긴 뒤 변형한다.
        let srcTile = sourceImages[0].tilePixelBounds
        var image = CIImage(ioSurface: inputSurface)
            .transformed(by: CGAffineTransform(translationX: CGFloat(srcTile.left),
                                               y: CGFloat(srcTile.bottom)))

        // 확대 기준점은 타일이 아니라 이미지 전체의 중앙이어야 한다.
        // (타일 기준으로 잡으면 타일이 쪼개질 때마다 기준점이 달라진다)
        let imageBounds = sourceImages[0].imagePixelBounds
        let centerX = CGFloat(imageBounds.left + imageBounds.right) / 2.0
        let centerY = CGFloat(imageBounds.bottom + imageBounds.top) / 2.0
        let positionX = CGFloat(state.positionX * Double(imageBounds.right - imageBounds.left) / 100.0)
        let positionY = CGFloat(state.positionY * Double(imageBounds.top - imageBounds.bottom) / 100.0)

        var transform = CGAffineTransform(translationX: centerX + positionX,
                                          y: centerY + positionY)
        transform = transform.rotated(by: CGFloat(state.rotationZ * .pi / 180))
        transform = transform.scaledBy(x: CGFloat(state.scale), y: CGFloat(state.scale))
        transform = transform.translatedBy(x: -centerX, y: -centerY)
        image = image.transformed(by: transform)

        if abs(state.rotationX) > 0.001 || abs(state.rotationY) > 0.001 {
            image = perspectiveRotated(image, xDegrees: state.rotationX, yDegrees: state.rotationY)
        }

        if state.blur > 0.001 {
            let extent = image.extent
            image = image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": state.blur])
                .cropped(to: extent)
        }

        if state.usesOpacity, state.opacity < 0.9999 {
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: state.opacity)
            ])
        }

        // render(bounds:)는 이미지 공간의 해당 영역을 출력 서피스 원점에 매핑한다.
        let dstTile = destinationImage.tilePixelBounds
        let renderRect = CGRect(x: CGFloat(dstTile.left),
                                y: CGFloat(dstTile.bottom),
                                width: CGFloat(dstTile.right - dstTile.left),
                                height: CGFloat(dstTile.top - dstTile.bottom))
        // 축소 시 변형 이미지의 extent가 출력 타일보다 작다. 출력 서피스는 자동으로
        // 초기화되지 않으므로, 먼저 검정 배경을 합성해 이전 프레임의 픽셀이 남지 않게 한다.
        let background = state.usesOpacity
            ? CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: renderRect)
            : CIImage(color: CIColor.black).cropped(to: renderRect)
        let output = image.composited(over: background)
        ciContext.render(output, to: outputSurface, bounds: renderRect, colorSpace: destinationImage.colorSpace)
    }

    /// X/Y 회전은 2D affine으로 표현할 수 없으므로, 이미지 네 모서리를 원근 투영한다.
    private func perspectiveRotated(_ image: CIImage, xDegrees: Double, yDegrees: Double) -> CIImage {
        let extent = image.extent
        let centerX = extent.midX
        let centerY = extent.midY
        let halfWidth = extent.width / 2
        let halfHeight = extent.height / 2
        let xRadians = xDegrees * .pi / 180
        let yRadians = yDegrees * .pi / 180
        let focalLength = max(extent.width, extent.height) * 1.8

        func project(_ x: CGFloat, _ y: CGFloat) -> CIVector {
            let x1 = Double(x) * cos(yRadians)
            let z1 = -Double(x) * sin(yRadians)
            let y1 = Double(y) * cos(xRadians) - z1 * sin(xRadians)
            let z2 = Double(y) * sin(xRadians) + z1 * cos(xRadians)
            let perspective = focalLength / max(focalLength + CGFloat(z2), focalLength * 0.15)
            return CIVector(x: centerX + CGFloat(x1) * perspective,
                            y: centerY + CGFloat(y1) * perspective)
        }

        return image.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": project(-halfWidth, halfHeight),
            "inputTopRight": project(halfWidth, halfHeight),
            "inputBottomRight": project(halfWidth, -halfHeight),
            "inputBottomLeft": project(-halfWidth, -halfHeight)
        ])
    }
}

import Foundation
import CoreGraphics

/// 키프레임 하나.
/// time은 클립 기준 정규화 위치(0.0 = 클립 시작, 1.0 = 클립 끝)다.
/// 클립 길이가 바뀌어도 키프레임이 비율을 유지하도록 절대 시간 대신 정규화해 저장한다.
/// 핸들은 키프레임을 원점으로 한 (시간, 값) 오프셋이다.
enum InterpolationMode: String, Codable, CaseIterable, Hashable {
    case linear
    case bezier
    case continuousBezier
    case autoBezier
    case hold
    case easeIn
    case easeOut
    case easeInOut

    var title: String {
        switch self {
        case .linear: "선형"
        case .bezier: "베지어"
        case .continuousBezier: "연속 베지어"
        case .autoBezier: "자동 베지어"
        case .hold: "Hold"
        case .easeIn: "Ease In"
        case .easeOut: "Ease Out"
        case .easeInOut: "Ease In & Out"
        }
    }
}

struct Keyframe: Codable, Identifiable {
    var id: UUID = UUID()
    var time: Double
    var value: Double

    var inHandleTime: Double = 0.0
    var inHandleValue: Double = 0.0
    var outHandleTime: Double = 0.0
    var outHandleValue: Double = 0.0
    /// 이 점에서 다음 점으로 나가는 구간의 보간 방식.
    var outgoingInterpolation: InterpolationMode = .linear
    /// 여러 축/시점의 키프레임을 영구적으로 같은 스케일 값으로 묶는 그룹 ID.
    var syncGroupID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, time, value, inHandleTime, inHandleValue, outHandleTime, outHandleValue, outgoingInterpolation, syncGroupID
    }

    init(id: UUID = UUID(), time: Double, value: Double,
         inHandleTime: Double = 0, inHandleValue: Double = 0,
         outHandleTime: Double = 0, outHandleValue: Double = 0,
         outgoingInterpolation: InterpolationMode = .linear,
         syncGroupID: UUID? = nil) {
        self.id = id
        self.time = time
        self.value = value
        self.inHandleTime = inHandleTime
        self.inHandleValue = inHandleValue
        self.outHandleTime = outHandleTime
        self.outHandleValue = outHandleValue
        self.outgoingInterpolation = outgoingInterpolation
        self.syncGroupID = syncGroupID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        time = try c.decode(Double.self, forKey: .time)
        value = try c.decode(Double.self, forKey: .value)
        inHandleTime = try c.decodeIfPresent(Double.self, forKey: .inHandleTime) ?? 0
        inHandleValue = try c.decodeIfPresent(Double.self, forKey: .inHandleValue) ?? 0
        outHandleTime = try c.decodeIfPresent(Double.self, forKey: .outHandleTime) ?? 0
        outHandleValue = try c.decodeIfPresent(Double.self, forKey: .outHandleValue) ?? 0
        // 이전 저장본에는 이 키가 없으므로 기존 동작과 같은 선형으로 읽는다.
        outgoingInterpolation = try c.decodeIfPresent(InterpolationMode.self, forKey: .outgoingInterpolation) ?? .linear
        syncGroupID = try c.decodeIfPresent(UUID.self, forKey: .syncGroupID)
    }

    /// 핸들이 모두 0이면 그 구간은 직선(선형 보간)으로 처리된다.
    var isLinear: Bool {
        inHandleTime == 0 && inHandleValue == 0 && outHandleTime == 0 && outHandleValue == 0
    }
}

/// 속성 하나에 대한 키프레임 트랙. (예: Scale X)
/// 그래프의 가로축이 이 트랙의 time, 세로축이 value에 대응한다.
struct KeyframeTrack: Codable {
    var name: String
    var minValue: Double
    var maxValue: Double
    var keyframes: [Keyframe]

    /// 정규화 시간 t(0~1)에서의 값. 키프레임 사이는 3차 베지에로 보간한다.
    func evaluate(at t: Double) -> Double {
        guard !keyframes.isEmpty else { return 1.0 }

        let sorted = keyframes.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last else { return 1.0 }

        // 첫 키프레임 이전 / 마지막 키프레임 이후는 각각 끝값을 유지한다.
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }

        // t가 속한 구간 찾기
        var k0 = first
        var k1 = last
        for i in 0..<(sorted.count - 1) where t >= sorted[i].time && t <= sorted[i + 1].time {
            k0 = sorted[i]
            k1 = sorted[i + 1]
            break
        }

        let span = k1.time - k0.time
        guard span > 1e-9 else { return k1.value }

        switch k0.outgoingInterpolation {
        case .hold:
            return k0.value
        case .linear:
            let u = (t - k0.time) / span
            return k0.value + (k1.value - k0.value) * u
        default:
            break
        }

        // 구간을 3차 베지에로 본다.
        // P0 = k0, P1 = k0 + outHandle, P2 = k1 + inHandle, P3 = k1
        let p0 = CGPoint(x: k0.time, y: k0.value)
        let p3 = CGPoint(x: k1.time, y: k1.value)
        let controls = controlPoints(for: k0, end: k1, sorted: sorted)
        let p1 = controls.0
        let p2 = controls.1

        let u = BezierSegment.solveU(forX: t, p0: p0, p1: p1, p2: p2, p3: p3)
        return BezierSegment.sample(u, Double(p0.y), Double(p1.y), Double(p2.y), Double(p3.y))
    }

    private func controlPoints(for start: Keyframe, end: Keyframe, sorted: [Keyframe]) -> (CGPoint, CGPoint) {
        let span = end.time - start.time
        let delta = end.value - start.value

        switch start.outgoingInterpolation {
        case .bezier, .continuousBezier:
            return (CGPoint(x: start.time + start.outHandleTime, y: start.value + start.outHandleValue),
                    CGPoint(x: end.time + end.inHandleTime, y: end.value + end.inHandleValue))
        case .autoBezier:
            let startIndex = sorted.firstIndex(where: { $0.id == start.id }) ?? 0
            let endIndex = sorted.firstIndex(where: { $0.id == end.id }) ?? sorted.count - 1
            let previous = startIndex > 0 ? sorted[startIndex - 1] : start
            let next = endIndex + 1 < sorted.count ? sorted[endIndex + 1] : end
            // Catmull-Rom에 가까운 자동 접선. 시간은 항상 단조롭게 유지한다.
            let p1Value = start.value + (end.value - previous.value) / 6.0
            let p2Value = end.value - (next.value - start.value) / 6.0
            return (CGPoint(x: start.time + span / 3.0, y: p1Value),
                    CGPoint(x: end.time - span / 3.0, y: p2Value))
        case .easeOut:
            return (CGPoint(x: start.time + span * 0.20, y: start.value),
                    CGPoint(x: start.time + span * 0.70, y: start.value + delta * 0.75))
        case .easeIn:
            return (CGPoint(x: start.time + span * 0.30, y: start.value + delta * 0.25),
                    CGPoint(x: start.time + span * 0.80, y: end.value))
        case .easeInOut:
            return (CGPoint(x: start.time + span * 0.25, y: start.value),
                    CGPoint(x: start.time + span * 0.75, y: end.value))
        case .linear, .hold:
            return (CGPoint(x: start.time + span / 3.0, y: start.value + delta / 3.0),
                    CGPoint(x: end.time - span / 3.0, y: end.value - delta / 3.0))
        }
    }

    /// 최소 2개(첫/끝)는 항상 유지한다.
    static func makeDefault(name: String, minValue: Double, maxValue: Double, value: Double) -> KeyframeTrack {
        KeyframeTrack(
            name: name,
            minValue: minValue,
            maxValue: maxValue,
            keyframes: [
                Keyframe(time: 0.0, value: value),
                Keyframe(time: 1.0, value: value)
            ]
        )
    }

    /// 원본 그래프의 [start, end] 구간을 컷된 클립의 0~1 축으로 재배치한다.
    func projected(from start: Double, to end: Double) -> KeyframeTrack {
        let lower = min(max(start, 0), 1)
        let upper = min(max(end, 0), 1)
        let span = upper - lower
        guard span > 1e-9 else { return self }

        var result = [Keyframe(time: 0, value: evaluate(at: lower))]
        for keyframe in keyframes.sorted(by: { $0.time < $1.time }) where keyframe.time > lower && keyframe.time < upper {
            var copy = keyframe
            copy.time = (copy.time - lower) / span
            copy.inHandleTime /= span
            copy.outHandleTime /= span
            result.append(copy)
        }
        result.append(Keyframe(time: 1, value: evaluate(at: upper)))
        return KeyframeTrack(name: name, minValue: minValue, maxValue: maxValue, keyframes: result)
    }
}

/// 시작·끝이 임의의 좌표인 일반 3차 베지에 구간.
/// BezierMath는 (0,0)~(1,1) 단위 곡선 전용이라 키프레임 구간에는 쓸 수 없어 따로 둔다.
enum BezierSegment {

    /// 3차 베지에의 한 성분을 매개변수 u에서 샘플링
    static func sample(_ u: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let m = 1.0 - u
        return m * m * m * a
             + 3.0 * m * m * u * b
             + 3.0 * m * u * u * c
             + u * u * u * d
    }

    private static func sampleDerivative(_ u: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let m = 1.0 - u
        return 3.0 * m * m * (b - a)
             + 6.0 * m * u * (c - b)
             + 3.0 * u * u * (d - c)
    }

    /// x(u) = targetX 가 되는 u를 찾는다. 뉴턴-랩슨으로 시도하고 실패하면 이분 탐색으로 확정한다.
    static func solveU(forX targetX: Double, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> Double {
        let x0 = Double(p0.x), x1 = Double(p1.x), x2 = Double(p2.x), x3 = Double(p3.x)

        let span = x3 - x0
        var u = span > 1e-9 ? (targetX - x0) / span : 0.5

        for _ in 0..<8 {
            let dx = sample(u, x0, x1, x2, x3) - targetX
            if abs(dx) < 1e-6 { return u }
            let slope = sampleDerivative(u, x0, x1, x2, x3)
            if abs(slope) < 1e-6 { break }
            let next = u - dx / slope
            if next < 0.0 || next > 1.0 { break }
            u = next
        }

        var lo = 0.0
        var hi = 1.0
        u = min(max(span > 1e-9 ? (targetX - x0) / span : 0.5, 0.0), 1.0)
        for _ in 0..<40 {
            let x = sample(u, x0, x1, x2, x3)
            if abs(x - targetX) < 1e-6 { return u }
            if targetX > x { lo = u } else { hi = u }
            u = (lo + hi) * 0.5
        }
        return u
    }
}

/// 이 플러그인이 다루는 트랙 전체. 커스텀 파라미터에 통째로 직렬화해 저장한다.
/// 지금은 Scale X / Scale Y 두 개만 다룬다. (확대 = 두 트랙을 같은 지점에서 함께 올림)
struct TrackTimeDomain: Codable, Equatable {
    var start: Double
    var duration: Double
}

/// 설정 팝업에서 켜고 끄는 속성 목록. 저장 데이터에 같이 넣어 프로젝트를 다시 열어도 유지한다.
struct EnabledProperties: Codable, Equatable {
    var opacity = false
    var positionX = true
    var positionY = true
    var scale = true
    var rotationZ = false
    var rotationY = false
    var rotationX = false
    var blur = false
}

struct TrackSet: Codable {
    var scale: KeyframeTrack
    var positionX: KeyframeTrack
    var positionY: KeyframeTrack
    var opacity: KeyframeTrack
    var rotationZ: KeyframeTrack
    var rotationY: KeyframeTrack
    var rotationX: KeyframeTrack
    var blur: KeyframeTrack
    var enabledProperties: EnabledProperties
    /// 키프레임이 만들어진 입력 소스 기준 시간 범위. 기존 데이터는 nil로 읽힌다.
    var timeDomain: TrackTimeDomain?

    static func makeDefault() -> TrackSet {
        TrackSet(
            scale: .makeDefault(name: "Scale", minValue: 0.0, maxValue: 4.0, value: 1.0),
            // Position은 픽셀이 아니라 캔버스 크기에 비례하는 가상 단위다.
            // 100 = 현재 프레임 가로/세로 길이 한 번만큼 이동한다.
            positionX: .makeDefault(name: "Position X", minValue: -500.0, maxValue: 500.0, value: 0.0),
            positionY: .makeDefault(name: "Position Y", minValue: -500.0, maxValue: 500.0, value: 0.0),
            opacity: .makeDefault(name: "Opacity", minValue: 0.0, maxValue: 1.0, value: 1.0),
            rotationZ: .makeDefault(name: "Rotation Z", minValue: -360.0, maxValue: 360.0, value: 0.0),
            rotationY: .makeDefault(name: "Rotation Y", minValue: -85.0, maxValue: 85.0, value: 0.0),
            rotationX: .makeDefault(name: "Rotation X", minValue: -85.0, maxValue: 85.0, value: 0.0),
            blur: .makeDefault(name: "Blur", minValue: 0.0, maxValue: 200.0, value: 0.0),
            enabledProperties: EnabledProperties(),
            timeDomain: nil
        )
    }

    /// 컷 후 현재 클립이 원본 시간축에서 차지하는 부분만 표시용 그래프로 만든다.
    func projected(for currentDomain: TrackTimeDomain) -> TrackSet {
        guard let source = timeDomain, source.duration > 1e-9 else { return self }
        let start = (currentDomain.start - source.start) / source.duration
        let end = (currentDomain.start + currentDomain.duration - source.start) / source.duration
        guard start > 1e-6 || end < 1.0 - 1e-6 else { return self }
        return TrackSet(scale: scale.projected(from: start, to: end),
                        positionX: positionX.projected(from: start, to: end),
                        positionY: positionY.projected(from: start, to: end),
                        opacity: opacity.projected(from: start, to: end),
                        rotationZ: rotationZ.projected(from: start, to: end),
                        rotationY: rotationY.projected(from: start, to: end),
                        rotationX: rotationX.projected(from: start, to: end),
                        blur: blur.projected(from: start, to: end),
                        enabledProperties: enabledProperties,
                        timeDomain: currentDomain)
    }

    func encoded() -> Data {
        // 렌더 스레드에서 값 변화 여부를 비교할 때 JSON 키 순서가 바뀌어
        // 같은 트랙을 다른 값으로 오인하지 않도록 항상 같은 순서로 인코딩한다.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// 저장된 데이터가 없거나 깨졌으면 기본 트랙으로 되돌린다. (렌더 중 절대 실패하면 안 됨)
    enum CodingKeys: String, CodingKey {
        case scale, positionX, positionY, opacity, rotationZ, rotationY, rotationX, blur, enabledProperties, timeDomain
        // v1 데이터 호환용
        case scaleX, scaleY
    }

    init(scale: KeyframeTrack, positionX: KeyframeTrack, positionY: KeyframeTrack,
         opacity: KeyframeTrack, rotationZ: KeyframeTrack, rotationY: KeyframeTrack,
         rotationX: KeyframeTrack, blur: KeyframeTrack, enabledProperties: EnabledProperties,
         timeDomain: TrackTimeDomain?) {
        self.scale = scale
        self.positionX = positionX
        self.positionY = positionY
        self.opacity = opacity
        self.rotationZ = rotationZ
        self.rotationY = rotationY
        self.rotationX = rotationX
        self.blur = blur
        self.enabledProperties = enabledProperties
        self.timeDomain = timeDomain
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let scale = try c.decodeIfPresent(KeyframeTrack.self, forKey: .scale) {
            self.scale = scale
            self.positionX = try c.decodeIfPresent(KeyframeTrack.self, forKey: .positionX)
                ?? .makeDefault(name: "Position X", minValue: -500, maxValue: 500, value: 0)
            self.positionY = try c.decodeIfPresent(KeyframeTrack.self, forKey: .positionY)
                ?? .makeDefault(name: "Position Y", minValue: -500, maxValue: 500, value: 0)
        } else {
            // 이전 Scale X/Y 프로젝트는 X를 균일 Scale 값으로 이어받는다.
            self.scale = try c.decodeIfPresent(KeyframeTrack.self, forKey: .scaleX)
                ?? .makeDefault(name: "Scale", minValue: 0, maxValue: 4, value: 1)
            self.scale.name = "Scale"
            self.positionX = .makeDefault(name: "Position X", minValue: -500, maxValue: 500, value: 0)
            self.positionY = .makeDefault(name: "Position Y", minValue: -500, maxValue: 500, value: 0)
        }
        opacity = try c.decodeIfPresent(KeyframeTrack.self, forKey: .opacity)
            ?? .makeDefault(name: "Opacity", minValue: 0, maxValue: 1, value: 1)
        rotationZ = try c.decodeIfPresent(KeyframeTrack.self, forKey: .rotationZ)
            ?? .makeDefault(name: "Rotation Z", minValue: -360, maxValue: 360, value: 0)
        rotationY = try c.decodeIfPresent(KeyframeTrack.self, forKey: .rotationY)
            ?? .makeDefault(name: "Rotation Y", minValue: -85, maxValue: 85, value: 0)
        rotationX = try c.decodeIfPresent(KeyframeTrack.self, forKey: .rotationX)
            ?? .makeDefault(name: "Rotation X", minValue: -85, maxValue: 85, value: 0)
        blur = try c.decodeIfPresent(KeyframeTrack.self, forKey: .blur)
            ?? .makeDefault(name: "Blur", minValue: 0, maxValue: 200, value: 0)
        enabledProperties = try c.decodeIfPresent(EnabledProperties.self, forKey: .enabledProperties) ?? EnabledProperties()
        timeDomain = try c.decodeIfPresent(TrackTimeDomain.self, forKey: .timeDomain)
        // 초기 개발본의 ±10000 범위는 실제 편집에 지나치게 넓었다.
        // 기존 프로젝트도 로드 즉시 같은 ±500 가상 단위 범위로 정리한다.
        positionX = Self.normalizedPositionTrack(positionX, name: "Position X")
        positionY = Self.normalizedPositionTrack(positionY, name: "Position Y")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scale, forKey: .scale)
        try c.encode(positionX, forKey: .positionX)
        try c.encode(positionY, forKey: .positionY)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(rotationZ, forKey: .rotationZ)
        try c.encode(rotationY, forKey: .rotationY)
        try c.encode(rotationX, forKey: .rotationX)
        try c.encode(blur, forKey: .blur)
        try c.encode(enabledProperties, forKey: .enabledProperties)
        try c.encodeIfPresent(timeDomain, forKey: .timeDomain)
    }

    static func decoded(from data: Data?) -> TrackSet {
        guard let data, !data.isEmpty,
              let set = try? JSONDecoder().decode(TrackSet.self, from: data) else { return .makeDefault() }
        return set
    }

    private static func normalizedPositionTrack(_ source: KeyframeTrack, name: String) -> KeyframeTrack {
        var track = source
        track.name = name
        track.minValue = -500
        track.maxValue = 500
        track.keyframes.indices.forEach { index in
            track.keyframes[index].value = min(max(track.keyframes[index].value, -500), 500)
        }
        return track
    }
}

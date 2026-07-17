import SwiftUI
import FxPlug
import AppKit

private enum TrackAxis: Hashable, CaseIterable {
    case scale
    case positionX
    case positionY
    case opacity
    case rotationZ
    case rotationY
    case rotationX
    case blur
}

/// 평상시에는 한 축만 선택하고, Command 클릭일 때만 X/Y 한 점씩 함께 선택한다.
private struct KeyframeReference: Hashable {
    var axis: TrackAxis
    var id: UUID
}

private struct KeyframeSelection {
    var ids: Set<KeyframeReference> = []

    mutating func select(_ id: UUID, on axis: TrackAxis, additive: Bool) {
        if !additive { ids.removeAll() }
        ids.insert(KeyframeReference(axis: axis, id: id))
    }

    mutating func remove(_ id: UUID, on axis: TrackAxis) {
        ids.remove(KeyframeReference(axis: axis, id: id))
    }

    func ids(on axis: TrackAxis) -> Set<UUID> {
        Set(ids.filter { $0.axis == axis }.map(\.id))
    }
}

/// 인스펙터 안에 들어가는 그래프 에디터.
/// Scale X / Scale Y 트랙을 각각 하나의 그래프로 보여준다.
/// 확대 = 두 그래프의 같은 지점을 함께 올리는 것.
struct KeyframeToolboxView: View {

    // 플러그인은 이 뷰를 호스팅하는 NSHostingView를 강하게 들고 있다.
    // 여기서 다시 강하게 잡으면 순환 참조가 되므로 weak로 둔다.
    weak var plugin: KeyframeToolboxPlugin?

    @State private var tracks: TrackSet = .makeDefault()
    @State private var loaded = false
    @State private var selection = KeyframeSelection()
    @State private var playbackTime: Double?
    @State private var hoverTime: Double?
    @State private var showsSettings = false
    @State private var pendingProperties = EnabledProperties()

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("키프레임 그래프")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button("⚙ 설정") {
                            pendingProperties = tracks.enabledProperties
                            showsSettings = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .popover(isPresented: $showsSettings, arrowEdge: .top) {
                            settingsPopover
                        }
                    }

                    if tracks.enabledProperties.scale {
                        editor($tracks.scale, axis: .scale, accent: .cyan, displaysPercentage: true)
                    }
                    if tracks.enabledProperties.positionX {
                        editor($tracks.positionX, axis: .positionX, accent: .green, displaysPercentage: false)
                    }
                    if tracks.enabledProperties.positionY {
                        editor($tracks.positionY, axis: .positionY, accent: .orange, displaysPercentage: false)
                    }
                    if tracks.enabledProperties.opacity {
                        editor($tracks.opacity, axis: .opacity, accent: .white, displaysPercentage: true)
                    }
                    if tracks.enabledProperties.rotationZ {
                        editor($tracks.rotationZ, axis: .rotationZ, accent: .pink, displaysPercentage: false)
                    }
                    if tracks.enabledProperties.rotationY {
                        editor($tracks.rotationY, axis: .rotationY, accent: .purple, displaysPercentage: false)
                    }
                    if tracks.enabledProperties.rotationX {
                        editor($tracks.rotationX, axis: .rotationX, accent: .yellow, displaysPercentage: false)
                    }
                    if tracks.enabledProperties.blur {
                        editor($tracks.blur, axis: .blur, accent: .mint, displaysPercentage: false)
                    }

                    Text("선 위 클릭: 키프레임 추가 · 빈 곳 클릭: 시간 이동 · ⌘ 클릭: 다중 선택")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                .padding(10)
                // ScrollView 안의 콘텐츠는 가로축에서 본래 크기를 요구할 수 있다.
                // 최종 폭을 호스트 인스펙터 폭으로 제한해 오른쪽 축이 잘리지 않게 한다.
                .frame(width: proxy.size.width, alignment: .leading)
            }
        }
        .background(Color(red: 0.15, green: 0.15, blue: 0.15))
        // 인스펙터의 폭보다 큰 최소 폭을 강제하지 않는다.
        .frame(maxWidth: .infinity, minHeight: 640)
        .onAppear {
            kfUITrace("swiftui onAppear enter loaded=\(loaded)")
            // onAppear는 여러 번 불릴 수 있다. 편집 중인 내용을 덮어쓰지 않도록 최초 1회만 읽는다.
            guard !loaded else { return }
            loaded = true
            if let plugin { tracks = plugin.loadTracksForCustomView() }
            kfUITrace("swiftui onAppear complete")
        }
        // FCP의 Undo/Redo로 숨겨진 Tracks 파라미터가 바뀌면 그래프도 즉시 같은 값으로 복원한다.
        .onReceive(NotificationCenter.default.publisher(for: KeyframeToolboxPlugin.tracksDidChangeNotification,
                                                        object: plugin)) { _ in
            kfUITrace("swiftui notification enter")
            guard loaded, let plugin else { return }
            tracks = plugin.loadTracksForCustomView()
            kfUITrace("swiftui notification complete")
        }
        .onReceive(NotificationCenter.default.publisher(for: KeyframeToolboxPlugin.playheadDidChangeNotification,
                                                        object: plugin)) { note in
            if let time = note.userInfo?["time"] as? Double { playbackTime = time }
        }
    }

    private func commit() {
        plugin?.saveTracks(tracks)
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("표시할 속성")
                .font(.headline)
            Toggle("Opacity", isOn: $pendingProperties.opacity)
            Toggle("Position X", isOn: $pendingProperties.positionX)
            Toggle("Position Y", isOn: $pendingProperties.positionY)
            Toggle("Scale", isOn: $pendingProperties.scale)
            Toggle("Rotation Z", isOn: $pendingProperties.rotationZ)
            Toggle("Rotation Y", isOn: $pendingProperties.rotationY)
            Toggle("Rotation X", isOn: $pendingProperties.rotationX)
            Toggle("Blur", isOn: $pendingProperties.blur)
            Divider()
            HStack {
                Spacer()
                Button("취소") { showsSettings = false }
                Button("Save") {
                    tracks.enabledProperties = pendingProperties
                    selection.ids.removeAll()
                    commit()
                    showsSettings = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
        .frame(width: 230)
    }

    private func editor(_ track: Binding<KeyframeTrack>, axis: TrackAxis, accent: Color, displaysPercentage: Bool) -> some View {
        TrackEditor(track: track,
                    accent: accent,
                    snapTargets: allKeyframes(except: axis),
                    displaysPercentage: displaysPercentage,
                    scrubberTime: hoverTime ?? playbackTime,
                    selectedKeyframeIDs: selection.ids(on: axis),
                    selectionCount: selection.ids.count,
                    onCommit: { commit() },
                    onSelectionChange: { id, additive in selection.select(id, on: axis, additive: additive) },
                    onSelectionRemove: { id in selection.remove(id, on: axis) },
                    onDeleteKeyframe: { id in deleteKeyframe(id: id, on: axis) },
                    onSyncValueChange: { id, value in syncValue(of: id, on: axis, to: value) },
                    onSyncHandleChange: { id, keyframe in syncHandles(of: id, on: axis, from: keyframe) },
                    onSynchronizeSelection: { synchronizeSelection() },
                    onUnsynchronize: { id in unsynchronize(id: id, on: axis) },
                    onHoverTimeChange: { hoverTime = $0 },
                    onBlankTap: { time in
                        playbackTime = time
                        plugin?.movePlayhead(toNormalizedTime: time)
                    },
                    onSelectKeyframe: { time in
                        playbackTime = time
                        plugin?.movePlayhead(toNormalizedTime: time)
                    })
    }

    private func allKeyframes(except axis: TrackAxis) -> [Keyframe] {
        TrackAxis.allCases.filter { $0 != axis }.flatMap { track(for: $0).keyframes }
    }

    private func track(for axis: TrackAxis) -> KeyframeTrack {
        switch axis {
        case .scale: tracks.scale
        case .positionX: tracks.positionX
        case .positionY: tracks.positionY
        case .opacity: tracks.opacity
        case .rotationZ: tracks.rotationZ
        case .rotationY: tracks.rotationY
        case .rotationX: tracks.rotationX
        case .blur: tracks.blur
        }
    }

    private func modifyTrack(_ axis: TrackAxis, _ body: (inout KeyframeTrack) -> Void) {
        switch axis {
        case .scale: body(&tracks.scale)
        case .positionX: body(&tracks.positionX)
        case .positionY: body(&tracks.positionY)
        case .opacity: body(&tracks.opacity)
        case .rotationZ: body(&tracks.rotationZ)
        case .rotationY: body(&tracks.rotationY)
        case .rotationX: body(&tracks.rotationX)
        case .blur: body(&tracks.blur)
        }
    }

    private func synchronizeSelection() {
        guard selection.ids.count >= 2 else { return }
        let group = UUID()
        for reference in selection.ids {
            modifyTrack(reference.axis) { track in
                if let index = track.keyframes.firstIndex(where: { $0.id == reference.id }) { track.keyframes[index].syncGroupID = group }
            }
        }
        commit()
    }

    private func unsynchronize(id: UUID, on axis: TrackAxis) {
        let source = track(for: axis)
        guard let group = source.keyframes.first(where: { $0.id == id })?.syncGroupID else { return }
        TrackAxis.allCases.forEach { axis in modifyTrack(axis) { track in track.keyframes.indices.forEach { if track.keyframes[$0].syncGroupID == group { track.keyframes[$0].syncGroupID = nil } } } }
        commit()
    }

    /// 동기화된 점은 X/Y 중 한쪽만 지우면 다른 축에 고아 점이 남아 곡선이 어긋난다.
    /// 그래서 동기화 그룹 삭제는 항상 원자적으로, 그룹 전체에 적용한다.
    private func deleteKeyframe(id: UUID, on axis: TrackAxis) {
        let source = track(for: axis)
        guard let keyframe = source.keyframes.first(where: { $0.id == id }) else { return }

        if let group = keyframe.syncGroupID {
            let members = TrackAxis.allCases.flatMap { candidateAxis in
                track(for: candidateAxis).keyframes
                    .filter { $0.syncGroupID == group }
                    .map { KeyframeReference(axis: candidateAxis, id: $0.id) }
            }
            // 시작/끝점은 트랙의 시간 범위를 유지해야 하므로 그룹 전체 삭제도 막는다.
            guard !members.contains(where: { isBoundaryKeyframe($0.id, on: $0.axis) }) else { return }
            for member in members {
                modifyTrack(member.axis) { $0.keyframes.removeAll { $0.id == member.id } }
                selection.remove(member.id, on: member.axis)
            }
        } else {
            guard !isBoundaryKeyframe(id, on: axis) else { return }
            modifyTrack(axis) { $0.keyframes.removeAll { $0.id == id } }
            selection.remove(id, on: axis)
        }
        commit()
    }

    private func isBoundaryKeyframe(_ id: UUID, on axis: TrackAxis) -> Bool {
        let sorted = track(for: axis).keyframes.sorted { $0.time < $1.time }
        return sorted.first?.id == id || sorted.last?.id == id
    }

    private func syncValue(of id: UUID, on axis: TrackAxis, to value: Double) {
        let source = track(for: axis)
        guard let group = source.keyframes.first(where: { $0.id == id })?.syncGroupID else { return }
        TrackAxis.allCases.forEach { axis in modifyTrack(axis) { track in track.keyframes.indices.forEach { if track.keyframes[$0].syncGroupID == group { track.keyframes[$0].value = value } } } }
    }

    /// 동기화 그룹은 점의 값뿐 아니라 베지에 입·출력 핸들 모양도 공유한다.
    /// id/time/value/syncGroupID는 각 점의 고유 정보이므로 건드리지 않는다.
    private func syncHandles(of id: UUID, on axis: TrackAxis, from sourceKeyframe: Keyframe) {
        let source = track(for: axis)
        guard let group = source.keyframes.first(where: { $0.id == id })?.syncGroupID else { return }
        TrackAxis.allCases.forEach { targetAxis in
            modifyTrack(targetAxis) { track in
                for index in track.keyframes.indices where track.keyframes[index].syncGroupID == group {
                    track.keyframes[index].inHandleTime = sourceKeyframe.inHandleTime
                    track.keyframes[index].inHandleValue = sourceKeyframe.inHandleValue
                    track.keyframes[index].outHandleTime = sourceKeyframe.outHandleTime
                    track.keyframes[index].outHandleValue = sourceKeyframe.outHandleValue
                    track.keyframes[index].outgoingInterpolation = sourceKeyframe.outgoingInterpolation
                }
            }
        }
    }
}

/// 트랙 하나를 그리고 편집하는 그래프.
private struct TrackEditor: View {
    @Binding var track: KeyframeTrack
    var accent: Color
    /// 반대 축의 키프레임. 시간과 값이 가까워지면 같은 좌표로 스냅한다.
    var snapTargets: [Keyframe]
    var displaysPercentage: Bool
    /// 세 그래프가 동일하게 표시할 마우스/재생 위치.
    var scrubberTime: Double?
    var selectedKeyframeIDs: Set<UUID>
    var selectionCount: Int
    var onCommit: () -> Void
    var onSelectionChange: (UUID, Bool) -> Void
    var onSelectionRemove: (UUID) -> Void
    var onDeleteKeyframe: (UUID) -> Void
    var onSyncValueChange: (UUID, Double) -> Void
    /// 동기화된 점의 베지에 핸들 모양을 함께 갱신한다.
    var onSyncHandleChange: (UUID, Keyframe) -> Void
    var onSynchronizeSelection: () -> Void
    var onUnsynchronize: (UUID) -> Void
    var onHoverTimeChange: (Double?) -> Void
    /// 곡선 밖 빈 공간을 클릭했을 때 그 가로축 시간으로 스키머를 옮긴다.
    var onBlankTap: (Double) -> Void
    /// 기존 키프레임을 클릭만 했을 때 FCP 재생 헤드를 그 위치로 이동한다.
    var onSelectKeyframe: (Double) -> Void

    @State private var dragging: UUID?
    @State private var didMoveKeyframe = false
    @State private var createdKeyframeInGesture = false
    @State private var beganGraphGesture = false
    @State private var blankTapTime: Double?
    private var activeSelectedKeyframeID: UUID? {
        selectedKeyframeIDs.count == 1 ? selectedKeyframeIDs.first : nil
    }

    private let graphHeight: CGFloat = 150
    private static let percentageFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.minimum = 0
        formatter.maximum = 400
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(track.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text(rangeText)
                    .font(.system(size: 9).monospaced())
                    .foregroundColor(.gray)
            }

            HStack(spacing: 6) {
                GeometryReader { geo in
                    let size = geo.size
                    ZStack {
                        grid(size: size)
                        curve(size: size)
                        bezierHandles(size: size)
                        handles(size: size)
                        scrubber(size: size)
                    }
                    .contentShape(Rectangle())
                    .gesture(dragGesture(size: size))
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let point):
                            guard size.width > 0 else { return }
                            onHoverTimeChange(min(max(Double(point.x / size.width), 0), 1))
                        case .ended:
                            onHoverTimeChange(nil)
                        }
                    }
                }
                .frame(height: graphHeight)
                // 우측 축이 필요한 폭을 먼저 확보하고 그래프가 남는 폭을 사용한다.
                .layoutPriority(0)

                yAxisControls
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.25))
            .cornerRadius(4)
        }
    }

    // MARK: - 좌표 변환 (트랙 값 <-> 화면 픽셀)

    private func point(_ kf: Keyframe, _ size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(kf.time) * size.width,
                y: valueToY(kf.value, size))
    }

    private func valueToY(_ value: Double, _ size: CGSize) -> CGFloat {
        let range = displayRange
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return size.height }
        let ratio = (value - range.lowerBound) / span
        // 화면은 위가 0이라 뒤집는다.
        return size.height * CGFloat(1.0 - ratio)
    }

    private func yToValue(_ y: CGFloat, _ size: CGSize) -> Double {
        guard size.height > 0 else { return track.minValue }
        let range = displayRange
        let ratio = 1.0 - Double(y / size.height)
        return min(max(range.lowerBound + ratio * (range.upperBound - range.lowerBound),
                       track.minValue), track.maxValue)
    }

    /// 키프레임 값 주변만 확대해서 보여준다. 값 차이가 작으면 더 좁은 범위를 쓰므로
    /// 작은 변화도 세밀하게 조절할 수 있고, 값 차이가 커지면 자동으로 범위가 넓어진다.
    private var displayRange: ClosedRange<Double> {
        let values = track.keyframes.map(\.value)
        guard let low = values.min(), let high = values.max() else {
            return track.minValue...track.maxValue
        }

        let span = max(high - low, 0.1)
        let padding = max(span * 0.2, 0.05)
        var lower = max(track.minValue, low - padding)
        var upper = min(track.maxValue, high + padding)

        // 값이 동일한 기본 상태에서도 5% 단위 조절이 가능하도록 최소 시야를 확보한다.
        let minimumVisibleSpan = 0.2
        if upper - lower < minimumVisibleSpan {
            let center = (low + high) / 2
            lower = max(track.minValue, center - minimumVisibleSpan / 2)
            upper = min(track.maxValue, center + minimumVisibleSpan / 2)
            if upper - lower < minimumVisibleSpan {
                lower = max(track.minValue, upper - minimumVisibleSpan)
                upper = min(track.maxValue, lower + minimumVisibleSpan)
            }
        }
        return lower...upper
    }

    // MARK: - 그리기

    @ViewBuilder
    private func scrubber(size: CGSize) -> some View {
        if let scrubberTime {
            Path { path in
                let x = CGFloat(min(max(scrubberTime, 0), 1)) * size.width
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            .stroke(Color.white.opacity(0.92), lineWidth: 1)
            .allowsHitTesting(false)
        }
    }

    private func grid(size: CGSize) -> some View {
        Canvas { ctx, _ in
            var path = Path()
            for i in 0...4 {
                let y = size.height * CGFloat(i) / 4.0
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for i in 0...8 {
                let x = size.width * CGFloat(i) / 8.0
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            ctx.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)

            // 100% 기준선 — 현재 보이는 범위 안에 있을 때만 표시한다.
            if displayRange.contains(1.0) {
                var base = Path()
                let y = valueToY(1.0, size)
                base.move(to: CGPoint(x: 0, y: y))
                base.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(base, with: .color(.white.opacity(0.28)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
    }

    private func curve(size: CGSize) -> some View {
        Path { path in
            let sorted = track.keyframes.sorted { $0.time < $1.time }
            guard sorted.count >= 2 else { return }
            // 트랙 평가 결과를 그대로 따라 그린다 — 렌더와 화면이 어긋나지 않게.
            let steps = max(Int(size.width), 2)
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                let p = CGPoint(x: CGFloat(t) * size.width,
                                y: valueToY(track.evaluate(at: t), size))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func handles(size: CGSize) -> some View {
        ForEach(track.keyframes) { kf in
            let isBoundary = isBoundaryKeyframe(kf.id)
            let isSelected = selectedKeyframeIDs.contains(kf.id)
            let pointColor = kf.syncGroupID == nil ? accent : .purple
            ZStack {
                Circle()
                    .fill(isBoundary ? Color.clear : (dragging == kf.id ? Color.white : pointColor))
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle().stroke(isSelected ? Color.white : pointColor,
                                        lineWidth: isBoundary ? 2 : 1)
                    )
                    .contextMenu {
                        if selectedKeyframeIDs.contains(kf.id), selectionCount >= 2 {
                            Button("동기화 하기") { onSynchronizeSelection() }
                        }
                        if kf.syncGroupID != nil {
                            Button("동기화 해제") { onUnsynchronize(kf.id) }
                        }
                        if selectedKeyframeIDs.contains(kf.id), selectionCount >= 2 || kf.syncGroupID != nil {
                            Divider()
                        }
                        Menu("보간 방식") {
                            ForEach(InterpolationMode.allCases, id: \.self) { mode in
                                Button {
                                    setOutgoingInterpolation(mode, for: kf.id)
                                } label: {
                                    if outgoingInterpolation(for: kf.id) == mode {
                                        Label(mode.title, systemImage: "checkmark")
                                    } else {
                                        Text(mode.title)
                                    }
                                }
                                .disabled(isBoundary && sortedIndex(for: kf.id) == track.keyframes.count - 1)
                            }
                        }

                        Divider()
                        if !isBoundary {
                            Button("키프레임 삭제", role: .destructive) {
                                deleteKeyframe(id: kf.id)
                            }
                        }
                    }

            }
            .frame(width: 18, height: 18)
            .position(point(kf, size))
        }
    }

    // MARK: - 베지에 핸들

    /// 선택한 키프레임의 입·출력 핸들만 표시한다.
    /// 핸들 값이 0인 선형 상태에서는 드래그를 시작할 수 있도록 점에서 살짝 떨어진
    /// 점선 가이드 핸들을 보여준다. 실제 모델 값은 드래그 전까지 0으로 유지된다.
    @ViewBuilder
    private func bezierHandles(size: CGSize) -> some View {
        if let id = activeSelectedKeyframeID,
           let index = track.keyframes.firstIndex(where: { $0.id == id }) {
            let sorted = track.keyframes.sorted { $0.time < $1.time }
            if let sortedIndex = sorted.firstIndex(where: { $0.id == id }) {
                let keyframe = track.keyframes[index]
                let keyframePoint = point(keyframe, size)

                if sortedIndex > 0 {
                    bezierHandle(kind: .incoming,
                                 keyframe: keyframe,
                                 anchor: keyframePoint,
                                 size: size)
                }
                if sortedIndex < sorted.count - 1 {
                    bezierHandle(kind: .outgoing,
                                 keyframe: keyframe,
                                 anchor: keyframePoint,
                                 size: size)
                }
            }
        }
    }

    private enum BezierHandleKind {
        case incoming
        case outgoing
    }

    private func bezierHandle(kind: BezierHandleKind,
                              keyframe: Keyframe,
                              anchor: CGPoint,
                              size: CGSize) -> some View {
        let handle = handlePoint(for: keyframe, kind: kind, size: size)
        let isDormant = isDormantHandle(keyframe, kind: kind)

        return ZStack {
            Path { path in
                path.move(to: anchor)
                path.addLine(to: handle)
            }
            .stroke(accent.opacity(0.65),
                    style: StrokeStyle(lineWidth: 1, dash: isDormant ? [3, 3] : []))

            Circle()
                .fill(Color.black.opacity(0.7))
                .overlay(Circle().stroke(accent, lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .position(handle)
                .gesture(bezierHandleDrag(kind: kind,
                                           keyframeID: keyframe.id,
                                           size: size))
                .contextMenu {
                    Button("핸들 초기화") {
                        resetBezierHandle(kind: kind, keyframeID: keyframe.id)
                    }
                }

        }
    }

    private func isDormantHandle(_ keyframe: Keyframe, kind: BezierHandleKind) -> Bool {
        switch kind {
        case .incoming:
            return keyframe.inHandleTime == 0 && keyframe.inHandleValue == 0
        case .outgoing:
            return keyframe.outHandleTime == 0 && keyframe.outHandleValue == 0
        }
    }

    private func handlePoint(for keyframe: Keyframe,
                             kind: BezierHandleKind,
                             size: CGSize) -> CGPoint {
        let dormant = isDormantHandle(keyframe, kind: kind)
        if dormant {
            // 선형 상태에서도 핸들을 잡을 수 있는 시각적 손잡이.
            let direction: CGFloat = kind == .incoming ? -1 : 1
            return CGPoint(x: CGFloat(keyframe.time) * size.width + direction * 26,
                           y: valueToY(keyframe.value, size))
        }

        let timeOffset: Double
        let valueOffset: Double
        switch kind {
        case .incoming:
            timeOffset = keyframe.inHandleTime
            valueOffset = keyframe.inHandleValue
        case .outgoing:
            timeOffset = keyframe.outHandleTime
            valueOffset = keyframe.outHandleValue
        }
        return CGPoint(x: CGFloat(keyframe.time + timeOffset) * size.width,
                       y: valueToY(keyframe.value + valueOffset, size))
    }

    private func bezierHandleDrag(kind: BezierHandleKind,
                                  keyframeID: UUID,
                                  size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                updateBezierHandle(kind: kind,
                                   keyframeID: keyframeID,
                                   location: gesture.location,
                                   size: size)
            }
            .onEnded { _ in onCommit() }
    }

    private func updateBezierHandle(kind: BezierHandleKind,
                                    keyframeID: UUID,
                                    location: CGPoint,
                                    size: CGSize) {
        guard let index = track.keyframes.firstIndex(where: { $0.id == keyframeID }) else { return }
        let sorted = track.keyframes.sorted { $0.time < $1.time }
        guard let sortedIndex = sorted.firstIndex(where: { $0.id == keyframeID }) else { return }

        let keyframe = track.keyframes[index]
        let rawTime = min(max(Double(location.x / size.width), 0), 1)
        let rawValue = yToValue(location.y, size)
        let previousModelIndex = sortedIndex > 0
            ? track.keyframes.firstIndex(where: { $0.id == sorted[sortedIndex - 1].id })
            : nil
        let isContinuous = track.keyframes[index].outgoingInterpolation == .continuousBezier ||
            previousModelIndex.map { track.keyframes[$0].outgoingInterpolation == .continuousBezier } == true

        switch kind {
        case .incoming:
            // P2는 이전 키프레임의 오른쪽과 현재 키프레임 사이에 있어야 x(u)가 단조롭다.
            let previousTime = sorted[sortedIndex - 1].time
            let handleTime = min(max(rawTime, previousTime), keyframe.time)
            track.keyframes[index].inHandleTime = handleTime - keyframe.time
            track.keyframes[index].inHandleValue = rawValue - keyframe.value
            if !isContinuous, let previousModelIndex { track.keyframes[previousModelIndex].outgoingInterpolation = .bezier }
            if isContinuous, sortedIndex < sorted.count - 1 {
                let nextTime = sorted[sortedIndex + 1].time
                track.keyframes[index].outHandleTime = min(-track.keyframes[index].inHandleTime, nextTime - keyframe.time)
                track.keyframes[index].outHandleValue = -track.keyframes[index].inHandleValue
            }
        case .outgoing:
            // P1은 현재 키프레임과 다음 키프레임 사이에 제한한다.
            let nextTime = sorted[sortedIndex + 1].time
            let handleTime = min(max(rawTime, keyframe.time), nextTime)
            track.keyframes[index].outHandleTime = handleTime - keyframe.time
            track.keyframes[index].outHandleValue = rawValue - keyframe.value
            if !isContinuous { track.keyframes[index].outgoingInterpolation = .bezier }
            if isContinuous, sortedIndex > 0 {
                let previousTime = sorted[sortedIndex - 1].time
                track.keyframes[index].inHandleTime = max(-track.keyframes[index].outHandleTime, previousTime - keyframe.time)
                track.keyframes[index].inHandleValue = -track.keyframes[index].outHandleValue
            }
        }
        // 연속 베지어의 반대편 핸들까지 계산된 뒤 전체 모양을 동기화한다.
        onSyncHandleChange(keyframeID, track.keyframes[index])
    }

    private func resetBezierHandle(kind: BezierHandleKind, keyframeID: UUID) {
        guard let index = track.keyframes.firstIndex(where: { $0.id == keyframeID }) else { return }
        switch kind {
        case .incoming:
            track.keyframes[index].inHandleTime = 0
            track.keyframes[index].inHandleValue = 0
        case .outgoing:
            track.keyframes[index].outHandleTime = 0
            track.keyframes[index].outHandleValue = 0
        }
        onSyncHandleChange(keyframeID, track.keyframes[index])
        onCommit()
    }

    private func sortedIndex(for id: UUID) -> Int? {
        track.keyframes.sorted { $0.time < $1.time }.firstIndex(where: { $0.id == id })
    }

    private func outgoingInterpolation(for id: UUID) -> InterpolationMode {
        track.keyframes.first(where: { $0.id == id })?.outgoingInterpolation ?? .linear
    }

    /// 메뉴의 보간 방식은 해당 키프레임에서 오른쪽(다음 키프레임)으로 가는 구간에 적용한다.
    private func setOutgoingInterpolation(_ mode: InterpolationMode, for id: UUID) {
        let sorted = track.keyframes.sorted { $0.time < $1.time }
        guard let position = sorted.firstIndex(where: { $0.id == id }), position < sorted.count - 1,
              let startIndex = track.keyframes.firstIndex(where: { $0.id == id }),
              let endIndex = track.keyframes.firstIndex(where: { $0.id == sorted[position + 1].id }) else { return }

        track.keyframes[startIndex].outgoingInterpolation = mode
        let span = track.keyframes[endIndex].time - track.keyframes[startIndex].time
        let delta = track.keyframes[endIndex].value - track.keyframes[startIndex].value

        switch mode {
        case .linear, .hold:
            track.keyframes[startIndex].outHandleTime = 0
            track.keyframes[startIndex].outHandleValue = 0
            track.keyframes[endIndex].inHandleTime = 0
            track.keyframes[endIndex].inHandleValue = 0
        case .bezier, .continuousBezier:
            // 처음 베지어로 바꿀 때는 직선 모양의 제어점을 배치한다.
            if track.keyframes[startIndex].outHandleTime == 0 && track.keyframes[startIndex].outHandleValue == 0 &&
                track.keyframes[endIndex].inHandleTime == 0 && track.keyframes[endIndex].inHandleValue == 0 {
                track.keyframes[startIndex].outHandleTime = span / 3
                track.keyframes[startIndex].outHandleValue = delta / 3
                track.keyframes[endIndex].inHandleTime = -span / 3
                track.keyframes[endIndex].inHandleValue = -delta / 3
            }
        case .autoBezier, .easeIn, .easeOut, .easeInOut:
            break
        }
        onCommit()
    }

    // MARK: - 편집

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                if !beganGraphGesture {
                    beganGraphGesture = true
                    dragging = nearestKeyframe(to: g.startLocation, size: size)
                    didMoveKeyframe = false
                    createdKeyframeInGesture = false
                    blankTapTime = nil
                    // 빈 곳은 편집하지 않는다. 실제 곡선 위에서만 새 키프레임을 만든다.
                    if dragging == nil {
                        guard isNearCurve(g.startLocation, size: size) else {
                            blankTapTime = min(max(Double(g.startLocation.x / size.width), 0), 1)
                            return
                        }
                        let kf = Keyframe(time: min(max(Double(g.startLocation.x / size.width), 0), 1),
                                          value: yToValue(g.startLocation.y, size))
                        track.keyframes.append(kf)
                        dragging = kf.id
                        createdKeyframeInGesture = true
                    }
                    if let id = dragging {
                        // 이미 선택된 점을 다시 드래그하면 다중 선택을 유지한다.
                        if !selectedKeyframeIDs.contains(id) {
                            // macOS의 Control+클릭은 우클릭 메뉴와 같으므로 묶음 선택은 Command를 쓴다.
                            onSelectionChange(id, NSEvent.modifierFlags.contains(.command))
                        }
                    }
                }
                guard let id = dragging,
                      let idx = track.keyframes.firstIndex(where: { $0.id == id }) else { return }

                // 단순 클릭에도 DragGesture의 좌표가 1~2px 흔들릴 수 있다.
                // 기존 키프레임은 3px 이상 움직였을 때만 실제 값을 바꾼다.
                let distance = hypot(g.location.x - g.startLocation.x,
                                     g.location.y - g.startLocation.y)
                guard distance >= 3 else { return }
                didMoveKeyframe = true

                let sorted = track.keyframes.sorted { $0.time < $1.time }
                let isFirst = sorted.first?.id == id
                let isLast = sorted.last?.id == id

                // 첫/끝 키프레임은 값만 바꾸고 시간은 고정해 트랙이 항상 클립 전체를 덮게 한다.
                var time = min(max(Double(g.location.x / size.width), 0), 1)
                var value = yToValue(g.location.y, size)
                let snapped = magneticSnap(time: time, value: value, size: size)
                time = snapped.time
                value = snapped.value

                if !isFirst && !isLast { track.keyframes[idx].time = time }
                track.keyframes[idx].value = value
                onSyncValueChange(id, value)
            }
            .onEnded { _ in
                let shouldCommit = didMoveKeyframe || createdKeyframeInGesture
                let navigationTime = blankTapTime
                let selectedTime = dragging.flatMap { id in
                    track.keyframes.first(where: { $0.id == id })?.time
                }
                dragging = nil
                track.keyframes.sort { $0.time < $1.time }
                didMoveKeyframe = false
                createdKeyframeInGesture = false
                beganGraphGesture = false
                blankTapTime = nil
                if shouldCommit { onCommit() }
                // 새 키프레임 추가/드래그는 편집 동작이다. 움직이지 않은 기존 점만 이동한다.
                if !shouldCommit, let selectedTime { onSelectKeyframe(selectedTime) }
                if !shouldCommit, selectedTime == nil, let navigationTime { onBlankTap(navigationTime) }
            }
    }

    private func nearestKeyframe(to location: CGPoint, size: CGSize) -> UUID? {
        var best: (UUID, CGFloat)?
        for kf in track.keyframes {
            let p = point(kf, size)
            let d = hypot(p.x - location.x, p.y - location.y)
            if d < 12, best == nil || d < best!.1 { best = (kf.id, d) }
        }
        return best?.0
    }

    /// 곡선의 화면 좌표와 가까울 때만 키프레임 추가를 허용한다.
    private func isNearCurve(_ location: CGPoint, size: CGSize) -> Bool {
        guard size.width > 0 else { return false }
        let time = min(max(Double(location.x / size.width), 0), 1)
        let curveY = valueToY(track.evaluate(at: time), size)
        return abs(location.y - curveY) <= 10
    }

    private func isBoundaryKeyframe(_ id: UUID) -> Bool {
        let sorted = track.keyframes.sorted { $0.time < $1.time }
        return sorted.first?.id == id || sorted.last?.id == id
    }

    private func deleteKeyframe(id: UUID) {
        // 메뉴의 활성화 상태는 FCP가 호스팅한 SwiftUI 뷰에서 신뢰하지 않는다.
        // 시작·끝 보호는 실제 변경 직전에만 적용한다.
        guard !isBoundaryKeyframe(id) else { return }
        onDeleteKeyframe(id)
    }

    /// 다른 축의 가까운 키프레임에 시간·값을 함께 맞춘다.
    /// 두 축이 같은 배율을 유지하기 쉬워져 비율을 찌그러뜨리지 않는 확대가 가능하다.
    private func magneticSnap(time: Double, value: Double, size: CGSize) -> (time: Double, value: Double) {
        guard !snapTargets.isEmpty else { return (time, value) }
        let timeThreshold = max(12.0 / Double(max(size.width, 1)), 0.015)
        let valueThreshold = (displayRange.upperBound - displayRange.lowerBound) * 0.07

        var snappedTime = time
        var snappedValue = value
        if let target = snapTargets.min(by: { abs($0.time - time) < abs($1.time - time) }),
           abs(target.time - time) <= timeThreshold {
            snappedTime = target.time
        }
        if let target = snapTargets.min(by: { abs($0.value - value) < abs($1.value - value) }),
           abs(target.value - value) <= valueThreshold {
            snappedValue = target.value
        }
        return (snappedTime, snappedValue)
    }

    private var yAxisControls: some View {
        let range = displayRange
        return VStack(spacing: 4) {
            Text(valueText(range.upperBound))
            TextField(displaysPercentage ? "%" : "가상", value: selectedDisplayValueBinding, formatter: Self.percentageFormatter)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .disabled(activeSelectedKeyframeID == nil)
            Spacer(minLength: 0)
            Text(valueText((range.lowerBound + range.upperBound) / 2))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            Text(valueText(range.lowerBound))
        }
        .font(.system(size: 9, design: .monospaced))
        .foregroundColor(.gray)
        .frame(width: 52, height: graphHeight)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private var rangeText: String {
        displaysPercentage
            ? String(format: "%.0f%% ~ %.0f%%", track.minValue * 100, track.maxValue * 100)
            : String(format: "%.0f ~ %.0f", track.minValue, track.maxValue)
    }

    private func valueText(_ value: Double) -> String {
        displaysPercentage ? String(format: "%.0f%%", value * 100) : String(format: "%.0f", value)
    }

    private var selectedDisplayValueBinding: Binding<Double> {
        Binding(
            get: {
                guard let id = activeSelectedKeyframeID,
                      let index = track.keyframes.firstIndex(where: { $0.id == id }) else { return 0 }
                return displaysPercentage ? track.keyframes[index].value * 100 : track.keyframes[index].value
            },
            set: { displayValue in
                guard let id = activeSelectedKeyframeID,
                      let index = track.keyframes.firstIndex(where: { $0.id == id }) else { return }
                let value = displaysPercentage ? displayValue / 100 : displayValue
                track.keyframes[index].value = min(max(value,
                                                        track.minValue), track.maxValue)
                onCommit()
            }
        )
    }
}

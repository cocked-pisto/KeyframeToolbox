# Keyframe Toolbox

Final Cut Pro / Motion용 FxPlug 4 키프레임 그래프 에디터입니다.

Final Cut Pro 기본 키프레임 편집을 대체하는 그래프 기반 워크플로를 목표로 합니다. 클립의 시간 축을 기준으로 속성 값을 직접 편집하고, 보간 방식과 베지에 핸들을 제어할 수 있습니다.

## 현재 기능

- 그래프 위에서 키프레임 추가·이동·삭제
- 선형, 베지어, 연속 베지어, 자동 베지어, Hold, Ease In/Out 보간
- 베지에 핸들 편집 및 핸들 초기화
- Command 클릭 다중 선택 및 키프레임 동기화
- 동기화 그룹의 값·베지에 핸들·삭제 동작 연동
- 그래프 클릭으로 Final Cut Pro 재생 헤드 이동
- 모든 그래프에 공통으로 표시되는 흰색 재생/마우스 스키머
- 반응형 Y축, 자석 스냅, 키프레임별 수치 입력
- 컷 이후 키프레임 시간 범위 보정 및 Cmd+Z/Redo UI 동기화

## 지원 속성

설정 버튼에서 필요한 속성을 켜고 `Save`하면 그래프가 표시되고 렌더에 적용됩니다.

- Scale
- Position X / Y — 픽셀이 아닌 가상 단위입니다. `100`은 현재 캔버스 폭 또는 높이의 100% 이동입니다.
- Opacity
- Rotation Z
- Rotation Y / X — 원근 투영 방식의 3D 회전
- Blur

기본 활성 속성은 Scale, Position X, Position Y입니다.

## 요구 사항

- macOS 15 Sequoia 이상 (Intel / Apple Silicon)
- Final Cut Pro 또는 Motion
- Xcode Command Line Tools
- [FxPlug SDK](https://developer.apple.com/download/) — `/Library/Developer/SDKs/FxPlug.sdk`에 설치

## 빌드 및 설치

일반 사용자는 [INSTALL.md](INSTALL.md)를 따라 Release ZIP을 설치하면 됩니다. Xcode나 FxPlug SDK, Motion은 필요 없습니다. 래퍼 앱이 FxPlug 엔진과 Motion Publish 효과 템플릿을 함께 설치합니다.

소스에서 직접 빌드하려면:

```bash
git clone https://github.com/OWNER/KeyframeToolbox.git
cd KeyframeToolbox
bash build_fxplug.sh
```

스크립트는 `KeyframeToolboxV6.app`을 만들고 `/Applications`에 복사한 다음 PlugInKit에 등록합니다. 설치 후 Final Cut Pro를 재시작하세요.

## 프로젝트 구성

```text
FxPlug_Template/
  KeyframeToolboxExtension/  FxPlug 효과·렌더러·SwiftUI 그래프 에디터
  KeyframeToolboxWrapper/    플러그인 등록용 macOS 래퍼 앱
build_fxplug.sh              로컬 빌드·서명·등록 스크립트
```

## 개발 상태

현재는 배포 전 개발 단계입니다. 실제 Final Cut Pro 프로젝트에서 기능과 안정성을 계속 검증하고 있습니다.

# FxPlug 4.0 파이널컷 프로 플러그인 템플릿 개발 가이드

이 가이드는 작성된 Swift 코드를 사용하여 Xcode에서 파이널컷 프로(FCP) 및 Motion용 커스텀 베지에 키프레임 그래프 플러그인을 실제 구성, 빌드 및 연동하는 절차를 설명합니다.

---

## 1. FxPlug 4.0 개발 전제 조건

- **개발 환경**: macOS 및 Xcode 설치 완료
- **필수 SDK**: [Apple Developer - FxPlug SDK 다운로드](https://developer.apple.com/download/) 및 설치.
  - SDK 설치 시 `/Library/Developer/SDKs/` 경로에 FxPlug SDK 파일이 추가됩니다.

---

## 2. Xcode 프로젝트 생성 및 설정

### 2.1 프로젝트 생성
1. Xcode를 실행하고 **Create a new Xcode project**를 선택합니다.
2. **macOS > App** 템플릿을 선택하여 프로젝트를 생성합니다. (예: 프로젝트명 `KeyframeToolbox`)
   - 이 앱은 플러그인 Extension을 감싸는 **Wrapper Application**이 됩니다.

### 2.2 Extension 타깃 추가 (핵심)
1. Xcode 프로젝트 설정 창의 왼쪽 아래 `+` 버튼(Add a target)을 누릅니다.
2. **macOS > Application Extension > Xcode-provided FxPlug 4.0 Template** 또는 일반 **XPC Service**를 생성합니다.
   - 타깃 이름을 `KeyframeToolboxExtension`으로 입력합니다.
   - Language는 **Swift**로 설정합니다.

### 2.3 프레임워크 링크 설정
1. 생성한 Extension 타깃의 **Build Phases > Link Binary With Libraries**에 FxPlug SDK의 `FxPlug.framework`를 추가해 줍니다.

---

## 3. 템플릿 소스 코드 배치

제공된 `FxPlug_Template` 폴더 내의 파일들을 Xcode 프로젝트 내의 `KeyframeToolboxExtension` 그룹(폴더)에 복사하여 추가합니다.

1. **[KeyframeToolboxPlugin.swift](./KeyframeToolboxExtension/KeyframeToolboxPlugin.swift)**
   - FxTileableEffect 및 FCP 파라미터(시작/종료 시간 및 수치 슬라이더) 설정 모듈.
2. **[KeyframeToolboxView.swift](./KeyframeToolboxExtension/KeyframeToolboxView.swift)**
   - FCP 호스트 API 호출과 결합된 SwiftUI 베지에 에디터 패널.
3. **[BezierMath.swift](./KeyframeToolboxExtension/BezierMath.swift)**
   - 감속/가속 연산 뉴턴-랩슨 해법 모델 수학 모듈.

---

## 4. Info.plist 속성 및 권한 설정

Extension 타깃의 `Info.plist` 파일에 다음 키가 정확히 정의되어 있는지 확인해야 FCP가 올바르게 인식합니다.

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.FxPlug</string>
    <key>NSExtensionPrincipalClass</key>
    <string>$(PRODUCT_MODULE_NAME).KeyframeToolboxPlugin</string>
</dict>
```

- **PrincipalClass**: FCP가 Extension 진입 시 로드할 플러그인 클래스 경로입니다. Swift 모듈명인 `$(PRODUCT_MODULE_NAME).KeyframeToolboxPlugin` 형태로 매핑해 줍니다.

---

## 5. 빌드 및 파이널컷 프로 등록

FxPlug 4.0은 macOS의 **PlugInKit** 관리 프레임워크를 기반으로 자동 등록 및 로드됩니다.

1. **빌드**: Xcode 상단에서 빌드 스킴을 `KeyframeToolbox`(Wrapper App)로 선택하고 `Cmd + B` 또는 `Cmd + R`(실행)을 진행합니다.
2. **래퍼 앱 최초 구동**: Wrapper App이 성공적으로 한 번 실행되면, macOS가 백그라운드에 확장앱(.appex)의 존재를 자동으로 인식하여 시스템에 영구 등록합니다.
3. **PlugInKit 검증**: 터미널을 열고 다음 명령어를 쳐서 플러그인이 정상 등록되었는지 확인할 수 있습니다:
   ```bash
   pluginkit -m -p FxPlug
   ```
   목록 중에 `KeyframeToolboxExtension` 이름이 뜨면 정상입니다.

---

## 6. FCP에서 연동 및 테스트

1. 파이널컷 프로(FCP)를 실행합니다.
2. **Effects Browser**(우측 하단 이펙트 아이콘)를 엽니다.
3. 생성한 플러그인 카테고리에서 **키프레임 베지에 커브** 이펙트를 찾을 수 있습니다.
4. 타임라인의 비디오 클립에 드래그 앤 드롭으로 적용합니다.
5. 우측 상단 **인스펙터(Inspector)**를 확인하면, 선형 슬라이더들과 함께 **커스텀 베지에 커브 그래프 에디터** UI 패널이 렌더링된 것을 확인할 수 있습니다.
6. 드래그하여 조절 시 FCP 파라미터가 실시간 양방향으로 연동됩니다.

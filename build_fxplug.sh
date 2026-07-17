#!/bin/bash

echo "🚀 FxPlug 4.0 파이널컷 프로 플러그인 패키지 빌드 시작..."

# 1. 빌드 폴더 준비 및 구조 설계
APP_NAME="KeyframeToolboxV6.app"
EXTENSION_NAME="KeyframeToolboxExtension.pluginkit"

rm -rf "$APP_NAME"

echo "📂 앱 번들 폴더 구조 생성 중..."
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"
mkdir -p "$APP_NAME/Contents/PlugIns/$EXTENSION_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/PlugIns/$EXTENSION_NAME/Contents/Resources"

# 2. SDK 경로 및 Swift 컴파일러 환경 탐색
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)
FXPLUG_SDK="/Library/Developer/SDKs/FxPlug.sdk"

if [ ! -d "$FXPLUG_SDK" ]; then
    echo "❌ 에러: FxPlug SDK가 설치되어 있지 않습니다."
    exit 1
fi

echo "⚙️  1단계: App Extension (플러그인 로직) 컴파일..."
swiftc -sdk "$SDK_PATH" \
    -F "$FXPLUG_SDK/Library/Frameworks" \
    -I modules_map \
    -framework FxPlug -framework SwiftUI -framework AppKit \
    -Xlinker -rpath -Xlinker "/Applications/Final Cut Pro.app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "@loader_path/../Frameworks" \
    FxPlug_Template/KeyframeToolboxExtension/*.swift \
    -o "$APP_NAME/Contents/PlugIns/$EXTENSION_NAME/Contents/MacOS/KeyframeToolboxExtension"

if [ $? -ne 0 ]; then
    echo "❌ 에러: 플러그인 Extension 컴파일 실패"
    exit 1
fi

echo "⚙️  2단계: Wrapper Application (시스템 등록 래퍼 앱) 컴파일..."
swiftc -sdk "$SDK_PATH" \
    -framework SwiftUI -framework AppKit \
    -parse-as-library \
    FxPlug_Template/KeyframeToolboxWrapper/main.swift \
    -o "$APP_NAME/Contents/MacOS/KeyframeToolbox"

if [ $? -ne 0 ]; then
    echo "❌ 에러: Wrapper App 컴파일 실패"
    exit 1
fi

# 3. 설정 설정파일(Info.plist) 삽입
echo "📝 설정 정보(Info.plist) 복사..."
cp FxPlug_Template/KeyframeToolboxWrapper/Info.plist "$APP_NAME/Contents/Info.plist"
cp FxPlug_Template/KeyframeToolboxExtension/Info.plist "$APP_NAME/Contents/PlugIns/$EXTENSION_NAME/Contents/Info.plist"

# FCP는 displayName/infoString을 "Table::Key" 형식의 로컬라이징 키로 해석한다.
# 애플 FxPlug 4 템플릿과 동일하게 en.lproj를 번들 Resources에 넣어줘야 이름이 해석된다.
echo "🌐 로컬라이징 리소스(en.lproj) 복사..."
cp -R FxPlug_Template/KeyframeToolboxExtension/en.lproj "$APP_NAME/Contents/PlugIns/$EXTENSION_NAME/Contents/Resources/"

# 4. macOS 보안 정책에 따른 Ad-hoc 코드 서명 진행 (필수 - Hardened Runtime 활성화)
echo "🔑 macOS 보안을 위한 로컬 코드 서명(Codesign) 진행..."
codesign -f -s - --options runtime --entitlements entitlements.plist "$APP_NAME/Contents/PlugIns/$EXTENSION_NAME"
codesign -f -s - --options runtime --entitlements entitlements.plist "$APP_NAME"

# 5. /Applications 폴더로 복사 및 등록
echo "🚚 /Applications 폴더로 앱 전송 및 등록..."
rm -rf "/Applications/$APP_NAME"
cp -R "$APP_NAME" "/Applications/"
pluginkit -a "/Applications/$APP_NAME/Contents/PlugIns/$EXTENSION_NAME"
pluginkit -e use -i com.user.KeyframeToolboxV6.KeyframeToolboxExtension
open "/Applications/$APP_NAME"

echo "✅ 모든 빌드 및 연동 완료!"
echo "👉 파이널컷 프로를 재실행한 뒤 이펙트 창을 확인해 주세요."

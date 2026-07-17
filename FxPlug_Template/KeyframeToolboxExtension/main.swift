import Foundation
import FxPlug

// 계측용: 이 로그가 안 찍히면 NSLog 자체가 캡처되지 않는다는 뜻이므로
// "init 로그가 없다 = 플러그인이 호출되지 않았다"는 추론이 성립하지 않는다.
NSLog("=== KFTB-PROBE: extension main() 진입, startServicePrincipal 호출 직전 ===")

// FxPlug 4.0 XPC Service 서비스 리스너 시작 및 기동
FxPrincipal.startServicePrincipal()

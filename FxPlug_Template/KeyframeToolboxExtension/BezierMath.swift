import Foundation

struct BezierMath {
    let p1: CGPoint
    let p2: CGPoint

    init(p1: CGPoint, p2: CGPoint) {
        self.p1 = p1
        self.p2 = p2
    }

    // 3차 베지에 곡선 X(t) 좌표 계산
    private func sampleCurveX(t: Double) -> Double {
        return 3.0 * (1.0 - t) * (1.0 - t) * t * Double(p1.x) + 3.0 * (1.0 - t) * t * t * Double(p2.x) + t * t * t
    }

    // 3차 베지에 곡선 Y(t) 좌표 계산
    func sampleCurveY(t: Double) -> Double {
        return 3.0 * (1.0 - t) * (1.0 - t) * t * Double(p1.y) + 3.0 * (1.0 - t) * t * t * Double(p2.y) + t * t * t
    }

    // X(t)의 t에 대한 미분값 계산 (뉴턴-랩슨 해법에 활용)
    private func sampleCurveDerivativeX(t: Double) -> Double {
        let cx = 3.0 * Double(p1.x)
        let bx = 3.0 * (Double(p2.x) - Double(p1.x)) - cx
        let ax = 1.0 - cx - bx
        return 3.0 * ax * t * t + 2.0 * bx * t + cx
    }

    // 주어진 X값(시간 축)에 해당하는 매개변수 t를 뉴턴-랩슨 및 이진 탐색 기법으로 산출
    func solveTForX(x: Double) -> Double {
        var tGuess = x

        // 1단계: 뉴턴-랩슨 법 시도 (빠른 수렴)
        for _ in 0..<8 {
            let currentX = sampleCurveX(t: tGuess) - x
            let slope = sampleCurveDerivativeX(t: tGuess)
            if abs(slope) < 1e-6 { break }
            let nextT = tGuess - currentX / slope
            if nextT < 0.0 || nextT > 1.0 { break }
            tGuess = nextT
            if abs(currentX) < 1e-6 {
                return tGuess
            }
        }

        // 2단계: 범위 초과 또는 수렴 실패 시 이진 탐색으로 백업
        var tMin = 0.0
        var tMax = 1.0
        tGuess = x

        if tGuess < tMin { return tMin }
        if tGuess > tMax { return tMax }

        while tMin < tMax {
            let currentX = sampleCurveX(t: tGuess)
            if abs(currentX - x) < 1e-6 {
                return tGuess
            }
            if x > currentX {
                tMin = tGuess
            } else {
                tMax = tGuess
            }
            tGuess = (tMax + tMin) * 0.5
        }

        return tGuess
    }

    // 주어진 X(시간 진행도 0.0 ~ 1.0)에 상응하는 Y(보간값 0.0 ~ 1.0) 계산
    func evaluate(x: Double) -> Double {
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        let t = solveTForX(x: x)
        return sampleCurveY(t: t)
    }
}

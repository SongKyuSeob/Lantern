import Foundation

/// 설정 → 일반 → "창 모습": 평소 창 투명도와 창 크기 (2026-11-14, 사용자 피드백)
enum PanelAppearance {
    /// 평소 창의 불투명도(0.3~1). 활성 창은 늘 1
    static let opacityKey = "panel.passiveOpacity"
    static let opacityRange = 0.3...1.0

    static var passiveOpacity: Double {
        let value = UserDefaults.standard.object(forKey: opacityKey) as? Double ?? 1
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }
}

/// 플로팅 창의 글자와 창을 함께 키우고 줄이는 단계. 말풍선(메모·기한)과 설정·기록 창은 macOS 기본 크기를 따른다
enum PanelSize: String, CaseIterable, Identifiable {
    case small, standard, large, larger

    static let key = "panel.size"

    var id: Self { self }

    var scale: CGFloat {
        switch self {
        case .small: 0.9
        case .standard: 1
        case .large: 1.15
        case .larger: 1.3
        }
    }

    var title: String {
        switch self {
        case .small: String(localized: "작게")
        case .standard: String(localized: "기본")
        case .large: String(localized: "크게")
        case .larger: String(localized: "더 크게")
        }
    }

    static var current: PanelSize {
        #if DEBUG
        // 그림 저장 모드에서 단계별 화면을 확인할 때 실제 설정을 건드리지 않고 고른다
        if let size = ProcessInfo.processInfo.environment["LANTERN_RENDER_SIZE"].flatMap(PanelSize.init) { return size }
        #endif
        return UserDefaults.standard.string(forKey: key).flatMap(PanelSize.init) ?? .standard
    }
}

// 플로팅 창 안의 글자 크기·폭·여백은 `13.scaled`처럼 써서 고른 크기 단계를 곱한다.
// 단계를 바꾸면 `PanelView`가 화면을 새로 그린다(`.id`)
extension BinaryInteger {
    var scaled: CGFloat { PanelSize.scaled(CGFloat(self)) }
}

extension BinaryFloatingPoint {
    var scaled: CGFloat { PanelSize.scaled(CGFloat(self)) }
}

extension PanelSize {
    /// 배율을 곱한 값을 0.5pt(레티나 한 픽셀)로 반올림한다
    static func scaled(_ value: CGFloat) -> CGFloat {
        (value * current.scale * 2).rounded() / 2
    }
}

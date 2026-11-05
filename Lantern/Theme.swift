import AppKit
import SwiftUI

/// 창의 색. 시스템 라이트·다크 모드를 따른다.
///
/// 순수 Liquid Glass + 시스템 강조색·시스템 색으로, 제어 센터 같은 macOS 기본 앱 느낌을 낸다
/// (2026-10-29 확정. Figma 시안 v2.5의 남색 배경·인디고 강조색은 쓰지 않는다).
/// 글자·선은 `Theme.ink`에 진하기를 곱해 쓰고(라이트는 검정, 다크는 흰색), 모드마다 따로 맞춰야 하는 색만 여기 둔다
/// (라이트 값은 Figma "랜턴 · 라이트 모드 시안" A안, 2026-11-06)
enum Theme {
    /// 글자·선·칸의 기준 색. 라이트는 검정, 다크는 흰색이고 진하기를 곱해 쓴다.
    /// 시스템 `.primary`는 다크에서 85% 흰색이라, 0.5까지 쓰던 진하기를 그대로 곱하면 다크 화면이 흐려져서 따로 둔다
    static let ink = Color(light: .black, dark: .white)
    /// Liquid Glass에 섞는 색
    static let background = Color(light: .white, dark: .black)
    static let primary = Color.accentColor
    static let primaryLight = Color.accentColor
    static let primaryTabText = ink
    /// 선택된 탭(할 일 / 깨어 있기) 바탕
    static let tabSelectedFill = Color(light: .white.opacity(0.9), dark: .white.opacity(0.14))
    /// 선택된 세그먼트(언제까지) 바탕
    static let segmentSelectedFill = Color(light: .white.opacity(0.95), dark: .white.opacity(0.22))
    /// 깨어 있음 표시. 밝은 바탕에서는 시스템 주황이 흐려서 글자는 한 단계 진하게
    static let flame = Color(light: Color(red: 0.85, green: 0.43, blue: 0), dark: .orange)
    static let flameText = flame
    static let flameTextPassive = flame
    static let good = Color(light: Color(red: 0.14, green: 0.54, blue: 0.24), dark: .green)
    static let goodDot = Color.green
    static let goodPassive = good
    static let bad = Color(light: Color(red: 0.84, green: 0, blue: 0.08), dark: .red)

    static let divider = ink.opacity(0.07)
    static let fillTrack = ink.opacity(0.06)
    static let fillCard = ink.opacity(0.043)
    /// 유리 위 글자를 또렷하게 하는 그림자 (다크는 어둡게, 라이트는 밝게 번진다)
    static let textShadow = Color(light: .white.opacity(0.6), dark: .black.opacity(0.5))

    /// 평소 상태 Liquid Glass에 섞는 색의 진하기. 높을수록 덜 비친다
    static let passiveTintOpacity = 0.0
    /// 활성 창 Liquid Glass에 섞는 색의 진하기. 조작할 글자가 많아 평소보다 조금 진하게
    static let activeTintOpacity = 0.12
}

extension Color {
    /// 라이트·다크 모드에 따라 다른 색. 그리는 순간의 모드를 따른다
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
    }
}

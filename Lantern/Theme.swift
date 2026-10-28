import SwiftUI

/// 창의 색. 창은 항상 어두운 바탕이라 다크 모드 구분이 없다.
///
/// 순수 Liquid Glass + 시스템 강조색·시스템 색으로, 제어 센터 같은 macOS 기본 앱 느낌을 낸다
/// (2026-10-29 확정. Figma 시안 v2.5의 남색 배경·인디고 강조색은 쓰지 않는다)
enum Theme {
    /// Liquid Glass에 섞는 색
    static let background = Color.black
    static let primary = Color.accentColor
    static let primaryLight = Color.accentColor
    static let primaryTabText = Color.white
    /// 선택된 탭(할 일 / 깨어 있기) 바탕
    static let tabSelectedFill = Color.white.opacity(0.14)
    /// 선택된 세그먼트(언제까지) 바탕
    static let segmentSelectedFill = Color.white.opacity(0.22)
    static let flame = Color.orange
    static let flameText = Color.orange
    static let flameTextPassive = Color.orange
    static let good = Color.green
    static let goodDot = Color.green
    static let goodPassive = Color.green
    static let bad = Color.red

    static let divider = Color.white.opacity(0.07)
    static let fillTrack = Color.white.opacity(0.06)
    static let fillCard = Color.white.opacity(0.043)

    /// 평소 상태 Liquid Glass에 섞는 색의 진하기. 높을수록 덜 비친다
    static let passiveTintOpacity = 0.0
    /// 활성 창 Liquid Glass에 섞는 색의 진하기. 조작할 글자가 많아 평소보다 조금 진하게
    static let activeTintOpacity = 0.12
}

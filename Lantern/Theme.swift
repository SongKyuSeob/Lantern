import SwiftUI

/// Figma 시안 v2.5의 색. 창은 항상 어두운 바탕이라 다크 모드 구분이 없다.
enum Theme {
    static let background = Color(hex: 0x16161C)
    static let primary = Color(hex: 0x6E72FF)
    static let primaryLight = Color(hex: 0xA3A6FF)
    static let primaryTabText = Color(hex: 0xB8BAFF)
    static let flame = Color(hex: 0xFFB247)
    static let flameText = Color(hex: 0xFFC26B)
    static let flameTextPassive = Color(hex: 0xFFC773)
    static let good = Color(hex: 0x73E599)
    static let goodDot = Color(hex: 0x66E08F)
    static let goodPassive = Color(hex: 0x80F2A8)
    static let bad = Color(hex: 0xFF8A7A)

    static let border = Color.white.opacity(0.10)
    static let borderPassive = Color.white.opacity(0.12)
    static let divider = Color.white.opacity(0.07)
    static let fillTrack = Color.white.opacity(0.06)
    static let fillCard = Color.white.opacity(0.043)

    /// 평소 상태 바탕의 불투명도 (나중에 설정 슬라이더로 조절)
    static let passiveBackgroundOpacity = 0.55
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

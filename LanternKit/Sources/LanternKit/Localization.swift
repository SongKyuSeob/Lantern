import Foundation

/// 화면 언어. 한국어와 영어 두 가지만 있어서, 문구는 `L("한국어", "English")`처럼 쓰는 자리에 두 언어를 함께 둔다
public enum AppLanguage: String, CaseIterable, Sendable {
    case korean = "ko"
    case english = "en"

    /// 이 언어에 맞는 쪽. 테스트처럼 언어를 직접 정해야 할 때 쓴다
    public func text(_ korean: String, _ english: String) -> String {
        self == .korean ? korean : english
    }
}

/// 설정에서 고르는 언어. 시스템을 따르거나 직접 고른다
public enum LanguagePreference: String, CaseIterable, Sendable {
    case system
    case korean = "ko"
    case english = "en"
}

public enum Localization {
    /// 설정 값을 저장하는 UserDefaults 키
    public static let preferenceKey = "app.language"

    /// 지금 화면 언어. 앱을 켤 때 한 번 정하고, 바꾸면 다시 켠다 (Sparkle 창 같은 시스템 화면까지 맞추려고)
    nonisolated(unsafe) public static var language: AppLanguage = resolve(
        preference: UserDefaults.standard.string(forKey: preferenceKey).flatMap(LanguagePreference.init) ?? .system,
        preferredLanguages: Locale.preferredLanguages
    )

    /// 시스템을 따르면 선호 언어 목록에서 한국어가 영어보다 앞에 있을 때만 한국어, 아니면 영어
    public static func resolve(preference: LanguagePreference, preferredLanguages: [String]) -> AppLanguage {
        switch preference {
        case .korean: return .korean
        case .english: return .english
        case .system:
            for identifier in preferredLanguages {
                if identifier.hasPrefix("ko") { return .korean }
                if identifier.hasPrefix("en") { return .english }
            }
            return .english
        }
    }

    /// 날짜·시각 형식에 쓰는 지역 설정. 언어만 화면 언어로 바꾸고 지역은 시스템을 따른다
    public static var locale: Locale { locale(for: language) }

    public static func locale(for language: AppLanguage) -> Locale {
        Locale(languageCode: .init(language.rawValue), languageRegion: Locale.current.region)
    }
}

/// 화면 문구. 지금 화면 언어에 맞는 쪽을 돌려준다
public func L(_ korean: String, _ english: String) -> String {
    Localization.language.text(korean, english)
}

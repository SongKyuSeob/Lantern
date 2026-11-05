import Foundation

/// 화면 언어. 문구는 String Catalog(`Localizable.xcstrings`, 원본 한국어)에 있고, 앱은 시스템 방식대로 언어를 고른다
public enum AppLanguage: String, CaseIterable, Sendable {
    case korean = "ko"
    case english = "en"

    /// 이 언어의 LanternKit 번역 묶음. 없으면 기본 묶음
    var bundle: Bundle {
        Bundle.module.url(forResource: rawValue, withExtension: "lproj").flatMap(Bundle.init(url:)) ?? .module
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

    /// 지금 화면 언어. 앱이 켤 때 실제로 고른 번역(`Bundle.main.preferredLocalizations`)으로 정한다.
    /// 바꾸려면 앱 선호 언어(`AppleLanguages`)를 바꾸고 다시 켠다
    nonisolated(unsafe) public static var language: AppLanguage = Bundle.main.preferredLocalizations.first
        .flatMap { identifier in AppLanguage.allCases.first { identifier.hasPrefix($0.rawValue) } } ?? .korean

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

/// LanternKit 문구를 정한 언어로 가져온다. 테스트처럼 언어를 직접 정해야 하는 곳에서 쓴다
func localized(_ key: String.LocalizationValue, _ language: AppLanguage) -> String {
    String(localized: key, bundle: language.bundle, locale: Localization.locale(for: language))
}

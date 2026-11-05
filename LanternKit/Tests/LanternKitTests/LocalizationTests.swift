import LanternKit
import Testing

@Suite("화면 언어")
struct LocalizationTests {
    @Test("직접 고르면 그 언어", arguments: [(LanguagePreference.korean, AppLanguage.korean), (.english, .english)])
    func explicit(_ pair: (LanguagePreference, AppLanguage)) {
        #expect(Localization.resolve(preference: pair.0, preferredLanguages: ["ja-JP"]) == pair.1)
    }

    @Test("시스템을 따르면 한국어·영어 중 먼저 나오는 쪽, 둘 다 없으면 영어", arguments: [
        (["ko-KR", "en-US"], AppLanguage.korean),
        (["en-US", "ko-KR"], .english),
        (["ja-JP", "ko-KR"], .korean),
        (["ja-JP", "fr-FR"], .english),
    ])
    func system(_ pair: ([String], AppLanguage)) {
        #expect(Localization.resolve(preference: .system, preferredLanguages: pair.0) == pair.1)
    }
}

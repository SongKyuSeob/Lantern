import AppKit
import LanternKit

/// 화면 언어를 바꾼다. 문구는 앱을 켤 때 정해지므로, 바꾼 뒤 다시 켜야 적용된다
enum AppLanguageSetting {
    /// 고른 언어를 저장한다. Sparkle 창 같은 시스템 화면도 같은 언어로 나오도록 앱의 선호 언어(`AppleLanguages`)도 맞춘다
    static func save(_ preference: LanguagePreference, defaults: UserDefaults = .standard) {
        defaults.set(preference.rawValue, forKey: Localization.preferenceKey)
        switch preference {
        case .system: defaults.removeObject(forKey: "AppleLanguages")
        case .korean, .english: defaults.set([preference.rawValue], forKey: "AppleLanguages")
        }
    }

    /// 고른 언어가 지금 화면 언어와 달라 다시 켜야 하는지
    static func needsRelaunch(_ preference: LanguagePreference) -> Bool {
        Localization.resolve(preference: preference, preferredLanguages: systemLanguages) != Localization.language
    }

    /// 앱 선호 언어를 뺀 시스템 언어 목록 (`Locale.preferredLanguages`는 `AppleLanguages`를 먼저 돌려준다)
    private static var systemLanguages: [String] {
        UserDefaults(suiteName: UserDefaults.globalDomain)?.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
    }

    /// 랜턴을 끄고 다시 켠다. 두 개가 함께 켜지지 않게, 이 앱이 끝난 뒤 1초 기다렸다 연다
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }
}

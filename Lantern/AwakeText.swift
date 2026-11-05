import Foundation
import LanternKit

/// 메뉴와 창이 함께 쓰는 깨어 있기 문구.
enum AwakeText {
    static func label(for option: AwakeOption) -> String {
        switch option {
        case .indefinite: String(localized: "계속")
        case .hours(let hours): String(localized: "\(hours)시간")
        case .timeOfDay(let hour, let minute): History.untilText(clock(hour: hour, minute: minute), tomorrow: false)
        case .untilAgentsFinish: String(localized: "에이전트가 끝날 때까지")
        }
    }

    /// 세그먼트·버튼에 쓰는 짧은 이름: "에이전트", "오후 4:30" / "Agents", "4:30 PM"
    static func shortLabel(for option: AwakeOption) -> String {
        switch option {
        case .untilAgentsFinish: String(localized: "에이전트")
        case .timeOfDay(let hour, let minute): clock(hour: hour, minute: minute)
        default: label(for: option)
        }
    }

    /// "오후 4:30까지", 다음 날이면 "내일 오전 7:00까지" ("Until 4:30 PM", "Until tomorrow 7:00 AM"). 끝나는 시각이 없으면 `nil`
    static func until(_ session: AwakeSession, calendar: Calendar = .current) -> String? {
        guard let endsAt = session.endsAt else { return nil }
        return until(endsAt, from: session.startedAt, calendar: calendar)
    }

    static func until(_ endsAt: Date, from start: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: endsAt)
        let time = clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        return History.untilText(time, tomorrow: !calendar.isDate(endsAt, inSameDayAs: start))
    }

    /// 연장 버튼에서 고르는 시간
    static var extensions: [(label: String, interval: TimeInterval)] {
        [(String(localized: "30분 더"), 30 * 60), (String(localized: "1시간 더"), 3600), (String(localized: "2시간 더"), 2 * 3600)]
    }

    /// "오전 7시", "오후 12시" / "7 AM", "12 PM"
    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(Date.FormatStyle(locale: Localization.locale).hour(.defaultDigits(amPM: .abbreviated)))
    }

    /// "오전 7:00", "오후 12:30" / "7:00 AM", "12:30 PM"
    static func clock(hour: Int, minute: Int) -> String {
        History.clock(hour: hour, minute: minute)
    }

    /// 지금 뚜껑을 닫으면 어떻게 되는지. 뚜껑이 없는 맥이면 `nil`
    static func lidClose(_ outcome: LidCloseOutcome) -> (staysAwake: Bool, value: String, detail: String)? {
        switch outcome {
        case .noLid: nil
        case .staysAwake(.clamshell): (true, String(localized: "유지됨"), String(localized: "전원 · 외장 모니터 연결됨"))
        case .staysAwake(.lidMode): (true, String(localized: "유지됨"), String(localized: "뚜껑 모드"))
        case .sleeps(.noExternalDisplay): (false, String(localized: "잠듦"), String(localized: "외장 모니터 없음"))
        case .sleeps(.noPower): (false, String(localized: "잠듦"), String(localized: "전원 어댑터 연결 안 됨"))
        case .sleeps(.noPowerAndNoExternalDisplay): (false, String(localized: "잠듦"), String(localized: "전원 어댑터 · 외장 모니터 없음"))
        }
    }
}

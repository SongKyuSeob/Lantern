import Foundation
import LanternKit

/// 메뉴와 창이 함께 쓰는 깨어 있기 문구.
enum AwakeText {
    static func label(for option: AwakeOption) -> String {
        switch option {
        case .indefinite: L("계속", "Always")
        case .hours(let hours): L("\(hours)시간", hours == 1 ? "1 Hour" : "\(hours) Hours")
        case .timeOfDay(let hour, let minute): History.untilText(clock(hour: hour, minute: minute), tomorrow: false)
        case .untilAgentsFinish: L("에이전트가 끝날 때까지", "Until agents finish")
        }
    }

    /// 세그먼트·버튼에 쓰는 짧은 이름: "에이전트", "오후 4:30" / "Agents", "4:30 PM"
    static func shortLabel(for option: AwakeOption) -> String {
        switch option {
        case .untilAgentsFinish: L("에이전트", "Agents")
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
        [(L("30분 더", "+30 Minutes"), 30 * 60), (L("1시간 더", "+1 Hour"), 3600), (L("2시간 더", "+2 Hours"), 2 * 3600)]
    }

    /// "오전 7시", "오후 12시" / "7 AM", "12 PM"
    static func hourLabel(_ hour: Int) -> String {
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return L("\(hour < 12 ? "오전" : "오후") \(hour12)시", "\(hour12) \(hour < 12 ? "AM" : "PM")")
    }

    /// "오전 7:00", "오후 12:30" / "7:00 AM", "12:30 PM"
    static func clock(hour: Int, minute: Int) -> String {
        History.clock(hour: hour, minute: minute)
    }

    /// 지금 뚜껑을 닫으면 어떻게 되는지. 뚜껑이 없는 맥이면 `nil`
    static func lidClose(_ outcome: LidCloseOutcome) -> (staysAwake: Bool, value: String, detail: String)? {
        switch outcome {
        case .noLid: nil
        case .staysAwake(.clamshell): (true, L("유지됨", "Stays awake"), L("전원 · 외장 모니터 연결됨", "Plugged in · External display connected"))
        case .staysAwake(.lidMode): (true, L("유지됨", "Stays awake"), L("뚜껑 모드", "Closed-Lid Mode"))
        case .sleeps(.noExternalDisplay): (false, L("잠듦", "Sleeps"), L("외장 모니터 없음", "No external display"))
        case .sleeps(.noPower): (false, L("잠듦", "Sleeps"), L("전원 어댑터 연결 안 됨", "Not plugged in"))
        case .sleeps(.noPowerAndNoExternalDisplay): (false, L("잠듦", "Sleeps"), L("전원 어댑터 · 외장 모니터 없음", "Not plugged in · No external display"))
        }
    }
}

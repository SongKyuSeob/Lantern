import Foundation
import LanternKit

/// 메뉴와 창이 함께 쓰는 깨어 있기 문구.
enum AwakeText {
    static func label(for option: AwakeOption) -> String {
        switch option {
        case .indefinite: "계속"
        case .hours(let hours): "\(hours)시간"
        case .timeOfDay(let hour, let minute): "\(clock(hour: hour, minute: minute))까지"
        case .untilAgentsFinish: "에이전트가 끝날 때까지"
        }
    }

    /// "오후 4:30까지", 다음 날이면 "내일 오전 7:00까지". 끝나는 시각이 없으면 `nil`
    static func until(_ session: AwakeSession, calendar: Calendar = .current) -> String? {
        guard let endsAt = session.endsAt else { return nil }
        return until(endsAt, from: session.startedAt, calendar: calendar)
    }

    static func until(_ endsAt: Date, from start: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: endsAt)
        let time = clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        let tomorrow = calendar.isDate(endsAt, inSameDayAs: start) ? "" : "내일 "
        return "\(tomorrow)\(time)까지"
    }

    /// "오전 7시", "오후 12시"
    static func hourLabel(_ hour: Int) -> String {
        let period = hour < 12 ? "오전" : "오후"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(period) \(hour12)시"
    }

    /// "오전 7:00", "오후 12:30"
    static func clock(hour: Int, minute: Int) -> String {
        let period = hour < 12 ? "오전" : "오후"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(period) \(hour12):\(String(format: "%02d", minute))"
    }

    /// 지금 뚜껑을 닫으면 어떻게 되는지. 뚜껑이 없는 맥이면 `nil`
    static func lidClose(_ outcome: LidCloseOutcome) -> (staysAwake: Bool, value: String, detail: String)? {
        switch outcome {
        case .noLid: nil
        case .staysAwake(.clamshell): (true, "유지됨", "전원 · 외장 모니터 연결됨")
        case .staysAwake(.lidMode): (true, "유지됨", "뚜껑 모드")
        case .sleeps(.noExternalDisplay): (false, "잠듦", "외장 모니터 없음")
        case .sleeps(.noPower): (false, "잠듦", "전원 어댑터 연결 안 됨")
        case .sleeps(.noPowerAndNoExternalDisplay): (false, "잠듦", "전원 어댑터 · 외장 모니터 없음")
        }
    }
}

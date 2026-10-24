import Foundation

/// 사용자가 고르는 "언제까지 깨어 있을지".
///
/// 고른 순간의 선택지 자체를 담는다. 실제 종료 시각은 세션을 시작할 때 `endDate(startingAt:calendar:)`로 정한다.
/// 그래서 "빠르게 켜기"로 같은 옵션을 다시 쓰면, 그때의 현재 시각을 기준으로 종료 시각이 새로 계산된다.
public enum AwakeOption: Codable, Equatable, Hashable, Sendable {
    /// 계속: 사용자가 끌 때까지
    case indefinite
    /// 1시간, 2시간처럼 정해진 시간 동안
    case hours(Int)
    /// 지정한 시각까지. 이미 지난 시각이면 다음 날 그 시각
    case timeOfDay(hour: Int, minute: Int)
    /// 에이전트 작업이 모두 끝날 때까지 (감지는 M3)
    case untilAgentsFinish

    /// 이 옵션으로 `start`에 세션을 시작했을 때의 종료 시각. 시간으로 끝나지 않는 옵션은 `nil`
    public func endDate(startingAt start: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .indefinite, .untilAgentsFinish:
            return nil
        case .hours(let hours):
            return start.addingTimeInterval(TimeInterval(hours) * 3600)
        case .timeOfDay(let hour, let minute):
            return calendar.nextDate(
                after: start,
                matching: DateComponents(hour: hour, minute: minute, second: 0),
                matchingPolicy: .nextTime
            )
        }
    }
}

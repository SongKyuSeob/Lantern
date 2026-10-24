import Foundation

/// 깨어 있기를 켠 순간부터 꺼지는 순간까지의 한 번.
public struct AwakeSession: Codable, Equatable, Sendable {
    public let option: AwakeOption
    public let startedAt: Date
    /// 시간으로 끝나는 옵션이면 종료 시각, 아니면 `nil`
    public let endsAt: Date?

    public init(option: AwakeOption, startedAt: Date, calendar: Calendar = .current) {
        self.option = option
        self.startedAt = startedAt
        self.endsAt = option.endDate(startingAt: startedAt, calendar: calendar)
    }

    /// `now` 기준 남은 시간(초). 시간으로 끝나지 않는 세션은 `nil`, 이미 지났으면 0
    public func remaining(at now: Date) -> TimeInterval? {
        guard let endsAt else { return nil }
        return max(0, endsAt.timeIntervalSince(now))
    }

    /// 정해 둔 시각이 지났는지
    public func hasExpired(at now: Date) -> Bool {
        guard let endsAt else { return false }
        return now >= endsAt
    }
}

/// 세션이 끝난 이유
public enum AwakeEndReason: String, Codable, Sendable {
    /// 사용자가 직접 끔
    case userStopped
    /// 정해 둔 시간이 다 됨
    case timeElapsed
    /// 에이전트 작업이 모두 끝남
    case agentsFinished
}

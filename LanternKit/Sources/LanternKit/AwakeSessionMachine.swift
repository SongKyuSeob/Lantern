import Foundation

/// 깨어 있기 세션의 상태를 관리한다. 켜고, 끄고, 시간이 다 됐는지 확인한다.
///
/// 실제로 맥을 안 재우는 일(`IOPMAssertion`)은 하지 않는다. 앱은 이 상태를 보고 시스템 호출을 붙이거나 뗀다.
/// 현재 시각은 항상 바깥에서 받아서, 테스트에서 시간을 마음대로 돌릴 수 있게 한다.
public struct AwakeSessionMachine: Sendable {
    /// 진행 중인 세션. 꺼져 있으면 `nil`
    public private(set) var current: AwakeSession?
    /// 마지막으로 쓴 옵션. "빠르게 켜기"에 쓴다
    public private(set) var lastOption: AwakeOption

    public var isAwake: Bool { current != nil }

    public init(lastOption: AwakeOption = .hours(2)) {
        self.lastOption = lastOption
    }

    /// 새 세션을 시작한다. 이미 켜져 있으면 새 옵션으로 갈아 끼운다
    public mutating func start(_ option: AwakeOption, at now: Date, calendar: Calendar = .current) {
        current = AwakeSession(option: option, startedAt: now, calendar: calendar)
        lastOption = option
    }

    /// 마지막으로 쓴 옵션으로 시작한다
    public mutating func startWithLastOption(at now: Date, calendar: Calendar = .current) {
        start(lastOption, at: now, calendar: calendar)
    }

    /// 세션을 끝낸다. 끝난 세션을 돌려주고, 켜져 있지 않았으면 `nil`
    @discardableResult
    public mutating func stop() -> AwakeSession? {
        defer { current = nil }
        return current
    }

    /// 지금 세션을 끊지 않고 끝 시각만 `interval`만큼 미룬다. 시간으로 끝나는 세션이 아니면 `false`
    @discardableResult
    public mutating func extend(by interval: TimeInterval) -> Bool {
        guard let extended = current?.extended(by: interval) else { return false }
        current = extended
        return true
    }

    /// 주기적으로 불러서 시간이 다 됐으면 세션을 끝낸다. 끝냈으면 그 이유를 돌려준다
    public mutating func tick(at now: Date) -> AwakeEndReason? {
        guard let current, current.hasExpired(at: now) else { return nil }
        stop()
        return .timeElapsed
    }
}

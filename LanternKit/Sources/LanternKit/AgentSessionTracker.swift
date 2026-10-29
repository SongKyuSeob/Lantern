import Foundation

/// 에이전트 세션별로 지금 일하는 중인지 판단한다.
///
/// hook 신호만으로 판단하므로 끝 신호를 놓칠 수 있다 (Esc 중단, 강제 종료 등). 그래서
/// - 에이전트 프로세스가 사라졌으면 끝난 것으로 본다
/// - 실행 중인 도구 없이 `quietLimit` 동안 신호가 없으면 끝난 것으로 본다
/// - 도구나 백그라운드 작업이 실행 중이면 `busyLimit`까지 기다린다 (긴 빌드처럼 중간 신호가 없는 경우)
/// - 사용자 허락을 기다리는 중이면 도구가 실행 중이 아니므로 `quietLimit`을 쓴다.
///   다만 "허락했다"는 신호는 따로 오지 않으므로, 허락 요청 뒤에 시작해 `approvedCommandMinimumAge` 넘게 살아 있는
///   자식 프로세스가 에이전트 아래에 있으면 허락받고 명령이 도는 중으로 보고 `busyLimit`을 쓴다.
///   잠깐 생겼다 사라지는 프로세스(상태 줄 등)는 나이 조건으로 거른다. 틀리면 더 오래 깨어 있는 쪽이라 안전하다
public struct AgentSessionTracker: Sendable {
    public static let quietLimit: TimeInterval = 30 * 60
    public static let busyLimit: TimeInterval = 3 * 3600
    /// 응답은 끝났는데 백그라운드 작업만 남았을 때의 상한.
    /// 개발 서버처럼 끝나지 않는 작업 때문에 매번 3시간씩 깨어 있지 않게 짧게 둔다
    public static let backgroundLimit: TimeInterval = 60 * 60
    /// 이보다 오래 살아 있어야 허락받고 실행 중인 명령으로 본다
    public static let approvedCommandMinimumAge: TimeInterval = 10

    public enum Status: Equatable, Sendable {
        /// 신호가 계속 오고 있음
        case working
        /// 도구나 백그라운드 작업이 실행 중이라 신호가 없어도 기다리는 중
        case runningCommand
        /// 사용자 허락을 기다리는 중
        case awaitingPermission
        case done
    }

    public struct Session: Equatable, Sendable {
        public let agent: AgentKind
        public let sessionID: String
        public fileprivate(set) var agentPID: Int32?
        /// 프로세스 번호가 다른 프로그램에 재사용됐는지 가리기 위한 시작 시각
        public fileprivate(set) var agentStartedAt: Date?
        public fileprivate(set) var isWorking = false
        public fileprivate(set) var lastEventAt: Date
        fileprivate var runningTools: Set<String> = []
        /// 번호 없이 시작된 도구 수
        fileprivate var anonymousTools = 0
        /// 끝 신호가 시작 신호보다 먼저 처리된 도구. 늦게 온 시작 신호를 무시한다
        fileprivate var finishedTools: Set<String> = []
        fileprivate var awaitingPermission = false
        /// 마지막으로 허락을 요청한 시각
        fileprivate var permissionRequestedAt: Date?
        fileprivate var hasBackgroundWork = false

        var isRunningTool: Bool { !runningTools.isEmpty || anonymousTools > 0 }
    }

    public private(set) var sessions: [String: Session] = [:]

    public init() {}

    private static func key(_ agent: AgentKind, _ sessionID: String) -> String {
        "\(agent.rawValue):\(sessionID)"
    }

    /// 신호 하나를 반영한다. `agentStartedAt`은 신호에 담긴 프로세스의 시작 시각(앱이 확인한 값)
    public mutating func apply(_ event: AgentHookEvent, agentStartedAt: Date? = nil) {
        let key = Self.key(event.agent, event.sessionID)
        if case .sessionEnd = event.kind {
            sessions[key] = nil
            return
        }
        var session = sessions[key] ?? Session(agent: event.agent, sessionID: event.sessionID, lastEventAt: event.receivedAt)
        if let pid = event.agentPID, pid != session.agentPID {
            session.agentPID = pid
            session.agentStartedAt = agentStartedAt
        }
        session.lastEventAt = max(session.lastEventAt, event.receivedAt)
        session.awaitingPermission = false

        switch event.kind {
        case .sessionStart, .other:
            break
        case .promptSubmit:
            session.isWorking = true
            session.runningTools = []
            session.anonymousTools = 0
            session.finishedTools = []
            session.hasBackgroundWork = false
        case .toolStart(let id):
            session.isWorking = true
            if let id {
                if session.finishedTools.remove(id) == nil { session.runningTools.insert(id) }
            } else {
                session.anonymousTools += 1
            }
        case .toolEnd(let id):
            // 응답이 끝난 뒤 늦게 온 "도구 끝"은 세션을 다시 일하는 중으로 돌리지 않는다
            guard session.isWorking else { break }
            if let id {
                if session.runningTools.remove(id) == nil { session.finishedTools.insert(id) }
            } else {
                session.anonymousTools = max(0, session.anonymousTools - 1)
            }
        case .permissionRequest:
            session.isWorking = true
            session.awaitingPermission = true
            session.permissionRequestedAt = event.receivedAt
        case .subagentActivity:
            // 응답이 끝난 뒤 늦게 끝난 서브에이전트도 마찬가지
            guard session.isWorking else { break }
        case .stop(let hasBackgroundWork):
            session.runningTools = []
            session.anonymousTools = 0
            session.hasBackgroundWork = hasBackgroundWork
            session.isWorking = hasBackgroundWork
        case .stopFailure:
            session.isWorking = false
            session.runningTools = []
            session.anonymousTools = 0
            session.hasBackgroundWork = false
        case .sessionEnd:
            break
        }
        sessions[key] = session
    }

    /// `isAlive`는 (프로세스 번호, 시작 시각)이 아직 같은 프로그램으로 살아 있는지 알려 준다.
    /// `childStartTimes`는 에이전트 프로세스의 자식 프로세스들이 시작한 시각 (허락 대기 중에만 묻는다)
    public func status(
        of session: Session,
        now: Date,
        isAlive: (Int32, Date?) -> Bool,
        childStartTimes: (Int32) -> [Date] = { _ in [] }
    ) -> Status {
        guard session.isWorking else { return .done }
        if let pid = session.agentPID, !isAlive(pid, session.agentStartedAt) { return .done }
        let quiet = now.timeIntervalSince(session.lastEventAt)
        if session.awaitingPermission {
            if let pid = session.agentPID, let requestedAt = session.permissionRequestedAt,
               childStartTimes(pid).contains(where: {
                   $0 >= requestedAt.addingTimeInterval(-1) && now.timeIntervalSince($0) >= Self.approvedCommandMinimumAge
               }) {
                return quiet < Self.busyLimit ? .runningCommand : .done
            }
            return quiet < Self.quietLimit ? .awaitingPermission : .done
        }
        if session.isRunningTool {
            return quiet < Self.busyLimit ? (quiet < 60 ? .working : .runningCommand) : .done
        }
        if session.hasBackgroundWork {
            return quiet < Self.backgroundLimit ? (quiet < 60 ? .working : .runningCommand) : .done
        }
        return quiet < Self.quietLimit ? .working : .done
    }

    /// 일하는 중인 세션들
    public func activeSessions(
        now: Date,
        isAlive: (Int32, Date?) -> Bool,
        childStartTimes: (Int32) -> [Date] = { _ in [] }
    ) -> [(session: Session, status: Status)] {
        sessions.values
            .map { ($0, status(of: $0, now: now, isAlive: isAlive, childStartTimes: childStartTimes)) }
            .filter { $0.1 != .done }
            .sorted { $0.0.lastEventAt > $1.0.lastEventAt }
    }

    /// 끝난 지 오래됐거나 프로세스가 사라진 세션을 지운다
    public mutating func prune(now: Date, isAlive: (Int32, Date?) -> Bool) {
        sessions = sessions.filter { _, session in
            if let pid = session.agentPID, !isAlive(pid, session.agentStartedAt) { return false }
            return now.timeIntervalSince(session.lastEventAt) < Self.busyLimit
        }
    }
}

/// "에이전트가 끝날 때까지" 옵션에서 깨어 있기를 끌 때를 정한다.
///
/// - 일하는 에이전트가 하나라도 있으면 계속
/// - 모두 끝나면 `grace` 뒤에 끈다 (그 사이 다음 지시를 내리면 이어진다)
/// - 켰는데 에이전트가 한 번도 일하지 않으면 `waitLimit`까지 기다린다
public struct AgentFinishWatch: Sendable {
    public static let grace: TimeInterval = 60
    public static let waitLimit: TimeInterval = AgentSessionTracker.quietLimit

    public let startedAt: Date
    public private(set) var lastWorkingAt: Date?

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    /// 지금 깨어 있기를 끝내야 하면 `true`
    public mutating func update(anyWorking: Bool, now: Date) -> Bool {
        if anyWorking {
            lastWorkingAt = now
            return false
        }
        if let lastWorkingAt {
            return now.timeIntervalSince(lastWorkingAt) >= Self.grace
        }
        return now.timeIntervalSince(startedAt) >= Self.waitLimit
    }

    /// 에이전트가 한 번이라도 일하는 걸 봤는지
    public var hasSeenWork: Bool { lastWorkingAt != nil }
}

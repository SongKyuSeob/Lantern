import Foundation

/// 에이전트 세션별로 지금 일하는 중인지 판단한다.
///
/// hook 신호만으로 판단하므로 끝 신호를 놓칠 수 있다 (Esc 중단, 강제 종료 등). 그래서
/// - 에이전트 프로세스가 사라졌으면 끝난 것으로 본다
/// - 실행 중인 도구 없이 `quietLimit` 동안 신호가 없으면 끝난 것으로 본다
/// - 도구나 백그라운드 작업이 실행 중이면 `busyLimit`까지 기다린다 (긴 빌드처럼 중간 신호가 없는 경우)
/// - 사용자 허락을 기다리는 중이면 도구가 실행 중이 아니므로 `quietLimit`을 쓴다
public struct AgentSessionTracker: Sendable {
    public static let quietLimit: TimeInterval = 30 * 60
    public static let busyLimit: TimeInterval = 3 * 3600

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
        fileprivate var hasBackgroundWork = false

        var isBusy: Bool { !runningTools.isEmpty || anonymousTools > 0 || hasBackgroundWork }
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
            session.isWorking = true
            if let id {
                if session.runningTools.remove(id) == nil { session.finishedTools.insert(id) }
            } else {
                session.anonymousTools = max(0, session.anonymousTools - 1)
            }
        case .permissionRequest:
            session.isWorking = true
            session.awaitingPermission = true
        case .subagentActivity:
            session.isWorking = true
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

    /// `isAlive`는 (프로세스 번호, 시작 시각)이 아직 같은 프로그램으로 살아 있는지 알려 준다
    public func status(of session: Session, now: Date, isAlive: (Int32, Date?) -> Bool) -> Status {
        guard session.isWorking else { return .done }
        if let pid = session.agentPID, !isAlive(pid, session.agentStartedAt) { return .done }
        let quiet = now.timeIntervalSince(session.lastEventAt)
        if session.awaitingPermission {
            return quiet < Self.quietLimit ? .awaitingPermission : .done
        }
        if session.isBusy {
            return quiet < Self.busyLimit ? (quiet < 60 ? .working : .runningCommand) : .done
        }
        return quiet < Self.quietLimit ? .working : .done
    }

    /// 일하는 중인 세션들
    public func activeSessions(now: Date, isAlive: (Int32, Date?) -> Bool) -> [(session: Session, status: Status)] {
        sessions.values
            .map { ($0, status(of: $0, now: now, isAlive: isAlive)) }
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

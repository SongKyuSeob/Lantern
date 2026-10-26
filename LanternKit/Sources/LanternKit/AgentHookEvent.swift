import Foundation

/// hook을 걸 수 있는 에이전트 프로그램
public enum AgentKind: String, CaseIterable, Codable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

/// 에이전트 hook이 남긴 신호 하나.
///
/// hook 스크립트는 신호마다 파일 하나를 남긴다. 첫 줄은 에이전트 종류, 둘째 줄은 에이전트 프로세스 번호(모르면 빈 줄),
/// 나머지는 에이전트가 hook에 넘긴 JSON 그대로다.
public struct AgentHookEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case sessionStart
        case promptSubmit
        /// 도구 실행 시작. 같은 도구의 시작·끝을 짝짓는 번호가 있으면 담는다
        case toolStart(id: String?)
        case toolEnd(id: String?)
        /// 도구를 실행해도 되는지 사용자에게 묻는 중
        case permissionRequest
        case subagentActivity
        /// 응답이 끝남. 백그라운드 작업이 남아 있으면 아직 일하는 중이다
        case stop(hasBackgroundWork: Bool)
        /// API 오류 등으로 응답이 멈춤
        case stopFailure
        case sessionEnd
        /// 판단에 쓰지 않는 신호. 활동이 있었다는 것만 기록한다
        case other
    }

    public let agent: AgentKind
    public let sessionID: String
    public let kind: Kind
    public let agentPID: Int32?
    public let receivedAt: Date

    public init(agent: AgentKind, sessionID: String, kind: Kind, agentPID: Int32?, receivedAt: Date) {
        self.agent = agent
        self.sessionID = sessionID
        self.kind = kind
        self.agentPID = agentPID
        self.receivedAt = receivedAt
    }

    /// hook이 남긴 파일 내용을 읽는다. 형식이 맞지 않으면 `nil`
    public static func parse(fileContents: String, receivedAt: Date) -> AgentHookEvent? {
        let parts = fileContents.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3,
              let agent = AgentKind(rawValue: String(parts[0])),
              let object = try? JSONSerialization.jsonObject(with: Data(parts[2].utf8)) as? [String: Any],
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty,
              let eventName = object["hook_event_name"] as? String
        else { return nil }
        return AgentHookEvent(
            agent: agent,
            sessionID: sessionID,
            kind: kind(eventName: eventName, payload: object),
            agentPID: Int32(parts[1]),
            receivedAt: receivedAt
        )
    }

    private static func kind(eventName: String, payload: [String: Any]) -> Kind {
        let toolID = (payload["tool_use_id"] ?? payload["call_id"]) as? String
        switch eventName {
        case "SessionStart": return .sessionStart
        case "UserPromptSubmit": return .promptSubmit
        case "PreToolUse": return .toolStart(id: toolID)
        case "PostToolUse", "PostToolUseFailure": return .toolEnd(id: toolID)
        case "PermissionRequest": return .permissionRequest
        case "SubagentStart", "SubagentStop": return .subagentActivity
        case "Stop":
            let tasks = payload["background_tasks"] as? [Any] ?? []
            return .stop(hasBackgroundWork: !tasks.isEmpty)
        case "StopFailure": return .stopFailure
        case "SessionEnd": return .sessionEnd
        default: return .other
        }
    }
}

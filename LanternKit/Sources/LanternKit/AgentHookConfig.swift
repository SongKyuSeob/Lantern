import Foundation

/// 에이전트 프로그램 설정 파일에 랜턴 hook을 넣고 뺀다.
///
/// Claude Code(`~/.claude/settings.json`)와 Codex(`~/.codex/hooks.json`)는 같은 모양을 쓴다:
/// `{"hooks": {"이벤트": [{"hooks": [{"type": "command", "command": "..."}]}]}}`.
/// 다른 프로그램(오르카 등)이 넣은 hook은 건드리지 않고, 랜턴 것만 표시 문자열로 찾아 넣고 뺀다.
public enum AgentHookConfig {
    /// 랜턴 hook 명령에 들어가는 표시. 이걸로 랜턴 것을 찾는다
    public static let marker = "lantern-agent-hook"
    public static let scriptName = "lantern-agent-hook"
    /// hook 하나가 쓸 수 있는 최대 시간(초). 스크립트는 보통 수십 밀리초 안에 끝난다
    static let timeout = 5

    public static func configPath(for agent: AgentKind, home: String) -> String {
        switch agent {
        case .claude: "\(home)/.claude/settings.json"
        case .codex: "\(home)/.codex/hooks.json"
        }
    }

    /// 에이전트 프로그램이 설치돼 있는지 볼 때 쓰는 폴더
    public static func configDirectory(for agent: AgentKind, home: String) -> String {
        (configPath(for: agent, home: home) as NSString).deletingLastPathComponent
    }

    public static func scriptPath(home: String) -> String {
        "\(home)/Library/Application Support/Lantern/\(scriptName)"
    }

    public static func eventsDirectory(home: String) -> String {
        "\(home)/Library/Application Support/Lantern/agent-events"
    }

    /// 랜턴이 듣는 이벤트
    public static func events(for agent: AgentKind) -> [String] {
        switch agent {
        case .claude:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
             "PermissionRequest", "SubagentStart", "SubagentStop", "Stop", "StopFailure", "SessionEnd"]
        case .codex:
            ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
             "PermissionRequest", "SubagentStart", "SubagentStop", "Stop", "SessionEnd"]
        }
    }

    /// 설정 파일에 넣는 명령.
    /// 랜턴을 지워 스크립트가 없어져도 에이전트에 오류가 나지 않게, 없으면 입력만 읽고 조용히 끝낸다
    public static func command(for agent: AgentKind) -> String {
        """
        : \(marker); f="$HOME/Library/Application Support/Lantern/\(scriptName)"; \
        if [ -x "$f" ]; then "$f" \(agent.rawValue); else cat >/dev/null; fi; exit 0
        """
    }

    /// 설정에 랜턴 hook을 넣은 결과. 이미 있으면 새 명령으로 바꾼다. 나머지 내용과 순서는 그대로 둔다
    public static func installing(_ agent: AgentKind, into root: OrderedJSON) -> OrderedJSON {
        var root = removing(from: root)
        var hooks = root["hooks"] ?? .object([])
        let entry = OrderedJSON.object([
            ("hooks", .array([
                .object([
                    ("type", .string("command")),
                    ("command", .string(command(for: agent))),
                    ("timeout", .number(String(timeout))),
                ]),
            ])),
        ])
        for event in events(for: agent) {
            var groups: [OrderedJSON] = []
            if case .array(let existing) = hooks[event] { groups = existing }
            groups.append(entry)
            hooks.set(event, .array(groups))
        }
        root.set("hooks", hooks)
        return root
    }

    /// 설정에서 랜턴 hook만 뺀 결과. 비게 된 이벤트·`hooks`도 지운다
    public static func removing(from root: OrderedJSON) -> OrderedJSON {
        var root = root
        guard case .object(let events)? = root["hooks"] else { return root }
        var hooks = OrderedJSON.object(events)
        for (event, value) in events {
            guard case .array(let groups) = value else { continue }
            let kept = groups.filter { !isLanternGroup($0) }
            if kept.count != groups.count {
                hooks.set(event, kept.isEmpty ? nil : .array(kept))
            }
        }
        if case .object(let remaining) = hooks, remaining.isEmpty {
            root.set("hooks", nil)
        } else {
            root.set("hooks", hooks)
        }
        return root
    }

    /// 랜턴이 듣는 이벤트마다 랜턴 hook이 들어 있는지
    public static func isInstalled(_ agent: AgentKind, in root: OrderedJSON) -> Bool {
        guard let hooks = root["hooks"] else { return false }
        return events(for: agent).allSatisfy { event in
            guard case .array(let groups)? = hooks[event] else { return false }
            return groups.contains(where: isLanternGroup)
        }
    }

    /// 이벤트 하나에라도 랜턴 hook이 들어 있는지
    public static func containsLanternHook(_ root: OrderedJSON) -> Bool {
        guard case .object(let events)? = root["hooks"] else { return false }
        return events.contains { _, value in
            guard case .array(let groups) = value else { return false }
            return groups.contains(where: isLanternGroup)
        }
    }

    private static func isLanternGroup(_ group: OrderedJSON) -> Bool {
        guard case .array(let handlers)? = group["hooks"] else { return false }
        return handlers.contains { handler in
            if case .string(let command)? = handler["command"] { return command.contains(marker) }
            return false
        }
    }

    /// 에이전트가 신호마다 실행하는 스크립트.
    ///
    /// 받은 JSON을 그대로 파일 하나로 남기고 바로 끝난다. 아무것도 출력하지 않는다
    /// (Claude Code의 `UserPromptSubmit`은 출력이 대화에 들어간다). 프로세스 번호는 시작 신호 때만 찾는다.
    /// 반쯤 쓴 파일을 앱이 읽지 않도록 임시 파일에 쓰고 이름을 바꾼다
    public static func hookScript() -> String {
        #"""
        #!/bin/sh
        # Lantern agent hook. Records each hook event as a file for the Lantern app. Prints nothing.
        agent="$1"
        dir="$HOME/Library/Application Support/Lantern/agent-events"
        payload=$(cat)
        [ -n "$payload" ] && [ -d "$dir" ] || exit 0
        pid=
        case "$payload" in
          *'"SessionStart"'*|*'"UserPromptSubmit"'*)
            p=$PPID
            for _ in 1 2 3 4 5 6; do
              [ "$p" -gt 1 ] 2>/dev/null || break
              case "$(/bin/ps -o comm= -p "$p" 2>/dev/null)" in
                */"$agent"|"$agent"|*/node|node) pid=$p; break ;;
              esac
              p=$(/bin/ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
            done
            ;;
        esac
        tmp="$dir/.$$.tmp"
        { printf '%s\n%s\n' "$agent" "$pid"; printf '%s' "$payload"; } > "$tmp" 2>/dev/null && mv -f "$tmp" "$dir/$agent-$$-${RANDOM:-0}.event" 2>/dev/null
        exit 0
        """#
    }
}

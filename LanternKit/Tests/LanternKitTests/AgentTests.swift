import Foundation
import LanternKit
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000)

private func event(_ kind: AgentHookEvent.Kind, at seconds: TimeInterval = 0, pid: Int32? = nil, session: String = "s1") -> AgentHookEvent {
    AgentHookEvent(agent: .claude, sessionID: session, kind: kind, agentPID: pid, receivedAt: start.addingTimeInterval(seconds))
}

private func alive(_: Int32, _: Date?) -> Bool { true }

private func status(_ tracker: AgentSessionTracker, at seconds: TimeInterval, isAlive: (Int32, Date?) -> Bool = alive) -> AgentSessionTracker.Status {
    guard let session = tracker.sessions.values.first else { return .done }
    return tracker.status(of: session, now: start.addingTimeInterval(seconds), isAlive: isAlive)
}

@Suite("hook 신호 읽기")
struct AgentHookEventTests {
    @Test("hook이 남긴 파일에서 에이전트·세션·이벤트를 읽는다") func parsesFile() throws {
        let contents = "claude\n4321\n{\"session_id\":\"abc\",\"hook_event_name\":\"PreToolUse\",\"tool_use_id\":\"t1\"}"
        let parsed = try #require(AgentHookEvent.parse(fileContents: contents, receivedAt: start))
        #expect(parsed.agent == .claude)
        #expect(parsed.sessionID == "abc")
        #expect(parsed.kind == .toolStart(id: "t1"))
        #expect(parsed.agentPID == 4321)
    }

    @Test("Stop의 백그라운드 작업 유무를 읽는다") func parsesBackgroundTasks() throws {
        let busy = "claude\n\n{\"session_id\":\"a\",\"hook_event_name\":\"Stop\",\"background_tasks\":[{\"id\":\"b1\"}]}"
        let idle = "codex\n\n{\"session_id\":\"a\",\"hook_event_name\":\"Stop\"}"
        #expect(try #require(AgentHookEvent.parse(fileContents: busy, receivedAt: start)).kind == .stop(hasBackgroundWork: true))
        let parsed = try #require(AgentHookEvent.parse(fileContents: idle, receivedAt: start))
        #expect(parsed.kind == .stop(hasBackgroundWork: false))
        #expect(parsed.agentPID == nil)
    }

    @Test("여러 줄로 된 JSON도 읽는다") func parsesMultilineJSON() {
        let contents = "codex\n7\n{\n  \"session_id\": \"x\",\n  \"hook_event_name\": \"UserPromptSubmit\"\n}"
        #expect(AgentHookEvent.parse(fileContents: contents, receivedAt: start)?.kind == .promptSubmit)
    }

    @Test("형식이 틀리면 버린다", arguments: ["", "claude\n1", "gemini\n\n{\"session_id\":\"a\",\"hook_event_name\":\"Stop\"}", "claude\n\nnot json", "claude\n\n{\"hook_event_name\":\"Stop\"}"])
    func rejectsMalformed(_ contents: String) {
        #expect(AgentHookEvent.parse(fileContents: contents, receivedAt: start) == nil)
    }
}

@Suite("에이전트 세션 판단")
struct AgentSessionTrackerTests {
    @Test("지시를 보내면 일하는 중, Stop이 오면 끝남") func promptThenStop() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        #expect(status(tracker, at: 10) == .working)
        tracker.apply(event(.stop(hasBackgroundWork: false), at: 20))
        #expect(status(tracker, at: 21) == .done)
    }

    @Test("끝 신호가 없어도 30분 동안 조용하면 끝난 것으로 본다 (Esc 중단)") func quietLimit() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        tracker.apply(event(.toolStart(id: "t1"), at: 5))
        tracker.apply(event(.toolEnd(id: "t1"), at: 10))
        #expect(status(tracker, at: 10 + 29 * 60) == .working)
        #expect(status(tracker, at: 10 + 30 * 60) == .done)
    }

    @Test("도구가 실행 중이면 신호가 없어도 3시간까지 기다린다 (긴 빌드)") func busyLimit() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        tracker.apply(event(.toolStart(id: "build"), at: 5))
        #expect(status(tracker, at: 30) == .working)
        #expect(status(tracker, at: 5 + 2 * 3600) == .runningCommand)
        #expect(status(tracker, at: 5 + 3 * 3600) == .done)
    }

    @Test("사용자 허락을 기다리면 도구가 시작됐어도 30분 기준을 쓴다") func permissionUsesQuietLimit() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        tracker.apply(event(.toolStart(id: "t1"), at: 5))
        tracker.apply(event(.permissionRequest, at: 6))
        #expect(status(tracker, at: 6 + 10 * 60) == .awaitingPermission)
        #expect(status(tracker, at: 6 + 30 * 60) == .done)
    }

    @Test("허락 요청 뒤 시작해 10초 넘게 사는 자식 프로세스가 있으면 명령 실행 중으로 본다") func permissionApprovedByChild() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit, pid: 42))
        tracker.apply(event(.toolStart(id: "build"), at: 5))
        tracker.apply(event(.permissionRequest, at: 6))
        let session = tracker.sessions.values.first!
        let now = start.addingTimeInterval(6 + 40 * 60)
        // 허락 뒤 8초에 시작한 빌드가 아직 돌고 있음
        let running = tracker.status(of: session, now: now, isAlive: alive, childStartTimes: { _ in [start.addingTimeInterval(14)] })
        #expect(running == .runningCommand)
        // 허락 요청 전부터 있던 프로세스(MCP 서버 등)는 세지 않는다
        let old = tracker.status(of: session, now: now, isAlive: alive, childStartTimes: { _ in [start.addingTimeInterval(-100)] })
        #expect(old == .done)
    }

    @Test("방금 생긴 짧은 프로세스는 허락받은 명령으로 보지 않는다") func shortLivedChildIgnored() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit, pid: 42))
        tracker.apply(event(.permissionRequest, at: 6))
        let session = tracker.sessions.values.first!
        let now = start.addingTimeInterval(6 + 31 * 60)
        let status = tracker.status(of: session, now: now, isAlive: alive, childStartTimes: { _ in [now.addingTimeInterval(-3)] })
        #expect(status == .done)
    }

    @Test("허락하면 다시 도구 실행 중으로 돌아간다") func permissionGranted() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        tracker.apply(event(.toolStart(id: "t1"), at: 5))
        tracker.apply(event(.permissionRequest, at: 6))
        tracker.apply(event(.other, at: 60))
        #expect(status(tracker, at: 60 + 40 * 60) == .runningCommand)
    }

    @Test("백그라운드 작업이 남은 Stop은 1시간까지 일하는 중") func backgroundWork() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        tracker.apply(event(.stop(hasBackgroundWork: true), at: 10))
        #expect(status(tracker, at: 10 + 50 * 60) == .runningCommand)
        #expect(status(tracker, at: 10 + 60 * 60) == .done)
        tracker.apply(event(.promptSubmit, at: 4000))
        tracker.apply(event(.stop(hasBackgroundWork: false), at: 4010))
        #expect(status(tracker, at: 4011) == .done)
    }

    @Test("도구 끝 신호가 먼저 처리돼도 실행 중으로 남지 않는다") func outOfOrderToolEvents() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        tracker.apply(event(.toolEnd(id: "t1"), at: 5))
        tracker.apply(event(.toolStart(id: "t1"), at: 5))
        #expect(status(tracker, at: 5 + 40 * 60) == .done)
    }

    @Test("응답이 끝난 뒤 늦게 온 도구 끝·서브에이전트 신호는 다시 일하는 중으로 돌리지 않는다") func lateEventsAfterStop() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        tracker.apply(event(.toolStart(id: "t1"), at: 5))
        tracker.apply(event(.stop(hasBackgroundWork: false), at: 10))
        tracker.apply(event(.toolEnd(id: "t1"), at: 11))
        tracker.apply(event(.subagentActivity, at: 12))
        #expect(status(tracker, at: 13) == .done)
    }

    @Test("에이전트 프로그램이 꺼지면 끝난 것으로 본다") func processGone() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit, pid: 99))
        #expect(status(tracker, at: 10, isAlive: { _, _ in false }) == .done)
        #expect(status(tracker, at: 10) == .working)
    }

    @Test("세션 종료 신호가 오면 세션을 지운다") func sessionEnd() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit))
        tracker.apply(event(.sessionEnd, at: 5))
        #expect(tracker.sessions.isEmpty)
    }

    @Test("세션마다 따로 판단한다") func multipleSessions() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit, session: "a"))
        tracker.apply(event(.promptSubmit, session: "b"))
        tracker.apply(event(.stop(hasBackgroundWork: false), at: 10, session: "a"))
        let active = tracker.activeSessions(now: start.addingTimeInterval(20), isAlive: alive)
        #expect(active.map(\.session.sessionID) == ["b"])
    }

    @Test("오래됐거나 프로세스가 사라진 세션은 정리한다") func prune() {
        var tracker = AgentSessionTracker()
        tracker.apply(event(.promptSubmit, pid: 1, session: "gone"))
        tracker.apply(event(.promptSubmit, session: "old"))
        tracker.apply(event(.promptSubmit, at: 3 * 3600, session: "fresh"))
        tracker.prune(now: start.addingTimeInterval(3 * 3600 + 1), isAlive: { pid, _ in pid != 1 })
        #expect(tracker.sessions.values.map(\.sessionID) == ["fresh"])
    }
}

@Suite("에이전트가 끝날 때까지")
struct AgentFinishWatchTests {
    private func shouldEnd(_ watch: inout AgentFinishWatch, working: Bool, at seconds: TimeInterval) -> Bool {
        watch.update(anyWorking: working, now: start.addingTimeInterval(seconds))
    }

    @Test("모두 끝나고 1분 뒤에 끈다") func endsAfterGrace() {
        var watch = AgentFinishWatch(startedAt: start)
        let whileWorking = shouldEnd(&watch, working: true, at: 10)
        let beforeGrace = shouldEnd(&watch, working: false, at: 69)
        let afterGrace = shouldEnd(&watch, working: false, at: 70)
        #expect(!whileWorking)
        #expect(!beforeGrace)
        #expect(afterGrace)
    }

    @Test("1분 안에 다시 일하면 이어진다") func resumesWithinGrace() {
        var watch = AgentFinishWatch(startedAt: start)
        _ = shouldEnd(&watch, working: true, at: 0)
        _ = shouldEnd(&watch, working: false, at: 30)
        let resumed = shouldEnd(&watch, working: true, at: 50)
        let shortlyAfter = shouldEnd(&watch, working: false, at: 100)
        #expect(!resumed)
        #expect(!shortlyAfter)
    }

    @Test("에이전트가 시작하길 30분까지 기다린다") func waitsForFirstWork() {
        var watch = AgentFinishWatch(startedAt: start)
        let waiting = shouldEnd(&watch, working: false, at: 29 * 60)
        #expect(!waiting)
        #expect(!watch.hasSeenWork)
        let gaveUp = shouldEnd(&watch, working: false, at: 30 * 60)
        #expect(gaveUp)
    }
}

@Suite("에이전트 설정 파일의 랜턴 hook")
struct AgentHookConfigTests {
    private let original = """
    {
      "model": "opus",
      "hooks": {
        "Stop": [
          {
            "hooks": [
              {
                "type": "command",
                "command": ": orca-agent-hook-form=1; true",
                "timeout": 10
              }
            ]
          }
        ]
      },
      "env": {
        "A": "가나다 \\"quoted\\" /path"
      }
    }

    """

    @Test("기존 hook은 두고 랜턴 hook을 이벤트마다 더한다") func installKeepsOthers() throws {
        let installed = AgentHookConfig.installing(.claude, into: try OrderedJSON.parse(original))
        #expect(installed["model"] == .string("opus"))
        #expect(AgentHookConfig.isInstalled(.claude, in: installed))
        guard case .array(let stop)? = installed["hooks"]?["Stop"],
              case .array(let prompt)? = installed["hooks"]?["UserPromptSubmit"] else {
            Issue.record("hooks가 배열이 아님")
            return
        }
        #expect(stop.count == 2)
        #expect(prompt.count == 1)
    }

    @Test("두 번 연결해도 하나만 남는다") func installIsIdempotent() throws {
        let twice = AgentHookConfig.installing(.codex, into: AgentHookConfig.installing(.codex, into: .object([])))
        guard case .array(let stop)? = twice["hooks"]?["Stop"] else {
            Issue.record("Stop이 배열이 아님")
            return
        }
        #expect(stop.count == 1)
    }

    @Test("해제하면 원래 파일과 글자 하나까지 같다") func removeRestoresOriginalText() throws {
        let root = try OrderedJSON.parse(original)
        #expect(root.formatted() == original)
        let roundTrip = AgentHookConfig.removing(from: AgentHookConfig.installing(.claude, into: root))
        #expect(roundTrip.formatted() == original)
        #expect(!AgentHookConfig.isInstalled(.claude, in: roundTrip))
    }

    @Test("랜턴 hook이 하나라도 있는지 안다 (백업을 덮어쓰지 않으려고)") func detectsAnyLanternHook() throws {
        let root = try OrderedJSON.parse(original)
        #expect(!AgentHookConfig.containsLanternHook(root))
        #expect(AgentHookConfig.containsLanternHook(AgentHookConfig.installing(.codex, into: root)))
    }

    @Test("랜턴 hook만 있던 설정은 해제하면 hooks 항목도 지운다") func removeDropsEmptyHooks() {
        let removed = AgentHookConfig.removing(from: AgentHookConfig.installing(.claude, into: .object([("model", .string("x"))])))
        #expect(removed == .object([("model", .string("x"))]))
    }

    @Test("연결해도 다른 항목의 순서와 모양은 그대로다") func installKeepsLayout() throws {
        let installed = AgentHookConfig.installing(.claude, into: try OrderedJSON.parse(original)).formatted()
        #expect(installed.hasPrefix("{\n  \"model\": \"opus\",\n  \"hooks\": {\n    \"Stop\": [\n"))
        #expect(installed.hasSuffix("  \"env\": {\n    \"A\": \"가나다 \\\"quoted\\\" /path\"\n  }\n}\n"))
    }

    @Test("스크립트가 없어도 hook 명령은 입력을 읽고 조용히 성공한다") func commandWithoutScript() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let result = try runShell(AgentHookConfig.command(for: .claude), home: home, input: "{\"a\":1}")
        #expect(result.status == 0)
        #expect(result.output.isEmpty)
    }

    @Test("hook 스크립트는 아무것도 출력하지 않고 읽을 수 있는 신호 파일을 남긴다") func scriptWritesEventFile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let scriptPath = AgentHookConfig.scriptPath(home: home.path)
        let eventsPath = AgentHookConfig.eventsDirectory(home: home.path)
        try FileManager.default.createDirectory(atPath: eventsPath, withIntermediateDirectories: true)
        try AgentHookConfig.hookScript().write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let payload = "{\"session_id\":\"s9\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"비밀 \\\"hook_event_name\\\": \\\"Stop\\\"\"}"
        let result = try runShell(AgentHookConfig.command(for: .codex), home: home.path, input: payload)
        #expect(result.status == 0)
        #expect(result.output.isEmpty)

        let files = try FileManager.default.contentsOfDirectory(atPath: eventsPath)
        #expect(files.count == 1)
        let file = try #require(files.first)
        #expect(file.hasPrefix("codex-") && file.hasSuffix(".event"))
        let contents = try String(contentsOfFile: "\(eventsPath)/\(file)", encoding: .utf8)
        let parsed = try #require(AgentHookEvent.parse(fileContents: contents, receivedAt: start))
        #expect(parsed.agent == .codex)
        #expect(parsed.sessionID == "s9")
        #expect(parsed.kind == .promptSubmit)
        // 질문 원문 같은 내용은 파일에 남기지 않는다
        #expect(!contents.contains("비밀"))
    }

    @Test("도구 번호와 백그라운드 작업 여부도 남긴다") func scriptKeepsIdsOnly() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let events = try installScript(home: home)
        _ = try runShell(AgentHookConfig.command(for: .claude), home: home.path,
                         input: "{\"session_id\":\"a\",\"hook_event_name\":\"PreToolUse\",\"tool_use_id\":\"t\\\"1\",\"tool_input\":{\"command\":\"cat secret.txt\"}}")
        _ = try runShell(AgentHookConfig.command(for: .claude), home: home.path,
                         input: "{\"session_id\":\"a\",\"hook_event_name\":\"Stop\",\"background_tasks\":[{\"id\":\"b\"}],\"last_assistant_message\":\"secret\"}")
        let kinds = try FileManager.default.contentsOfDirectory(atPath: events).sorted().map { name -> AgentHookEvent.Kind? in
            let text = try String(contentsOfFile: "\(events)/\(name)", encoding: .utf8)
            #expect(!text.contains("secret"))
            return AgentHookEvent.parse(fileContents: text, receivedAt: start)?.kind
        }
        #expect(kinds.contains(.toolStart(id: "t\"1")))
        #expect(kinds.contains(.stop(hasBackgroundWork: true)))
    }

    @Test("신호가 너무 많이 쌓여 있으면 더 쓰지 않는다") func scriptStopsWhenFull() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let events = try installScript(home: home)
        for index in 0..<AgentHookConfig.maxPendingEvents {
            FileManager.default.createFile(atPath: "\(events)/old-\(index).event", contents: nil)
        }
        _ = try runShell(AgentHookConfig.command(for: .codex), home: home.path,
                         input: "{\"session_id\":\"a\",\"hook_event_name\":\"Stop\"}")
        #expect(try FileManager.default.contentsOfDirectory(atPath: events).count == AgentHookConfig.maxPendingEvents)
    }

    /// 임시 HOME에 hook 스크립트와 신호 폴더를 만든다. 신호 폴더 경로를 돌려준다
    private func installScript(home: URL) throws -> String {
        let scriptPath = AgentHookConfig.scriptPath(home: home.path)
        let eventsPath = AgentHookConfig.eventsDirectory(home: home.path)
        try FileManager.default.createDirectory(atPath: eventsPath, withIntermediateDirectories: true)
        try AgentHookConfig.hookScript().write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        return eventsPath
    }

    @Test("신호 폴더가 없으면 아무것도 남기지 않는다") func scriptSkipsWithoutEventsDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let scriptPath = AgentHookConfig.scriptPath(home: home.path)
        try FileManager.default.createDirectory(atPath: (scriptPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try AgentHookConfig.hookScript().write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        let result = try runShell(AgentHookConfig.command(for: .claude), home: home.path, input: "{}")
        #expect(result.status == 0)
        #expect(!FileManager.default.fileExists(atPath: AgentHookConfig.eventsDirectory(home: home.path)))
    }

    private func runShell(_ command: String, home: String, input: String) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["HOME": home, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }
}

@Suite("순서를 지키는 JSON")
struct OrderedJSONTests {
    @Test("읽고 다시 쓰면 같은 글이 된다") func roundTrip() throws {
        let text = "{\n  \"b\": 1.50,\n  \"a\": [\n    true,\n    null,\n    {}\n  ],\n  \"c\": \"줄\\n바꿈\\t탭 😀\"\n}\n"
        #expect(try OrderedJSON.parse(text).formatted() == text)
    }

    @Test("\\u 표기와 서로게이트 짝을 읽는다") func unicodeEscapes() throws {
        #expect(try OrderedJSON.parse("\"\\uac00\\ud83d\\ude00\\/\"") == .string("가😀/"))
    }

    @Test("JSON이 아니면 오류", arguments: ["{", "{\"a\" 1}", "[1,]", "tru", "\"\u{01}\"", "{} x"])
    func rejectsInvalid(_ text: String) {
        #expect(throws: OrderedJSON.ParseError.self) { try OrderedJSON.parse(text) }
    }

    @Test("키를 바꾸면 그 자리, 새 키는 끝, nil이면 지운다") func setKeepsPosition() {
        var object = OrderedJSON.object([("a", .number("1")), ("b", .number("2"))])
        object.set("a", .number("9"))
        object.set("c", .null)
        object.set("b", nil)
        #expect(object == .object([("a", .number("9")), ("c", .null)]))
    }
}

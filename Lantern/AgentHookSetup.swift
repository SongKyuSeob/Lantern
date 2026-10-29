import Foundation
import LanternKit

/// Claude Code·Codex 설정 파일에 랜턴 hook을 연결하고 해제한다.
///
/// 다른 프로그램이 넣은 hook은 그대로 두고 랜턴 것만 넣고 뺀다. 고치기 전에 원래 파일을 `.lantern-backup`으로 남긴다.
@Observable
final class AgentHookSetup {
    enum Status: Equatable {
        /// 에이전트 프로그램 설정 폴더가 없음 (설치 안 된 것으로 본다)
        case programMissing
        case notConnected
        case connected
    }

    private(set) var statuses: [AgentKind: Status] = [:]
    private(set) var lastError: String?

    private let home = NSHomeDirectory()

    init() {
        refresh()
    }

    func status(of agent: AgentKind) -> Status {
        statuses[agent] ?? .programMissing
    }

    var hasAnyConnection: Bool {
        statuses.values.contains(.connected)
    }

    func refresh() {
        var result: [AgentKind: Status] = [:]
        for agent in AgentKind.allCases {
            var isDirectory: ObjCBool = false
            let directory = AgentHookConfig.configDirectory(for: agent, home: home)
            if !FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) || !isDirectory.boolValue {
                result[agent] = .programMissing
            } else if let root = try? readConfig(agent), AgentHookConfig.isInstalled(agent, in: root) {
                result[agent] = .connected
            } else {
                result[agent] = .notConnected
            }
        }
        statuses = result
    }

    func connect(_ agent: AgentKind) {
        update(agent) { AgentHookConfig.installing(agent, into: $0) }
    }

    func disconnect(_ agent: AgentKind) {
        update(agent) { AgentHookConfig.removing(from: $0) }
    }

    /// 연결된 에이전트가 있으면 hook 스크립트를 이번 버전 내용으로 다시 쓴다 (앱을 업데이트했을 때를 위해)
    func refreshScriptIfConnected() {
        guard hasAnyConnection else { return }
        try? installScript()
    }

    // MARK: - 내부

    private func update(_ agent: AgentKind, _ change: (OrderedJSON) -> OrderedJSON) {
        lastError = nil
        do {
            try installScript()
            let linkPath = AgentHookConfig.configPath(for: agent, home: home)
            // dotfiles 도구로 설정 파일을 심볼릭 링크해 둔 경우, 링크를 일반 파일로 덮지 않고 원본에 쓴다
            let path = URL(fileURLWithPath: linkPath).resolvingSymlinksInPath().path
            let root = try readConfig(agent)
            // 백업은 랜턴이 손대기 전 원본이어야 하므로, 랜턴 hook이 이미 들어 있는 파일로는 덮어쓰지 않는다.
            // 링크를 복사하면 같은 파일을 가리키는 링크가 될 뿐이라, 내용을 읽어 새 파일로 쓴다
            if FileManager.default.fileExists(atPath: path), !AgentHookConfig.containsLanternHook(root) {
                let original = try Data(contentsOf: URL(fileURLWithPath: path))
                try original.write(to: URL(fileURLWithPath: linkPath + ".lantern-backup"), options: .atomic)
            }
            // 키 순서와 모양을 지켜, 랜턴 hook 말고는 파일이 바뀌지 않게 쓴다
            try Data(change(root).formatted().utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch ConfigError.unreadable {
            lastError = "\(agent.displayName) 설정 파일을 읽을 수 없어서 건드리지 않았어요. 파일 내용을 확인해 주세요."
        } catch {
            lastError = "\(agent.displayName) 설정을 바꾸지 못했어요. \(error.localizedDescription)"
        }
        refresh()
    }

    private enum ConfigError: Error {
        case unreadable
    }

    /// 설정 파일 내용. 파일이 없으면 빈 설정, 있는데 JSON 객체가 아니면 오류 (사용자 파일을 망가뜨리지 않기 위해)
    private func readConfig(_ agent: AgentKind) throws -> OrderedJSON {
        let path = AgentHookConfig.configPath(for: agent, home: home)
        guard FileManager.default.fileExists(atPath: path) else { return .object([]) }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { throw ConfigError.unreadable }
        if text.allSatisfy(\.isWhitespace) { return .object([]) }
        guard let root = try? OrderedJSON.parse(text), case .object = root else { throw ConfigError.unreadable }
        return root
    }

    private func installScript() throws {
        let manager = FileManager.default
        let scriptPath = AgentHookConfig.scriptPath(home: home)
        try manager.createDirectory(atPath: (scriptPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try manager.createDirectory(atPath: AgentHookConfig.eventsDirectory(home: home), withIntermediateDirectories: true)
        try Data(AgentHookConfig.hookScript().utf8).write(to: URL(fileURLWithPath: scriptPath), options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
    }
}

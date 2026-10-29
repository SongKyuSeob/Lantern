import Foundation
import LanternKit

/// 뚜껑 모드 감시 작업(`LidModeWatchdog`)을 launchd에 등록하고 지운다.
final class WatchdogController {
    private let plistPath = LidModeWatchdog.plistPath(home: NSHomeDirectory())
    private let scriptPath = LidModeWatchdog.scriptPath(home: NSHomeDirectory())
    private let uid = getuid()

    private var domain: String { "gui/\(uid)" }

    /// 등록하고 launchd에 실제로 올라갔는지 확인한다. 실패하면 `false`
    /// (예: 시스템 설정에서 "랜턴 뚜껑 모드 감시"를 꺼 둔 경우)
    @discardableResult
    func register() -> Bool {
        guard let executablePath = Bundle.main.executablePath else { return false }
        do {
            let script = LidModeWatchdog.script(
                pid: ProcessInfo.processInfo.processIdentifier,
                executablePath: executablePath,
                scriptPath: scriptPath,
                plistPath: plistPath,
                uid: uid
            )
            try write(Data(script.utf8), to: scriptPath, permissions: 0o755)
            try write(LidModeWatchdog.plist(scriptPath: scriptPath), to: plistPath, permissions: 0o644)
        } catch {
            return false
        }
        // 이전 것이 남아 있으면 지우고 새로 올린다
        _ = ShellCommand.run("/bin/launchctl", ["bootout", "\(domain)/\(LidModeWatchdog.label)"])
        let bootstrap = ShellCommand.run("/bin/launchctl", ["bootstrap", domain, plistPath])
        let loaded = ShellCommand.run("/bin/launchctl", ["print", "\(domain)/\(LidModeWatchdog.label)"])
        guard bootstrap.status == 0, loaded.status == 0 else {
            unregister()
            return false
        }
        return true
    }

    /// 등록을 지운다. 등록돼 있지 않아도 괜찮다
    func unregister() {
        _ = ShellCommand.run("/bin/launchctl", ["bootout", "\(domain)/\(LidModeWatchdog.label)"])
        try? FileManager.default.removeItem(atPath: plistPath)
        try? FileManager.default.removeItem(atPath: scriptPath)
    }

    private func write(_ data: Data, to path: String, permissions: Int) throws {
        let manager = FileManager.default
        try manager.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
    }
}

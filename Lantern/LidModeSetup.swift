import Foundation
import LanternKit

/// 뚜껑 모드 권한(sudoers 규칙)을 설치·제거하고, 설치돼 있는지 확인한다.
///
/// 설치와 제거는 macOS 관리자 비밀번호 창을 거친다. 설치한 뒤에는 `sudo -n pmset ...`로
/// 허용된 세 명령만 비밀번호 없이 실행할 수 있다.
@Observable
final class LidModeSetup {
    enum Status {
        case unknown
        case installed
        case notInstalled
    }

    private(set) var status: Status = .unknown
    /// 마지막 설치·제거가 실패한 이유. 사용자가 비밀번호 창을 취소한 경우는 비워 둔다
    private(set) var lastError: String?

    /// 지금 규칙이 실제로 동작하는지 sudo에 물어본다.
    /// `sudo -l 명령`은 비밀번호가 필요한 관리자 규칙으로도 통과하므로, 규칙 목록에서 NOPASSWD 명령을 직접 찾는다.
    /// 비밀번호 없이 허용된 규칙이 하나도 없으면 sudo가 목록 대신 비밀번호를 요구해 실패한다
    func refresh() {
        let result = ShellCommand.run("/usr/bin/sudo", ["-n", "-l"])
        let installed = result.status == 0 && SudoListing.allowsLidModeCommands(in: result.output)
        status = installed ? .installed : .notInstalled
    }

    func install() {
        guard let contents = SudoersRule.contents(for: NSUserName()) else {
            lastError = "사용자 이름에 쓸 수 없는 글자가 있어 설치할 수 없어요."
            return
        }
        // 루트 권한으로 임시 파일을 만들어 내용을 쓰고, visudo 검사를 통과할 때만 제자리에 넣는다.
        // 사용자 폴더의 파일을 거치지 않으므로 검사와 설치 사이에 내용이 바뀔 수 없다
        let script = """
        set -e
        tmp=$(/usr/bin/mktemp /tmp/lantern-sudoers.XXXXXX)
        trap '/bin/rm -f "$tmp"' EXIT
        /bin/cat > "$tmp" <<'LANTERN_RULE'
        \(contents)LANTERN_RULE
        /usr/sbin/visudo -c -q -f "$tmp"
        /usr/bin/install -m 0440 -o root -g wheel "$tmp" \(SudoersRule.path)
        """
        runWithAdministratorPrivileges(script)
    }

    /// 뚜껑 모드를 먼저 끄고 규칙을 지운다
    func uninstall() {
        let script = """
        \(SudoersRule.pmsetPath) \(SudoersRule.Command.enableSleep.arguments.joined(separator: " "))
        /bin/rm -f \(SudoersRule.path)
        """
        runWithAdministratorPrivileges(script)
    }

    /// 규칙 없이 남아 있는 뚜껑 모드를 관리자 비밀번호로 끈다
    func restoreSleepWithAdministratorPrivileges() {
        let script = "\(SudoersRule.pmsetPath) \(SudoersRule.Command.enableSleep.arguments.joined(separator: " "))"
        runWithAdministratorPrivileges(script, prompt: "랜턴이 켜져 있는 뚜껑 모드를 끄려고 합니다.")
    }

    // MARK: - 내부

    private func runWithAdministratorPrivileges(_ script: String, prompt: String = "랜턴이 뚜껑 모드 권한을 바꾸려고 합니다.") {
        lastError = nil
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with prompt \"\(prompt)\" with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo, errorInfo[NSAppleScript.errorNumber] as? Int != Self.userCanceledError {
            lastError = errorInfo[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류"
        }
        refresh()
    }

    /// 비밀번호 창에서 취소를 누르면 나오는 AppleScript 오류 번호
    private static let userCanceledError = -128
}

/// 짧은 명령을 실행하고 끝날 때까지 기다린다
enum ShellCommand {
    struct Result {
        let status: Int32
        let output: String
    }

    static func run(_ path: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

import Foundation

/// 랜턴이 비정상적으로 꺼졌을 때 뚜껑 모드를 끄는 감시 작업 (launchd 사용자 에이전트).
///
/// 뚜껑을 닫아 둔 채 뚜껑 모드를 풀면 macOS는 스스로 잠들지 않으므로, 뚜껑이 닫혀 있으면 재운다.
/// 충전기와 외장 모니터가 모두 연결된 클램쉘 상태는 원래 깨어 있는 상황이라 그대로 둔다 (앱의 판단과 같음).
///
/// 뚜껑 모드를 켤 때 등록하고 끌 때 지운다. 랜턴 프로세스가 사라지면 `disablesleep 0`을 실행하고 스스로 지운다.
/// 맥이 강제로 꺼진 경우에도 다음 로그인 때 다시 실행되어 같은 일을 한다.
/// 사용자 권한으로만 돌고, 이미 허용된 pmset 명령 하나만 쓴다. 이 경로들은 sudoers에 넣지 않는다.
///
/// 시스템 설정의 "앱 백그라운드 활동"에는 실행 파일 이름이 보이므로, `/bin/sh -c` 대신
/// 이름 있는 스크립트 파일을 실행한다 ("sh"로 보이면 사용자가 무엇인지 알 수 없다)
public enum LidModeWatchdog {
    public static let label = "com.songkyuseob.lantern.watchdog"
    public static let scriptName = "랜턴 뚜껑 모드 감시"
    /// 랜턴이 살아 있는지 확인하는 간격(초)
    public static let checkInterval = 5

    public static func plistPath(home: String) -> String {
        "\(home)/Library/LaunchAgents/\(label).plist"
    }

    public static func scriptPath(home: String) -> String {
        "\(home)/Library/Application Support/Lantern/\(scriptName)"
    }

    /// 감시 스크립트.
    ///
    /// PID만 보면 재부팅 뒤 같은 번호를 다른 프로그램이 쓸 수 있으므로, 실행 파일 경로까지 같은지 확인한다
    public static func script(pid: Int32, executablePath: String, scriptPath: String, plistPath: String, uid: UInt32) -> String {
        """
        #!/bin/sh
        while [ "$(/bin/ps -p \(pid) -o comm= 2>/dev/null)" = \(shellQuoted(executablePath)) ]; do /bin/sleep \(checkInterval); done
        /usr/bin/sudo -n \(SudoersRule.pmsetPath) \(SudoersRule.Command.enableSleep.arguments.joined(separator: " "))
        /bin/rm -f \(shellQuoted(scriptPath)) \(shellQuoted(plistPath))
        if /usr/sbin/ioreg -r -c IOPMrootDomain -d 1 | /usr/bin/grep -q '"AppleClamshellState" = Yes'; then
          external=$(/usr/sbin/system_profiler SPDisplaysDataType 2>/dev/null | /usr/bin/awk \(shellQuoted(externalDisplayCounter)))
          if ! { \(SudoersRule.pmsetPath) -g batt | /usr/bin/grep -q "AC Power" && [ "${external:-0}" -gt 0 ]; }; then
            /usr/bin/sudo -n \(SudoersRule.pmsetPath) \(SudoersRule.Command.sleepNow.arguments.joined(separator: " "))
          fi
        fi
        /bin/launchctl bootout gui/\(uid)/\(label)

        """
    }

    /// `system_profiler SPDisplaysDataType` 출력에서 내장 화면이 아닌 화면 수를 세는 awk 프로그램.
    /// 화면마다 8칸 들여쓴 "이름:" 줄로 시작하고, 내장 화면에는 "Connection Type: Internal" 줄이 있다
    public static let externalDisplayCounter = #"/^        [^ ].*:$/ { if (n) e += !i; n = 1; i = 0; next } /Connection Type: Internal/ { i = 1 } END { if (n) e += !i; print e + 0 }"#

    /// launchd 등록 파일 내용
    public static func plist(scriptPath: String) throws -> Data {
        let dictionary: [String: Any] = [
            "Label": label,
            "ProgramArguments": [scriptPath],
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        return try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    /// 셸에서 글자 그대로 쓰이도록 작은따옴표로 감싼다
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

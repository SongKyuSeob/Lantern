import Foundation

/// 뚜껑 모드에 필요한 sudoers 규칙.
///
/// 이 규칙은 그 사용자 계정의 모든 프로그램이 쓸 수 있으므로, 인자까지 정확히 쓴 pmset 명령 세 개만 허용한다.
/// 사용자가 고칠 수 있는 스크립트 경로는 절대 넣지 않는다 (내용을 바꿔치기하면 루트 권한을 통째로 넘겨준다).
public enum SudoersRule {
    public static let path = "/etc/sudoers.d/lantern"
    public static let pmsetPath = "/usr/bin/pmset"

    /// 비밀번호 없이 실행할 수 있게 허용하는 pmset 인자
    public enum Command: CaseIterable, Sendable {
        case disableSleep
        case enableSleep
        case sleepNow

        public var arguments: [String] {
            switch self {
            case .disableSleep: ["-a", "disablesleep", "1"]
            case .enableSleep: ["-a", "disablesleep", "0"]
            case .sleepNow: ["sleepnow"]
            }
        }
    }

    /// 규칙 파일 내용. 사용자 이름이 안전하지 않으면 `nil`
    public static func contents(for userName: String) -> String? {
        guard isSafeUserName(userName) else { return nil }
        let commands = Command.allCases
            .map { ([pmsetPath] + $0.arguments).joined(separator: " ") }
            .joined(separator: ", ")
        return """
        # Lantern lid mode. Only these exact pmset commands may run without a password.
        # Remove with: sudo rm \(path)
        \(userName) ALL=(root) NOPASSWD: \(commands)

        """
    }

    /// macOS 계정 짧은 이름에 쓰는 글자(영문, 숫자, `_`, `.`, `-`)만 허용한다.
    /// 규칙 파일과 셸 명령에 그대로 들어가므로 공백·따옴표·특수 문자가 끼면 거부한다
    public static func isSafeUserName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, name.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        let firstAllowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
        return firstAllowed.contains(first) && name.unicodeScalars.allSatisfy(allowed.contains)
    }
}

/// `pmset -g` 출력 해석
public enum PmsetOutput {
    /// `SleepDisabled` 값. 줄이 없으면 `nil`
    public static func sleepDisabled(in output: String) -> Bool? {
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 2, fields[0] == "SleepDisabled" {
                return fields[1] == "1"
            }
        }
        return nil
    }
}

/// `sudo -n -l` 출력 해석
public enum SudoListing {
    /// 출력에 `NOPASSWD`로 허용된 명령 목록. 예: `(root) NOPASSWD: /usr/bin/pmset sleepnow, /usr/bin/pmset -a disablesleep 0`
    ///
    /// sudo는 긴 줄을 화면 폭에 맞춰 공백 자리에서 줄바꿈하므로, 공백과 줄바꿈을 한 칸으로 합친 뒤 읽는다
    public static func passwordlessCommands(in output: String) -> Set<String> {
        let text = output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var commands: Set<String> = []
        var searchStart = text.startIndex
        while let tagRange = text.range(of: "NOPASSWD:", range: searchStart..<text.endIndex) {
            searchStart = tagRange.upperBound
            // 다음 규칙 줄은 "(root)"처럼 실행 계정으로 시작한다
            let entryEnd = text.range(of: " (", range: tagRange.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
            for item in text[tagRange.upperBound..<entryEnd].split(separator: ",") {
                var command = item.trimmingCharacters(in: .whitespaces)
                // 뒤에 PASSWD: 태그가 오면 거기부터는 비밀번호가 필요한 명령
                if command.hasPrefix("PASSWD:") { break }
                // SETENV: 같은 다른 태그는 떼어 낸다
                while let colon = command.firstIndex(of: ":"),
                      !command[..<colon].contains(" "), !command[..<colon].contains("/") {
                    command = String(command[command.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                commands.insert(command)
            }
        }
        return commands
    }

    /// 랜턴이 쓰는 세 명령이 모두 비밀번호 없이 허용돼 있는지
    public static func allowsLidModeCommands(in output: String) -> Bool {
        let allowed = passwordlessCommands(in: output)
        return SudoersRule.Command.allCases.allSatisfy {
            allowed.contains(([SudoersRule.pmsetPath] + $0.arguments).joined(separator: " "))
        }
    }
}

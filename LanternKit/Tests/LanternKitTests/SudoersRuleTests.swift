import LanternKit
import Testing

@Suite("뚜껑 모드 sudoers 규칙")
struct SudoersRuleTests {
    @Test("정확한 pmset 명령 세 개만 허용한다") func allowsExactlyThreeCommands() throws {
        let contents = try #require(SudoersRule.contents(for: "alice"))
        let rule = try #require(contents.split(separator: "\n").first { !$0.hasPrefix("#") })
        #expect(rule == "alice ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset sleepnow")
    }

    @Test("규칙 파일은 줄바꿈으로 끝난다") func endsWithNewline() throws {
        let contents = try #require(SudoersRule.contents(for: "user"))
        #expect(contents.hasSuffix("\n"))
    }

    @Test("위험한 사용자 이름은 거부한다", arguments: ["", "a b", "root'", "a;rm", "ALL\nALL", "$(id)", "-user", "사용자", "ALL", "all"])
    func rejectsUnsafeUserNames(_ name: String) {
        #expect(SudoersRule.contents(for: name) == nil)
    }

    @Test("평범한 사용자 이름은 받는다", arguments: ["alice", "alice-kim", "john.doe", "_test1"])
    func acceptsNormalUserNames(_ name: String) {
        #expect(SudoersRule.isSafeUserName(name))
    }

    @Test("pmset -g 출력에서 SleepDisabled를 읽는다") func parsesSleepDisabled() {
        let on = "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n standby              1\n"
        let off = "System-wide power settings:\n SleepDisabled\t\t0\n"
        #expect(PmsetOutput.sleepDisabled(in: on) == true)
        #expect(PmsetOutput.sleepDisabled(in: off) == false)
        #expect(PmsetOutput.sleepDisabled(in: "Currently in use:\n standby 1") == nil)
    }
}

@Suite("sudo -l 출력 해석")
struct SudoListingTests {
    private let header = "User alice may run the following commands on mac:\n"

    @Test("세 명령이 NOPASSWD로 있으면 설치됨") func detectsInstalledRule() {
        let output = header + "    (ALL) ALL\n    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset sleepnow\n"
        #expect(SudoListing.allowsLidModeCommands(in: output))
    }

    @Test("화면 폭에 맞춰 줄바꿈된 실제 출력도 읽는다") func readsWrappedOutput() {
        let output = """
        Matching Defaults entries for alice on mac:
            env_reset, env_keep+=BLOCKSIZE, env_keep+="COLORFGBG COLORTERM",
            lecture_file=/etc/sudo_lecture, !log_allowed

        User alice may run the following commands on mac:
            (ALL) ALL
            (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a
                disablesleep 0, /usr/bin/pmset sleepnow
        """
        #expect(SudoListing.allowsLidModeCommands(in: output))
    }

    @Test("NOPASSWD 규칙 뒤에 다른 규칙이 이어져도 섞지 않는다") func stopsAtNextEntry() {
        let output = header + "    (root) NOPASSWD: /usr/bin/pmset sleepnow\n    (ALL) /bin/ls\n"
        #expect(SudoListing.passwordlessCommands(in: output) == ["/usr/bin/pmset sleepnow"])
    }

    @Test("관리자 기본 규칙(ALL)만 있으면 설치 안 됨") func adminRuleIsNotEnough() {
        #expect(!SudoListing.allowsLidModeCommands(in: header + "    (ALL) ALL\n"))
    }

    @Test("세 명령 중 하나라도 빠지면 설치 안 됨") func missingCommand() {
        let output = header + "    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset sleepnow\n"
        #expect(!SudoListing.allowsLidModeCommands(in: output))
    }

    @Test("PASSWD 태그 뒤의 명령은 비밀번호가 필요") func passwdTagStops() {
        let output = header + "    (root) NOPASSWD: /usr/bin/pmset sleepnow, PASSWD: /usr/bin/pmset -a disablesleep 1\n"
        #expect(SudoListing.passwordlessCommands(in: output) == ["/usr/bin/pmset sleepnow"])
    }

    @Test("다른 태그는 떼어 낸다") func stripsOtherTags() {
        let output = header + "    (root) NOPASSWD: SETENV: /usr/bin/pmset sleepnow\n"
        #expect(SudoListing.passwordlessCommands(in: output) == ["/usr/bin/pmset sleepnow"])
    }
}

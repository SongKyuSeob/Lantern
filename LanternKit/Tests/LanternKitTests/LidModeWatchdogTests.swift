import Foundation
@testable import LanternKit
import Testing

@Suite("뚜껑 모드 감시 작업")
struct LidModeWatchdogTests {
    private let executable = "/Users/me/Library/Developer/Xcode/DerivedData/Lantern/Build/Products/Debug/Lantern.app/Contents/MacOS/Lantern"
    private let scriptPath = LidModeWatchdog.scriptPath(home: "/Users/me")
    private let plistPath = LidModeWatchdog.plistPath(home: "/Users/me")

    @Test("랜턴이 사라지면 뚜껑 모드를 끄고 스스로 지운다") func scriptSteps() {
        let script = LidModeWatchdog.script(pid: 4321, executablePath: executable, scriptPath: scriptPath, plistPath: plistPath, uid: 501)
        let lines = script.split(separator: "\n").map(String.init)
        #expect(lines.count == 5)
        #expect(lines[0] == "#!/bin/sh")
        #expect(lines[1].contains("/bin/ps -p 4321 -o comm="))
        #expect(lines[1].contains("/bin/sleep 5"))
        #expect(lines[2] == "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0")
        #expect(lines[3] == "/bin/rm -f '/Users/me/Library/Application Support/Lantern/랜턴 뚜껑 모드 감시' '\(plistPath)'")
        #expect(lines[4] == "/bin/launchctl bootout gui/501/com.songkyuseob.lantern.watchdog")
    }

    @Test("경로의 작은따옴표와 공백도 글자 그대로 넘긴다") func quotesPaths() {
        #expect(LidModeWatchdog.shellQuoted("/a b/it's") == "'/a b/it'\\''s'")
    }

    @Test("셸이 실제로 실행 파일 경로를 그대로 비교한다") func quotedPathRoundTrips() throws {
        let path = "/tmp/Personal Project/it's $HOME"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s \(LidModeWatchdog.shellQuoted(path))"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        #expect(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == path)
    }

    @Test("launchd는 이름 있는 감시 스크립트를 로그인 때도 실행한다") func plistContents() throws {
        let data = try LidModeWatchdog.plist(scriptPath: scriptPath)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == "com.songkyuseob.lantern.watchdog")
        #expect(plist["RunAtLoad"] as? Bool == true)
        #expect(plist["ProgramArguments"] as? [String] == [scriptPath])
    }
}

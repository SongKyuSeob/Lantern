import Foundation
@testable import LanternKit
import Testing

@Suite("뚜껑 모드 감시 작업")
struct LidModeWatchdogTests {
    private let executable = "/Users/me/Library/Developer/Xcode/DerivedData/Lantern/Build/Products/Debug/Lantern.app/Contents/MacOS/Lantern"
    private let scriptPath = LidModeWatchdog.scriptPath(home: "/Users/me")
    private let plistPath = LidModeWatchdog.plistPath(home: "/Users/me")

    @Test("랜턴이 사라지면 뚜껑 모드를 끄고, 뚜껑이 닫혀 있으면 재우고, 스스로 지운다") func scriptSteps() {
        let script = LidModeWatchdog.script(pid: 4321, executablePath: executable, scriptPath: scriptPath, plistPath: plistPath, uid: 501)
        let lines = script.split(separator: "\n").map(String.init)
        #expect(lines.first == "#!/bin/sh")
        #expect(lines[1].contains("/bin/ps -p 4321 -o comm="))
        #expect(lines[1].contains("/bin/sleep 5"))
        #expect(lines[2] == "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0")
        #expect(lines[3] == "/bin/rm -f '/Users/me/Library/Application Support/Lantern/랜턴 뚜껑 모드 감시' '\(plistPath)'")
        #expect(lines[4].contains("AppleClamshellState"))
        #expect(lines.contains { $0.trimmingCharacters(in: .whitespaces) == "/usr/bin/sudo -n /usr/bin/pmset sleepnow" })
        #expect(lines.last == "/bin/launchctl bootout gui/501/com.songkyuseob.lantern.watchdog")
        // 뚜껑 모드를 먼저 끄고 나서 재운다 (켜진 채로는 sleepnow가 먹지 않는다)
        let disable = script.range(of: "disablesleep 0")!.lowerBound
        let sleep = script.range(of: "pmset sleepnow")!.lowerBound
        #expect(disable < sleep)
    }

    @Test("내장 화면이 아닌 화면 수를 센다", arguments: [
        ("        Color LCD:\n          Display Type: Built-in\n          Connection Type: Internal\n        EDGE 27CH3:\n          Resolution: 1920 x 1080\n", "1"),
        ("        Color LCD:\n          Connection Type: Internal\n", "0"),
        ("        DELL U2720Q:\n          Online: Yes\n        LG HDR 4K:\n          Online: Yes\n", "2"),
        ("", "0"),
    ])
    func countsExternalDisplays(_ pair: (String, String)) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
        process.arguments = [LidModeWatchdog.externalDisplayCounter]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(pair.0.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == pair.1)
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

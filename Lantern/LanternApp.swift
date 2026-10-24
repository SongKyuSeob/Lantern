import AppKit
import LanternKit
import SwiftUI

@main
struct LanternApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("설정")
                .padding()
        }
    }
}

/// 메뉴바 아이콘은 `NSStatusItem`으로 직접 만든다 (왼쪽 클릭: 플로팅 창 활성/평소 전환, 오른쪽 클릭: 메뉴).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let powerMonitor = PowerStateMonitor()
    // 임시: 플로팅 창이 생기기 전까지 메뉴에서 판단 결과를 확인한다
    private let lidCloseItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "lamp.desk", accessibilityDescription: "랜턴")
        item.menu = makeMenu()
        statusItem = item

        updateLidCloseItem(powerMonitor.snapshot)
        powerMonitor.onChange = { [weak self] snapshot in
            self?.updateLidCloseItem(snapshot)
        }
        powerMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        powerMonitor.stop()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "랜턴 \(LanternKit.version)", action: nil, keyEquivalent: "")
        menu.addItem(lidCloseItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func updateLidCloseItem(_ snapshot: PowerSnapshot) {
        lidCloseItem.title = Self.lidCloseText(LidClosePrediction.outcome(for: snapshot))
    }

    private static func lidCloseText(_ outcome: LidCloseOutcome) -> String {
        switch outcome {
        case .noLid: "뚜껑이 없는 맥"
        case .staysAwake(.clamshell): "지금 뚜껑을 닫으면: 유지됨 (전원 · 외장 모니터 연결)"
        case .staysAwake(.lidMode): "지금 뚜껑을 닫으면: 유지됨 (뚜껑 모드)"
        case .sleeps(.noExternalDisplay): "지금 뚜껑을 닫으면: 잠듦 (외장 모니터 없음)"
        case .sleeps(.noPower): "지금 뚜껑을 닫으면: 잠듦 (전원 연결 안 됨)"
        case .sleeps(.noPowerAndNoExternalDisplay): "지금 뚜껑을 닫으면: 잠듦 (전원 · 외장 모니터 없음)"
        }
    }
}

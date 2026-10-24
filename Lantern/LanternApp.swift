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

/// 앱의 부품을 만들고 서로 연결한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let awake = AwakeController()
    private let power = PowerStateMonitor()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(awake: awake, power: power)
        power.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        power.stop()
        awake.stop()
    }
}

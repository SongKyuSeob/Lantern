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
    private let panelState = PanelState()
    private let lidMode = LidModeController(setup: LidModeSetup())
    private lazy var safety = SafetyController(awake: awake, power: power, lidMode: lidMode)
    private lazy var settings = SettingsWindowController(lidMode: lidMode, safety: safety)
    private var panel: FloatingPanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lidMode.onChange = { [weak self] isOn in self?.power.setLidModeOn(isOn) }
        power.onChange = { [weak self] _ in self?.safety.evaluate() }
        // 깨어 있기가 끝나면 뚜껑 모드를 먼저 끈다. 뚜껑이 닫혀 있었으면 세션이 다 정리된 뒤 재운다
        awake.onWillEnd = { [weak self] in
            guard let self, lidMode.isOn else { return }
            lidMode.disable()
            DispatchQueue.main.async { self.safety.sleepIfLidClosed() }
        }
        lidMode.setup.refresh()
        power.start()
        safety.start()

        let panel = FloatingPanelController(
            awake: awake, power: power, state: panelState,
            lidMode: lidMode, safety: safety,
            openSettings: { [weak self] in self?.settings.show() }
        )
        self.panel = panel
        statusItem = StatusItemController(awake: awake, lidMode: lidMode, safety: safety, panel: panel, settings: settings)
        panel.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        safety.appWillTerminate()
        power.stop()
        awake.stop()
    }
}

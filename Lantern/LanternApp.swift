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
    private let watchdog = WatchdogController()
    private let agentMonitor = AgentMonitor()
    private let agentHooks = AgentHookSetup()
    private let shortcuts = GlobalShortcutController()
    private lazy var agentAwake = AgentAwakeController(awake: awake, monitor: agentMonitor)
    private lazy var safety = SafetyController(awake: awake, power: power, lidMode: lidMode)
    private lazy var settings = SettingsWindowController(
        lidMode: lidMode, safety: safety, agentHooks: agentHooks, agentMonitor: agentMonitor, shortcuts: shortcuts
    )
    private var panel: FloatingPanelController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lidMode.onChange = { [weak self] isOn in
            self?.power.setLidModeOn(isOn)
            self?.watchdog.update(lidModeOn: isOn)
        }
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
        // 지난번에 남은 감시 작업이 있으면 정리한다
        if !lidMode.isOn { watchdog.unregister() }
        agentHooks.refreshScriptIfConnected()
        agentMonitor.onUpdate = { [weak self] in self?.agentAwake.update() }
        agentMonitor.start()
        agentAwake.start()

        let panel = FloatingPanelController(
            awake: awake, power: power, state: panelState,
            lidMode: lidMode, safety: safety,
            agentMonitor: agentMonitor, agentAwake: agentAwake,
            openSettings: { [weak self] in self?.settings.show() }
        )
        self.panel = panel
        shortcuts.onPress = { [weak self] in self?.panel?.toggleActive() }
        shortcuts.start()
        statusItem = StatusItemController(awake: awake, lidMode: lidMode, safety: safety, panel: panel, settings: settings)
        panel.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        safety.appWillTerminate()
        agentMonitor.stop()
        power.stop()
        awake.stop()
    }
}

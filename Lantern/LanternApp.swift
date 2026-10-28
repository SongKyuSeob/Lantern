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
    private let loginItem = LoginItemController()
    private let todoStore = AppDelegate.makeTodoStore()
    private lazy var agentAwake = AgentAwakeController(awake: awake, monitor: agentMonitor)
    private lazy var safety = SafetyController(awake: awake, power: power, lidMode: lidMode)
    private lazy var settings = SettingsWindowController(
        lidMode: lidMode, safety: safety, agentHooks: agentHooks, agentMonitor: agentMonitor,
        shortcuts: shortcuts, loginItem: loginItem
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
            todoStore: todoStore,
            openSettings: { [weak self] in self?.settings.show() }
        )
        self.panel = panel
        shortcuts.onPress = { [weak self] action in
            switch action {
            case .toggle: self?.panel?.toggleActive()
            case .hide: self?.panel?.toggleHidden()
            }
        }
        #if DEBUG
        observeDebugCommands()
        #endif
        shortcuts.start()
        loginItem.enableOnFirstLaunch()
        statusItem = StatusItemController(awake: awake, lidMode: lidMode, safety: safety, panel: panel, settings: settings)
        panel.show()
    }

    #if DEBUG
    private var debugObserver: NSObjectProtocol?

    /// 디버그 빌드에서만: `settings:<탭>`(설정 창 열기), `settingsSnapshot:<경로>`(설정 창을 PNG로 저장),
    /// `todoAdd:<제목>` · `todoDoneFirst` · `todoDeleteAll`(할 일 시험용), `tab:<todo|awake>`
    private func observeDebugCommands() {
        debugObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.songkyuseob.lantern.debug"), object: nil, queue: .main
        ) { [weak self] notification in
            guard let command = notification.object as? String else { return }
            MainActor.assumeIsolated {
                if command.hasPrefix("settings:") {
                    UserDefaults.standard.set(String(command.dropFirst("settings:".count)), forKey: "settings.tab")
                    self?.settings.show()
                } else if command.hasPrefix("settingsSnapshot:") {
                    self?.settings.snapshot(to: String(command.dropFirst("settingsSnapshot:".count)))
                } else if command.hasPrefix("todoAdd:") {
                    self?.todoStore.add(String(command.dropFirst("todoAdd:".count)))
                } else if command == "todoDoneFirst" {
                    if let first = self?.todoStore.openItems().first { self?.todoStore.setDone(first, true) }
                } else if command == "todoDeleteAll" {
                    guard let store = self?.todoStore else { return }
                    for item in store.openItems() + store.doneItems() { store.delete(item) }
                } else if command.hasPrefix("tab:") {
                    self?.panelState.tab = command.hasSuffix("todo") ? .todo : .awake
                }
            }
        }
    }
    #endif

    /// 할 일은 ~/Library/Application Support/Lantern/todos.store에 저장한다.
    /// 열지 못하면(파일 손상 등) 앱이 죽지 않도록 메모리에만 두고 시작한다
    private static func makeTodoStore() -> TodoStore {
        let directory = URL.applicationSupportDirectory.appending(path: "Lantern", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "todos.store")
        if let container = try? TodoStore.makeContainer(url: url) {
            return TodoStore(container: container)
        }
        return TodoStore(container: try! TodoStore.makeContainer(url: nil))
    }

    func applicationWillTerminate(_ notification: Notification) {
        safety.appWillTerminate()
        agentMonitor.stop()
        power.stop()
        awake.stop()
    }
}

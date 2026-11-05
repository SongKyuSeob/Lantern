import AppKit
import LanternKit
import SwiftUI
import UserNotifications

@main
struct LanternApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바 앱이라 창을 따로 띄우지 않는다. ⌘, 는 랜턴 설정 창을 연다
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "설정…")) { appDelegate.showSettings() }
                    .keyboardShortcut(",")
            }
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
    private let updates = UpdateController()
    private let todoStoreResult = AppDelegate.makeTodoStore()
    private var todoStore: TodoStore { todoStoreResult.store }
    private lazy var agentAwake = AgentAwakeController(awake: awake, monitor: agentMonitor)
    private lazy var safety = SafetyController(awake: awake, power: power, lidMode: lidMode)
    private lazy var settings = SettingsWindowController(
        lidMode: lidMode, safety: safety, agentHooks: agentHooks, agentMonitor: agentMonitor,
        shortcuts: shortcuts, loginItem: loginItem, updates: updates, panelState: panelState
    )
    private lazy var history = HistoryWindowController(todoStore: todoStore)
    private var panel: FloatingPanelController?
    /// 지금 깨어 있기 세션에서 뚜껑 닫아도 유지를 한 번이라도 켰는지 (기록용)
    private var lidModeUsedInSession = false
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // 화면 확인용: 창을 띄우지 않고 그림만 저장한 뒤 끈다 (마우스·키보드를 쓰지 않는다)
        if let directory = ProcessInfo.processInfo.environment["LANTERN_RENDER"] {
            renderSnapshots(to: directory)
            NSApp.terminate(nil)
            return
        }
        #endif
        lidMode.onChange = { [weak self] isOn in
            guard let self else { return }
            if isOn { lidModeUsedInSession = true }
            power.setLidModeOn(isOn)
            // 감시 작업이 없으면 앱이 갑자기 꺼졌을 때 뚜껑 모드가 남으므로, 등록하지 못하면 되돌린다
            if isOn, !watchdog.register() {
                lidMode.revertBecauseWatchdogFailed()
            } else if !isOn {
                watchdog.unregister()
            }
        }
        power.onChange = { [weak self] _ in self?.safety.evaluate() }
        lidMode.onAutomaticDisableFailed = { [weak self] in self?.safety.lidModeOffFailed() }
        // 끝난 깨어 있기는 기록 창에 남긴다
        awake.onDidEnd = { [weak self] session, reason in
            guard let self else { return }
            todoStore.recordAwake(
                session, endedAt: Date(), optionLabel: AwakeText.label(for: session.option),
                reason: reason, usedLidMode: lidModeUsedInSession
            )
            lidModeUsedInSession = lidMode.isOn
            // 깨어 있기가 끝난 뒤 설치하기로 한 업데이트가 있으면 이어서 설치한다 (랜턴을 끌 때는 제외)
            if reason != .appQuit { updates.awakeDidEnd() }
        }
        updates.isAwake = { [weak self] in self?.awake.isAwake ?? false }
        // 깨어 있기가 끝나면 뚜껑 모드를 먼저 끈다. 뚜껑이 닫혀 있었으면 세션이 다 정리된 뒤 재운다
        awake.onWillEnd = { [weak self] in
            guard let self, lidMode.isOn else { return }
            lidMode.disable()
            DispatchQueue.main.async { self.safety.sleepIfLidClosed() }
        }
        lidMode.setup.refresh()
        power.start()
        safety.start()
        if let warning = todoStoreResult.warning { Self.notify(warning) }
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
            todoStore: todoStore, updates: updates,
            openSettings: { [weak self] in self?.settings.show() },
            openHistory: { [weak self] in self?.history.show() }
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
        statusItem = StatusItemController(awake: awake, lidMode: lidMode, safety: safety, panel: panel, settings: settings, history: history, updates: updates)
        panel.show()
    }

    #if DEBUG
    /// 디버그 빌드에서만: 지금 언어로 주요 화면을 PNG로 저장한다 (`<폴더>/<언어>`). `LANTERN_RENDER=<폴더>`로 켜면 그리고 바로 끈다.
    /// 창을 화면에 띄우지 않아 포커스를 가져가지 않고, 실제 할 일 대신 시연 데이터를 쓴다
    private func renderSnapshots(to directory: String) {
        let defaults = UserDefaults.standard
        let savedSettingsTab = defaults.string(forKey: "settings.tab")
        // 그림을 그리느라 깨어 있기를 켜면 "마지막으로 쓴 옵션"이 바뀌므로 끝나면 되돌린다
        let savedLastOption = defaults.data(forKey: "awake.lastOption")
        // 그림용 창 상태는 실제 설정에 남지 않게 따로 둔다
        let scratchDomain = "com.songkyuseob.lantern.render"
        let scratch = UserDefaults(suiteName: scratchDomain) ?? .standard
        // 문구는 앱을 켤 때 고른 언어로 정해지므로, 언어마다 따로 실행한다 (`-AppleLanguages "(en)"`)
        for language in [Localization.language] {
            let folder = URL(fileURLWithPath: directory).appending(path: language.rawValue)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let store = DemoData.makeStore()
            let state = PanelState(defaults: scratch)

            func render(_ name: String, width: CGFloat, background: NSColor = .black, @ViewBuilder _ content: () -> some View) {
                let host = NSHostingView(rootView: content().frame(width: width).background(Color(nsColor: background)).environment(\.colorScheme, .dark))
                let size = host.fittingSize
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .darkAqua)
                window.backgroundColor = background
                window.contentView = host
                // 화면 밖 먼 곳에 올려야 그려진다. 키 창이 되지 않는 창이라 포커스는 가져가지 않는다
                window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
                window.orderFrontRegardless()
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                host.layoutSubtreeIfNeeded()
                host.writeSnapshot(to: folder.appending(path: "\(name).png").path)
                window.orderOut(nil)
            }
            func panel(_ name: String) {
                render(name, width: 300) {
                    PanelView(
                        awake: awake, power: power, state: state, lidMode: lidMode, safety: safety,
                        agentMonitor: agentMonitor, agentAwake: agentAwake, todoStore: store, updates: updates,
                        openSettings: {}, openHistory: {}
                    )
                }
            }

            state.isCollapsed = false
            state.mode = .active
            state.tab = .todo
            panel("panel-todo")
            state.tab = .awake
            panel("panel-awake-off")
            state.mode = .passive
            panel("passive-off")
            state.isCollapsed = true
            panel("compact-off")
            awake.start(.hours(2))
            state.isCollapsed = false
            panel("passive-on")
            state.isCollapsed = true
            panel("compact-on")
            state.isCollapsed = false
            state.mode = .active
            panel("panel-awake-on")
            state.isPickingTime = true
            panel("panel-awake-time")
            state.isPickingTime = false
            awake.stop()
            awake.start(.untilAgentsFinish)
            panel("panel-awake-agents")
            awake.stop()

            let item = store.openItems().first
            render("editor-note", width: 280, background: .darkGray) {
                TodoNoteEditor(title: item?.title ?? "", note: item?.note ?? "", onSave: { _ in }, onCancel: {})
            }
            render("editor-due", width: 260, background: .darkGray) {
                TodoDueEditor(title: item?.title ?? "", current: nil, onSave: { _ in }, onCancel: {})
            }
            render("history", width: 740, background: .windowBackgroundColor) {
                HistoryView().modelContainer(store.container).frame(height: 640)
            }
            for tab in SettingsView.Tab.allCases {
                defaults.set(tab.rawValue, forKey: "settings.tab")
                render("settings-\(tab.rawValue)", width: 520, background: .windowBackgroundColor) {
                    SettingsView(
                        lidMode: lidMode, safety: safety, agentHooks: agentHooks, agentMonitor: agentMonitor,
                        shortcuts: shortcuts, loginItem: loginItem, updates: updates, panelState: state
                    )
                    .frame(height: 620)
                }
            }
            let markdown = store.allItems().compactMap(\.completedAt).max().map { last in
                History.days(
                    todos: store.allItems().map { HistoryTodo(title: $0.title, isDone: $0.isDone, completedAt: $0.completedAt, hiddenAt: $0.hiddenAt, note: $0.note, dueDate: $0.dueDate) },
                    awake: store.awakeRecords().map { HistoryAwake(startedAt: $0.startedAt, endedAt: $0.endedAt, optionLabel: $0.optionLabel, usedLidMode: $0.usedLidMode) }
                )[Calendar.current.startOfDay(for: last)]
            }
            if let day = markdown ?? nil {
                try? History.markdown(for: day).write(to: folder.appending(path: "markdown.md"), atomically: true, encoding: .utf8)
            }
        }
        if let savedSettingsTab { defaults.set(savedSettingsTab, forKey: "settings.tab") } else { defaults.removeObject(forKey: "settings.tab") }
        if let savedLastOption { defaults.set(savedLastOption, forKey: "awake.lastOption") } else { defaults.removeObject(forKey: "awake.lastOption") }
        defaults.removePersistentDomain(forName: scratchDomain)
    }

    private var debugObserver: NSObjectProtocol?

    /// 디버그 빌드에서만: `settings:<탭>`(설정 창 열기), `settingsSnapshot:<경로>`(설정 창을 PNG로 저장),
    /// `todoAdd:<제목>` · `todoDoneFirst` · `todoDeleteAll`(할 일 시험용), `tab:<todo|awake>`, `checkForUpdates`(업데이트 확인)
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
                } else if command == "history" {
                    self?.history.show()
                } else if command.hasPrefix("historySnapshot:") {
                    self?.history.snapshot(to: String(command.dropFirst("historySnapshot:".count)))
                } else if command == "checkForUpdates" {
                    self?.updates.checkForUpdates()
                } else if command.hasPrefix("tab:") {
                    self?.panelState.tab = command.hasSuffix("todo") ? .todo : .awake
                }
            }
        }
    }
    #endif

    /// 할 일은 ~/Library/Application Support/Lantern/todos.store에 저장한다.
    /// 열지 못하면(파일 손상 등) 원래 파일을 옆에 보관하고 새로 만든다. 그것도 안 되면 메모리에만 두고 시작한다.
    /// 어느 경우든 사용자에게 알릴 문구를 함께 돌려준다
    private static func makeTodoStore() -> (store: TodoStore, warning: String?) {
        #if DEBUG
        if DemoData.isEnabled { return (DemoData.makeStore(), nil) }
        #endif
        let manager = FileManager.default
        let directory = URL.applicationSupportDirectory.appending(path: "Lantern", directoryHint: .isDirectory)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "todos.store")
        if let container = try? TodoStore.makeContainer(url: url) {
            return (TodoStore(container: container), nil)
        }
        // 못 연 파일은 지우지 않고 이름을 바꿔 보관한다 (SwiftData는 -shm, -wal 파일도 함께 쓴다)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let keptName = String(localized: "todos-열지 못함-\(stamp).store")
        for suffix in ["", "-shm", "-wal"] {
            let source = directory.appending(path: "todos.store\(suffix)")
            guard manager.fileExists(atPath: source.path) else { continue }
            try? manager.moveItem(at: source, to: directory.appending(path: keptName + suffix))
        }
        if let container = try? TodoStore.makeContainer(url: url) {
            return (TodoStore(container: container),
                    String(localized: "할 일 저장 파일을 열 수 없어서 새로 만들었어요. 원래 파일은 Application Support/Lantern 폴더에 \"\(keptName)\"로 보관했어요."))
        }
        let memory = TodoStore(container: try! TodoStore.makeContainer(url: nil))
        return (memory, String(localized: "할 일 저장 파일을 열 수 없어요. 이번에 적는 할 일은 랜턴을 끄면 사라져요."))
    }

    func showSettings() {
        settings.show()
    }

    private static func notify(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "랜턴")
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func applicationWillTerminate(_ notification: Notification) {
        safety.appWillTerminate()
        agentMonitor.stop()
        power.stop()
        awake.stop(reason: .appQuit)
    }
}

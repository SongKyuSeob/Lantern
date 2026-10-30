import AppKit
import LanternKit

/// 메뉴바 아이콘과 그 메뉴를 맡는다.
///
/// 왼쪽 클릭은 플로팅 창을 평소 ↔ 활성으로 바꾸고, 오른쪽 클릭은 메뉴를 연다.
/// 아이콘은 깨어 있기 상태에 따라 바뀌고, 메뉴는 열 때마다 지금 상태로 다시 그린다.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let awake: AwakeController
    private let lidMode: LidModeController
    private let safety: SafetyController
    private let panel: FloatingPanelController
    private let settings: SettingsWindowController
    private let history: HistoryWindowController
    private let updates: UpdateController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(
        awake: AwakeController,
        lidMode: LidModeController,
        safety: SafetyController,
        panel: FloatingPanelController,
        settings: SettingsWindowController,
        history: HistoryWindowController,
        updates: UpdateController
    ) {
        self.history = history
        self.updates = updates
        self.awake = awake
        self.lidMode = lidMode
        self.safety = safety
        self.panel = panel
        self.settings = settings
        super.init()
        menu.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
        observeAwakeState()
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            // 메뉴를 붙여 둔 채로 두면 왼쪽 클릭도 메뉴를 열기 때문에, 열 때만 잠깐 붙인다
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            panel.toggleActive()
        }
    }

    // MARK: - 아이콘

    private func updateIcon() {
        let name = lidMode.isOn ? "MenuBarLid" : awake.isAwake ? "MenuBarAwake" : "MenuBarOff"
        let image = NSImage(named: name)
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = image
        statusItem.button?.toolTip = lidMode.isOn ? "랜턴 · 뚜껑 닫아도 유지" : awake.isAwake ? "랜턴 · 깨어 있는 중" : "랜턴"
    }

    /// 깨어 있기·뚜껑 모드 상태가 바뀔 때마다 아이콘을 다시 그린다
    private func observeAwakeState() {
        withObservationTracking {
            _ = awake.isAwake
            _ = lidMode.isOn
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.observeAwakeState()
            }
        }
    }

    // MARK: - 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(statusText()))
        if awake.isAwake {
            menu.addItem(actionItem("깨어 있기 끄기", #selector(stopAwake)))
        } else {
            menu.addItem(actionItem("깨어 있기 시작 · \(AwakeText.label(for: awake.lastOption))", #selector(startWithLastOption)))
        }
        menu.addItem(durationMenuItem())
        if awake.remaining != nil {
            menu.addItem(extendMenuItem())
        }
        if let lidItem = lidModeMenuItem() {
            menu.addItem(lidItem)
        }
        if awake.isAwake {
            menu.addItem(actionItem("화면 끄기", #selector(turnOffDisplay)))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(panel.isVisible ? "창 숨기기" : "창 보이기", #selector(togglePanelVisibility)))
        menu.addItem(actionItem("기록 보기…", #selector(showHistory)))
        menu.addItem(actionItem("업데이트 확인…", #selector(checkForUpdates)))
        let settingsItem = actionItem("설정…", #selector(showSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "랜턴 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// "언제까지 ›" 하위 메뉴. 고르면 그 옵션으로 바로 시작한다
    private func durationMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "언제까지", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let selected = awake.current?.option ?? awake.lastOption
        for option in Self.menuOptions {
            let optionItem = actionItem(AwakeText.label(for: option), #selector(startOption(_:)))
            optionItem.representedObject = option
            optionItem.state = option == selected ? .on : .off
            submenu.addItem(optionItem)
        }
        let timeItem = actionItem("시각…", #selector(pickTime))
        if case .timeOfDay = selected { timeItem.state = .on }
        submenu.addItem(timeItem)
        item.submenu = submenu
        return item
    }

    /// "뚜껑 닫아도 유지" 항목. 뚜껑이 없는 맥이면 `nil`.
    /// 권한이 없으면 설정 창으로 보내고, 켤 수 없는 상태면 흐리게 둔다
    private func lidModeMenuItem() -> NSMenuItem? {
        guard PowerStateMonitor.readSnapshot().hasBuiltInDisplay else { return nil }
        if lidMode.setup.status == .notInstalled {
            return actionItem("뚜껑 닫아도 유지 설정…", #selector(showSettings))
        }
        let canEnable = lidMode.setup.status == .installed && awake.isAwake && safety.lidModeBlock == nil
        let item = NSMenuItem(title: "뚜껑 닫아도 유지", action: nil, keyEquivalent: "")
        if lidMode.isOn || canEnable {
            item.action = #selector(toggleLidMode)
            item.target = self
        }
        item.state = lidMode.isOn ? .on : .off
        return item
    }

    /// "연장 ›" 하위 메뉴. 끝 시각에 시간을 더한다
    private func extendMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "연장", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for extensionItem in AwakeText.extensions {
            let menuItem = actionItem(extensionItem.label, #selector(extend(_:)))
            menuItem.representedObject = extensionItem.interval
            submenu.addItem(menuItem)
        }
        item.submenu = submenu
        return item
    }

    private func statusText() -> String {
        guard let session = awake.current else { return "깨어 있기 꺼짐" }
        if lidMode.isOn {
            if let remaining = session.remaining(at: Date()) {
                return "뚜껑 닫아도 유지 · \(RemainingTimeFormat.string(from: remaining)) 남음"
            }
            return "뚜껑 닫아도 유지 · \(AwakeText.label(for: session.option))"
        }
        if let remaining = session.remaining(at: Date()) {
            return "깨어 있는 중 · \(RemainingTimeFormat.string(from: remaining)) 남음"
        }
        return "깨어 있는 중 · \(AwakeText.label(for: session.option))"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - 동작

    @objc private func startWithLastOption() { awake.startWithLastOption() }
    @objc private func stopAwake() { awake.stop() }
    @objc private func turnOffDisplay() { awake.turnOffDisplay() }
    @objc private func pickTime() { panel.showTimePicker() }
    @objc private func showSettings() { settings.show() }
    @objc private func showHistory() { history.show() }
    @objc private func checkForUpdates() { updates.checkForUpdates() }

    @objc private func toggleLidMode() {
        if lidMode.isOn { lidMode.disable(interactive: true) } else { lidMode.enable() }
    }

    @objc private func togglePanelVisibility() {
        if panel.isVisible { panel.hide() } else { panel.show() }
    }

    @objc private func extend(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        awake.extend(by: interval)
    }

    @objc private func startOption(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? AwakeOption else { return }
        awake.start(option)
    }

    // MARK: - 문구

    /// 메뉴에서 바로 고를 수 있는 옵션. "시각…"은 플로팅 창에서 고른다
    private static let menuOptions: [AwakeOption] = [.indefinite, .hours(1), .hours(2), .untilAgentsFinish]
}

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
        statusItem.button?.toolTip = lidMode.isOn ? L("랜턴 · 뚜껑 닫아도 유지", "Lantern · Closed-Lid Mode") : awake.isAwake ? L("랜턴 · 깨어 있는 중", "Lantern · Awake") : L("랜턴", "Lantern")
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
            menu.addItem(actionItem(L("깨어 있기 끄기", "Turn Off Keep Awake"), #selector(stopAwake)))
        } else {
            menu.addItem(actionItem(L("깨어 있기 시작", "Keep Awake") + " · \(AwakeText.label(for: awake.lastOption))", #selector(startWithLastOption)))
        }
        menu.addItem(durationMenuItem())
        if awake.remaining != nil {
            menu.addItem(extendMenuItem())
        }
        if let lidItem = lidModeMenuItem() {
            menu.addItem(lidItem)
        }
        if awake.isAwake {
            menu.addItem(actionItem(L("화면 끄기", "Turn Display Off"), #selector(turnOffDisplay)))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(panel.isVisible ? L("창 숨기기", "Hide Window") : L("창 보이기", "Show Window"), #selector(togglePanelVisibility)))
        let compactItem = actionItem(L("한 줄로 보기", "Single-Line View"), #selector(toggleCompact))
        compactItem.state = panel.isCompact ? .on : .off
        menu.addItem(compactItem)
        menu.addItem(actionItem(L("기록 보기…", "Show History…"), #selector(showHistory)))
        menu.addItem(actionItem(L("업데이트 확인…", "Check for Updates…"), #selector(checkForUpdates)))
        let settingsItem = actionItem(L("설정…", "Settings…"), #selector(showSettings))
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: L("랜턴 종료", "Quit Lantern"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// "언제까지 ›" 하위 메뉴. 고르면 그 옵션으로 바로 시작한다
    private func durationMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("언제까지", "Until"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let selected = awake.current?.option ?? awake.lastOption
        for option in Self.menuOptions {
            let optionItem = actionItem(AwakeText.label(for: option), #selector(startOption(_:)))
            optionItem.representedObject = option
            optionItem.state = option == selected ? .on : .off
            submenu.addItem(optionItem)
        }
        let timeItem = actionItem(L("시각…", "Time…"), #selector(pickTime))
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
            return actionItem(L("뚜껑 닫아도 유지 설정…", "Set Up Closed-Lid Mode…"), #selector(showSettings))
        }
        let canEnable = lidMode.setup.status == .installed && awake.isAwake && safety.lidModeBlock == nil
        let item = NSMenuItem(title: L("뚜껑 닫아도 유지", "Closed-Lid Mode"), action: nil, keyEquivalent: "")
        if lidMode.isOn || canEnable {
            item.action = #selector(toggleLidMode)
            item.target = self
        }
        item.state = lidMode.isOn ? .on : .off
        return item
    }

    /// "연장 ›" 하위 메뉴. 끝 시각에 시간을 더한다
    private func extendMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: L("연장", "Extend"), action: nil, keyEquivalent: "")
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
        guard let session = awake.current else { return L("깨어 있기 꺼짐", "Keep Awake off") }
        if lidMode.isOn {
            if let remaining = session.remaining(at: Date()) {
                return L("뚜껑 닫아도 유지 · \(RemainingTimeFormat.string(from: remaining)) 남음", "Closed-Lid Mode · \(RemainingTimeFormat.string(from: remaining)) left")
            }
            return L("뚜껑 닫아도 유지", "Closed-Lid Mode") + " · \(AwakeText.label(for: session.option))"
        }
        if let remaining = session.remaining(at: Date()) {
            return L("깨어 있는 중 · \(RemainingTimeFormat.string(from: remaining)) 남음", "Awake · \(RemainingTimeFormat.string(from: remaining)) left")
        }
        return L("깨어 있는 중", "Awake") + " · \(AwakeText.label(for: session.option))"
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

    @objc private func toggleCompact() { panel.isCompact.toggle() }

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

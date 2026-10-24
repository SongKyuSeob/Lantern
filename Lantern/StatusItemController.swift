import AppKit
import LanternKit

/// 메뉴바 아이콘과 그 메뉴를 맡는다.
///
/// 아이콘은 깨어 있기 상태에 따라 바뀌고, 메뉴는 열 때마다 지금 상태로 다시 그린다.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let awake: AwakeController
    private let power: PowerStateMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    init(awake: AwakeController, power: PowerStateMonitor) {
        self.awake = awake
        self.power = power
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        observeAwakeState()
    }

    // MARK: - 아이콘

    private func updateIcon() {
        let name = awake.isAwake ? "MenuBarAwake" : "MenuBarOff"
        let image = NSImage(named: name)
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = image
        statusItem.button?.toolTip = awake.isAwake ? "랜턴 · 깨어 있는 중" : "랜턴"
    }

    /// 깨어 있기 상태가 바뀔 때마다 아이콘을 다시 그린다
    private func observeAwakeState() {
        withObservationTracking {
            _ = awake.isAwake
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
            menu.addItem(actionItem("깨어 있기 시작 · \(Self.label(for: awake.lastOption))", #selector(startWithLastOption)))
        }
        menu.addItem(durationMenuItem())

        menu.addItem(.separator())
        menu.addItem(disabledItem(Self.lidCloseText(LidClosePrediction.outcome(for: power.snapshot))))
        if awake.isAwake {
            menu.addItem(actionItem("화면 끄기", #selector(turnOffDisplay)))
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "랜턴 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// "언제까지 ›" 하위 메뉴. 고르면 그 옵션으로 바로 시작한다
    private func durationMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "언제까지", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let selected = awake.current?.option ?? awake.lastOption
        for option in Self.menuOptions {
            let optionItem = actionItem(Self.label(for: option), #selector(startOption(_:)))
            optionItem.representedObject = option
            optionItem.state = option == selected ? .on : .off
            submenu.addItem(optionItem)
        }
        item.submenu = submenu
        return item
    }

    private func statusText() -> String {
        guard let session = awake.current else { return "깨어 있기 꺼짐" }
        if let remaining = session.remaining(at: Date()) {
            return "깨어 있는 중 · \(RemainingTimeFormat.string(from: remaining)) 남음"
        }
        return "깨어 있는 중 · \(Self.label(for: session.option))"
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

    @objc private func startOption(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? AwakeOption else { return }
        awake.start(option)
    }

    // MARK: - 문구

    /// 메뉴에서 바로 고를 수 있는 옵션. "시각…"은 플로팅 창(4단계)에서 고른다
    private static let menuOptions: [AwakeOption] = [.indefinite, .hours(1), .hours(2)]

    static func label(for option: AwakeOption) -> String {
        switch option {
        case .indefinite: "계속"
        case .hours(let hours): "\(hours)시간"
        case .timeOfDay(let hour, let minute): "\(hour < 12 ? "오전" : "오후") \(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute))까지"
        case .untilAgentsFinish: "에이전트가 끝날 때까지"
        }
    }

    static func lidCloseText(_ outcome: LidCloseOutcome) -> String {
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

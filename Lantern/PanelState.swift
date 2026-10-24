import Foundation

/// 플로팅 창이 지금 어떤 모습인지.
@Observable
final class PanelState {
    enum Mode {
        /// 반투명, 클릭이 뒤로 통과하는 보기 전용 상태
        case passive
        /// 불투명, 조작할 수 있는 상태
        case active
    }

    enum Tab: String {
        case todo
        case awake
    }

    var mode: Mode = .passive
    /// 시각을 고르는 중. 이때는 10초 무조작으로 평소 상태로 돌아가지 않는다
    var isPickingTime = false

    var isCollapsed: Bool {
        didSet { defaults.set(isCollapsed, forKey: Self.collapsedKey) }
    }

    var tab: Tab {
        didSet { defaults.set(tab.rawValue, forKey: Self.tabKey) }
    }

    private let defaults: UserDefaults
    private static let collapsedKey = "panel.isCollapsed"
    private static let tabKey = "panel.tab"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCollapsed = defaults.bool(forKey: Self.collapsedKey)
        // 할 일 탭은 M4에서 채우므로, 그 전까지는 깨어 있기 탭으로 시작한다
        tab = defaults.string(forKey: Self.tabKey).flatMap(Tab.init) ?? .awake
    }
}

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
    /// 할 일을 입력·수정하는 중. 이때도 10초 무조작·Esc로 닫지 않는다
    var isEditingText = false
    /// 아직 Enter를 누르지 않은 새 할 일. 창이 평소 상태로 바뀌거나 탭을 옮겨도 남아 있게 여기에 둔다
    var todoDraft = ""

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
        // 처음에는 메인 기능인 할 일 탭, 그 뒤로는 마지막에 본 탭
        tab = defaults.string(forKey: Self.tabKey).flatMap(Tab.init) ?? .todo
    }
}

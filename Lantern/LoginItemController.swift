import Foundation
import ServiceManagement

/// 로그인할 때 랜턴을 자동으로 여는 설정 (`SMAppService.mainApp`).
///
/// 처음 실행할 때 한 번 켜 두고, 그 뒤로는 사용자가 설정에서 끈 것을 존중한다.
/// 디버그 빌드는 Xcode 빌드 폴더의 앱이 로그인 항목에 들어가지 않도록 자동으로 켜지 않는다.
@Observable
final class LoginItemController {
    enum Status: Equatable {
        case enabled
        case disabled
        /// 시스템 설정에서 사용자가 허용해야 함
        case requiresApproval
    }

    private(set) var status: Status = .disabled
    private(set) var lastError: String?

    private let defaults: UserDefaults
    private static let didAutoEnableKey = "loginItem.didAutoEnable"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
    }

    /// 처음 실행이면 로그인 항목에 넣는다
    func enableOnFirstLaunch() {
        #if DEBUG
        return
        #else
        guard !defaults.bool(forKey: Self.didAutoEnableKey) else { return }
        defaults.set(true, forKey: Self.didAutoEnableKey)
        if status == .disabled { setEnabled(true) }
        #endif
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: status = .enabled
        case .requiresApproval: status = .requiresApproval
        default: status = .disabled
        }
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = enabled ? "로그인 항목에 넣지 못했어요. \(error.localizedDescription)" : "로그인 항목에서 빼지 못했어요. \(error.localizedDescription)"
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

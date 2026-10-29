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
        guard !defaults.bool(forKey: Self.didAutoEnableKey), Self.isInstalledLocation else { return }
        if status == .disabled { setEnabled(true) }
        // 성공했을 때만 끝난 것으로 기록한다 (실패하면 다음 실행 때 다시 시도)
        if status != .disabled { defaults.set(true, forKey: Self.didAutoEnableKey) }
        #endif
    }

    /// 응용 프로그램 폴더에서 실행 중인지. 다운로드 폴더에서 바로 열면 macOS가 임시 경로(App Translocation)에서
    /// 실행해서, 그 경로가 로그인 항목에 들어가면 다음 로그인 때 열리지 않는다
    private static var isInstalledLocation: Bool {
        let path = Bundle.main.bundlePath
        return !path.contains("/AppTranslocation/")
            && (path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/"))
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

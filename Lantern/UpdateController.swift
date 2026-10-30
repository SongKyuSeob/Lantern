import AppKit
import Sparkle

/// 자동 업데이트(Sparkle).
///
/// 하루 한 번 조용히 새 버전을 확인만 하고, 있으면 창을 띄우지 않고 `availableVersion`에 담아 플로팅 창에 작게 보여 준다.
/// 설치는 사용자가 그 표시나 "업데이트 확인…"을 눌렀을 때 Sparkle 창에서 하고, 몰래 설치하지 않는다.
/// 업데이트 파일은 EdDSA 키로 서명돼 있어야 받는다 (공개 키는 `Config/Lantern-Info.plist`).
@Observable
final class UpdateController: NSObject {
    /// 설치할 수 있는 새 버전 ("0.3.0"). 건너뛰거나 새 버전이 없다고 확인되면 nil
    private(set) var availableVersion: String?
    /// 깨어 있기가 끝나면 설치하려고 기다리는 중
    private(set) var installsAfterAwake = false
    /// 설정 창 "업데이트 자동으로 확인"
    var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    /// 깨어 있는지. 깨어 있는 동안에는 재시작 전에 한 번 묻는다
    @ObservationIgnored var isAwake: () -> Bool = { false }

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    /// "깨어 있기가 끝난 뒤 설치"를 고른 업데이트. 깨어 있기가 끝나면 이어서 설치·재시작한다
    @ObservationIgnored private var pendingInstall: (() -> Void)? {
        didSet { installsAfterAwake = pendingInstall != nil }
    }
    private let defaults: UserDefaults

    /// 알림 표시를 다시 켰을 때도 남기려고 저장한다. 지금 버전보다 새것일 때만 보여 준다
    private static let availableVersionKey = "update.availableVersion"
    private static let availableBuildKey = "update.availableBuild"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticallyChecks = true
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        restoreAvailableVersion()
    }

    /// 지금 버전 ("0.3.0")
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// 사용자가 직접 확인한다. 새 버전이 있으면 Sparkle 창(바뀐 내용·설치), 없으면 "최신 버전" 창이 뜬다.
    /// 건너뛴 버전도 다시 보여 준다
    func checkForUpdates() {
        // 깨어 있기가 끝나길 기다리는 설치가 있으면, 지금 설치할지만 묻는다
        if let install = pendingInstall {
            guard confirmInstallNow() else { return }
            pendingInstall = nil
            install()
            return
        }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    /// 깨어 있기가 끝났다. 끝난 뒤 설치하기로 한 업데이트가 있으면 지금 설치·재시작한다
    func awakeDidEnd() {
        // 다른 옵션으로 갈아 끼울 때도 앞 세션이 끝나므로, 정말 꺼졌는지 확인한 뒤에 설치한다
        DispatchQueue.main.async { [weak self] in
            guard let self, !isAwake(), let install = pendingInstall else { return }
            pendingInstall = nil
            install()
        }
    }

    private func setAvailable(_ item: SUAppcastItem?) {
        availableVersion = item?.displayVersionString
        if let item {
            defaults.set(item.displayVersionString, forKey: Self.availableVersionKey)
            defaults.set(item.versionString, forKey: Self.availableBuildKey)
        } else {
            defaults.removeObject(forKey: Self.availableVersionKey)
            defaults.removeObject(forKey: Self.availableBuildKey)
        }
    }

    private func restoreAvailableVersion() {
        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        guard let version = defaults.string(forKey: Self.availableVersionKey),
              let build = defaults.string(forKey: Self.availableBuildKey),
              build.compare(currentBuild, options: .numeric) == .orderedDescending
        else {
            // 이미 그 버전 이상으로 올라왔으면 지운다
            setAvailable(nil)
            return
        }
        availableVersion = version
    }

    /// 깨어 있는 동안 재시작하기 전에 묻는다. 지금 설치하면 true
    private func confirmInstallWhileAwake() -> Bool {
        let alert = NSAlert()
        alert.messageText = "지금 설치할까요?"
        alert.informativeText = "설치하면 랜턴이 다시 켜지면서 깨어 있기가 끝나요. \"끝난 뒤 설치\"를 고르면 깨어 있기가 끝날 때 저절로 설치해요."
        alert.addButton(withTitle: "끝난 뒤 설치")
        alert.addButton(withTitle: "지금 설치")
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// 깨어 있기가 끝나길 기다리는 설치를 지금 할지 묻는다. 지금 설치하면 true
    private func confirmInstallNow() -> Bool {
        let alert = NSAlert()
        alert.messageText = "지금 설치할까요?"
        alert.informativeText = "깨어 있기가 끝나면 \(availableVersion ?? "새 버전")을 설치하려고 기다리는 중이에요. 지금 설치하면 랜턴이 다시 켜지면서 깨어 있기가 끝나요."
        alert.addButton(withTitle: "그대로 두기")
        alert.addButton(withTitle: "지금 설치")
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// 설치를 미루면 Sparkle의 "설치 준비 완료" 창이 남는데, 그 창의 버튼은 다시 눌러도 반응이 없어서 숨긴다.
    /// 깨어 있기가 끝나면 창 없이 설치·재시작한다
    private func hideSparkleProgressWindow() {
        for window in NSApp.windows where window.isVisible {
            guard let windowController = window.windowController,
                  NSStringFromClass(type(of: windowController)) == "SUStatusController" else { continue }
            window.orderOut(nil)
        }
    }
}

// MARK: - Sparkle

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        // 건너뛰면 다음 버전이 나올 때까지 표시하지 않는다. 닫기만 했으면 표시를 그대로 둔다
        guard choice == .skip else { return }
        MainActor.assumeIsolated { setAvailable(nil) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { setAvailable(nil) }
    }

    nonisolated func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        // Sparkle은 이 메서드를 주 스레드에서 부른다
        nonisolated(unsafe) let installHandler = installHandler
        return MainActor.assumeIsolated {
            guard isAwake(), !confirmInstallWhileAwake() else { return false }
            pendingInstall = installHandler
            hideSparkleProgressWindow()
            return true
        }
    }
}

extension UpdateController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// 하루 한 번 확인에서 찾은 새 버전은 Sparkle 창을 띄우지 않고 우리가 작게 보여 준다
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated { setAvailable(update) }
    }
}

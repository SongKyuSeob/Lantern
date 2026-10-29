import Foundation
import LanternKit

/// 뚜껑 모드(`pmset -a disablesleep`)를 켜고 끈다.
///
/// 이 설정은 앱이 꺼져도 남기 때문에, 켜져 있는지는 랜턴이 기억하는 값이 아니라
/// `pmset -g`의 `SleepDisabled` 값으로 판단한다.
@Observable
final class LidModeController {
    private(set) var isOn = false
    /// 마지막으로 켜거나 끄지 못한 이유
    private(set) var lastError: String?
    /// 실제 상태가 바뀔 때 불린다
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    /// 사용자가 없을 때(세션 종료·안전장치·앱 종료) 끄지 못했을 때 불린다. 알림을 보내는 데 쓴다
    @ObservationIgnored var onAutomaticDisableFailed: (() -> Void)?

    let setup: LidModeSetup

    init(setup: LidModeSetup) {
        self.setup = setup
    }

    func refresh() {
        let result = ShellCommand.run(SudoersRule.pmsetPath, ["-g"])
        let value = PmsetOutput.sleepDisabled(in: result.output) ?? false
        guard value != isOn else { return }
        isOn = value
        onChange?(value)
    }

    func enable() {
        lastError = nil
        if !runPmset(.disableSleep) {
            lastError = "켜지 못했어요. 설정에서 권한을 확인해 주세요."
            setup.refresh()
        }
        refresh()
    }

    /// 끈다. `interactive`는 사용자가 직접 누른 경우로, 그때만 관리자 비밀번호 창으로 다시 시도한다.
    /// 자동으로 끄는 경로(세션 종료·안전장치·앱 종료)는 사람이 없을 수 있어 비밀번호 창을 띄우지 않고 알린다.
    /// 끄면 `true`
    @discardableResult
    func disable(interactive: Bool = false) -> Bool {
        lastError = nil
        if !runPmset(.enableSleep), interactive {
            // 권한 규칙이 지워진 뒤에도 남아 있으면 관리자 비밀번호를 받아서라도 원래대로 돌린다
            setup.restoreSleepWithAdministratorPrivileges()
        }
        refresh()
        guard isOn else { return true }
        lastError = "끄지 못했어요. 설정 → 전원에서 권한을 확인하거나, 터미널에서 sudo pmset -a disablesleep 0 을 실행해 주세요."
        if !interactive { onAutomaticDisableFailed?() }
        return false
    }

    /// 켠 직후 감시 작업을 등록하지 못하면 되돌린다 (앱이 갑자기 꺼졌을 때 뚜껑 모드가 남지 않게)
    func revertBecauseWatchdogFailed() {
        disable()
        lastError = "감시 작업을 등록하지 못해 켜지 않았어요. 시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램에서 \"랜턴 뚜껑 모드 감시\"가 허용돼 있는지 확인해 주세요."
    }

    /// 뚜껑 모드를 끄고 맥을 바로 재운다. 뚜껑 모드가 켜져 있으면 애플 메뉴의 잠자기도 먹지 않는다
    func sleepNow() {
        // 끄지 못하면 재워도 소용없다
        if isOn, !disable() { return }
        if !runPmset(.sleepNow) {
            _ = ShellCommand.run(SudoersRule.pmsetPath, SudoersRule.Command.sleepNow.arguments)
        }
    }

    /// 비밀번호 없이 허용된 pmset 명령을 실행한다. 규칙이 없으면 실패한다
    private func runPmset(_ command: SudoersRule.Command) -> Bool {
        ShellCommand.run("/usr/bin/sudo", ["-n", SudoersRule.pmsetPath] + command.arguments).status == 0
    }
}

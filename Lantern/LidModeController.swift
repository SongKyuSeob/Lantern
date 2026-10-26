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

    func disable() {
        lastError = nil
        if !runPmset(.enableSleep) {
            // 권한 규칙이 지워진 뒤에도 남아 있으면 관리자 비밀번호를 받아서라도 원래대로 돌린다
            setup.restoreSleepWithAdministratorPrivileges()
        }
        refresh()
        if isOn { lastError = "끄지 못했어요. 터미널에서 sudo pmset -a disablesleep 0 을 실행해 주세요." }
    }

    /// 뚜껑 모드를 끄고 맥을 바로 재운다. 뚜껑 모드가 켜져 있으면 애플 메뉴의 잠자기도 먹지 않는다
    func sleepNow() {
        if isOn { disable() }
        if !runPmset(.sleepNow) {
            _ = ShellCommand.run(SudoersRule.pmsetPath, SudoersRule.Command.sleepNow.arguments)
        }
    }

    /// 비밀번호 없이 허용된 pmset 명령을 실행한다. 규칙이 없으면 실패한다
    private func runPmset(_ command: SudoersRule.Command) -> Bool {
        ShellCommand.run("/usr/bin/sudo", ["-n", SudoersRule.pmsetPath] + command.arguments).status == 0
    }
}

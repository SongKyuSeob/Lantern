import LanternKit
import Testing

@Suite("뚜껑을 닫으면")
struct LidClosePredictionTests {
    private func outcome(power: Bool, external: Bool, builtIn: Bool = true, lidMode: Bool = false) -> LidCloseOutcome {
        LidClosePrediction.outcome(for: PowerSnapshot(
            isOnACPower: power, hasBuiltInDisplay: builtIn, hasExternalDisplay: external, isLidModeOn: lidMode
        ))
    }

    @Test("전원과 외장 모니터가 있으면 유지된다 (클램쉘)") func clamshellStaysAwake() {
        #expect(outcome(power: true, external: true) == .staysAwake(.clamshell))
    }

    @Test("전원만 있으면 잠든다") func powerOnlySleeps() {
        #expect(outcome(power: true, external: false) == .sleeps(.noExternalDisplay))
    }

    @Test("외장 모니터만 있으면 잠든다") func displayOnlySleeps() {
        #expect(outcome(power: false, external: true) == .sleeps(.noPower))
    }

    @Test("아무것도 없으면 잠든다") func nothingSleeps() {
        #expect(outcome(power: false, external: false) == .sleeps(.noPowerAndNoExternalDisplay))
    }

    @Test("뚜껑 모드가 켜져 있으면 환경과 상관없이 유지된다") func lidModeStaysAwake() {
        #expect(outcome(power: false, external: false, lidMode: true) == .staysAwake(.lidMode))
    }

    @Test("내장 화면이 없는 맥은 뚜껑이 없다") func desktopHasNoLid() {
        #expect(outcome(power: true, external: true, builtIn: false) == .noLid)
    }
}

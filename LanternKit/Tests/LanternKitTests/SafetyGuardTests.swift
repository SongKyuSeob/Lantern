import Foundation
import LanternKit
import Testing

@Suite("안전장치")
struct SafetyGuardTests {
    private func power(ac: Bool = false, battery: Int? = 50, lidMode: Bool = false) -> PowerSnapshot {
        PowerSnapshot(isOnACPower: ac, hasBuiltInDisplay: true, hasExternalDisplay: false, isLidModeOn: lidMode, batteryPercent: battery)
    }

    @Test("충전기 없이 기준에 닿으면 깨어 있기를 끈다") func lowBatteryEndsAwake() {
        var guardian = SafetyGuard(batteryThreshold: 20)
        #expect(guardian.evaluate(power: power(battery: 21), thermalState: .nominal, isAwake: true) == nil)
        #expect(guardian.evaluate(power: power(battery: 20), thermalState: .nominal, isAwake: true) == .endAwakeForLowBattery(percent: 20))
    }

    @Test("한 번 동작한 뒤 사용자가 다시 켜면 막지 않는다") func firesOncePerDrop() {
        var guardian = SafetyGuard(batteryThreshold: 20)
        _ = guardian.evaluate(power: power(battery: 20), thermalState: .nominal, isAwake: true)
        #expect(guardian.evaluate(power: power(battery: 19), thermalState: .nominal, isAwake: true) == nil)
    }

    @Test("충전기를 꽂았다 빼면 다시 동작한다") func rearmsAfterCharging() {
        var guardian = SafetyGuard(batteryThreshold: 20)
        _ = guardian.evaluate(power: power(battery: 20), thermalState: .nominal, isAwake: true)
        _ = guardian.evaluate(power: power(ac: true, battery: 19), thermalState: .nominal, isAwake: true)
        #expect(guardian.evaluate(power: power(battery: 19), thermalState: .nominal, isAwake: true) == .endAwakeForLowBattery(percent: 19))
    }

    @Test("기준 아래에서 깨어 있기를 새로 켜면 사용자 선택을 따른다") func startingBelowThresholdIsAllowed() {
        var guardian = SafetyGuard(batteryThreshold: 20)
        #expect(guardian.evaluate(power: power(battery: 15), thermalState: .nominal, isAwake: false) == nil)
        #expect(guardian.evaluate(power: power(battery: 15), thermalState: .nominal, isAwake: true) == nil)
    }

    @Test("충전 중이거나 배터리가 없는 맥은 배터리 기준을 쓰지 않는다") func ignoresBatteryWhenCharging() {
        var guardian = SafetyGuard(batteryThreshold: 20)
        #expect(guardian.evaluate(power: power(ac: true, battery: 5), thermalState: .nominal, isAwake: true) == nil)
        #expect(guardian.evaluate(power: power(battery: nil), thermalState: .nominal, isAwake: true) == nil)
    }

    @Test("뚜껑 모드 중 많이 뜨거우면 뚜껑 모드만 끈다", arguments: [ProcessInfo.ThermalState.serious, .critical])
    func heatDisablesLidMode(_ state: ProcessInfo.ThermalState) {
        var guardian = SafetyGuard(batteryThreshold: 20)
        #expect(guardian.evaluate(power: power(lidMode: true), thermalState: state, isAwake: true) == .disableLidModeForHeat)
    }

    @Test("조금 따뜻하거나 뚜껑 모드가 꺼져 있으면 발열 안전장치는 가만히 있는다") func mildHeatIsIgnored() {
        var guardian = SafetyGuard(batteryThreshold: 20)
        #expect(guardian.evaluate(power: power(lidMode: true), thermalState: .fair, isAwake: true) == nil)
        #expect(guardian.evaluate(power: power(lidMode: false), thermalState: .critical, isAwake: true) == nil)
    }

    @Test("기준 아래이거나 뜨거우면 뚜껑 모드를 켤 수 없다") func lidModeBlock() {
        let guardian = SafetyGuard(batteryThreshold: 20)
        #expect(guardian.lidModeBlock(power: power(battery: 20), thermalState: .nominal) == .lowBattery(threshold: 20))
        #expect(guardian.lidModeBlock(power: power(ac: true, battery: 20), thermalState: .nominal) == nil)
        #expect(guardian.lidModeBlock(power: power(battery: 80), thermalState: .serious) == .tooHot)
        #expect(guardian.lidModeBlock(power: power(battery: 80), thermalState: .fair) == nil)
    }
}

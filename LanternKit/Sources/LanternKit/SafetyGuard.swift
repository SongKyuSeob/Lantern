import Foundation

/// 안전장치가 해야 할 일
public enum SafetyAction: Equatable, Sendable {
    /// 배터리가 기준 아래로 내려감 → 깨어 있기(뚜껑 모드 포함)를 통째로 끈다
    case endAwakeForLowBattery(percent: Int)
    /// 맥이 너무 뜨거움 → 뚜껑 모드만 끈다. 깨어 있기는 유지한다
    case disableLidModeForHeat
}

/// 뚜껑 모드를 지금 켤 수 없는 이유
public enum LidModeBlock: Equatable, Sendable {
    case lowBattery(threshold: Int)
    case tooHot
}

/// 전원·발열 상태를 보고 안전장치를 동작시킬지 판단한다.
///
/// 배터리 기준은 충전기 없이 기준 %에 **닿는 순간** 한 번만 동작한다. 그 뒤에 사용자가 다시 켜면 그 선택을 따른다.
/// 충전기를 꽂거나 기준보다 높아지면 다시 동작할 준비를 한다.
/// 발열은 뚜껑 모드가 켜져 있는 동안 `.serious` 이상이면 매번 동작한다.
public struct SafetyGuard: Sendable {
    /// 이 % 이하가 되면 깨어 있기를 끈다
    public var batteryThreshold: Int
    private var isBatteryArmed = true

    public init(batteryThreshold: Int) {
        self.batteryThreshold = batteryThreshold
    }

    public mutating func evaluate(
        power: PowerSnapshot,
        thermalState: ProcessInfo.ThermalState,
        isAwake: Bool
    ) -> SafetyAction? {
        if isLowBattery(power) {
            if isBatteryArmed {
                isBatteryArmed = false
                if isAwake, let percent = power.batteryPercent {
                    return .endAwakeForLowBattery(percent: percent)
                }
            }
        } else {
            isBatteryArmed = true
        }

        if power.isLidModeOn, Self.isTooHot(thermalState) {
            return .disableLidModeForHeat
        }
        return nil
    }

    /// 뚜껑 모드를 켜지 못하게 막아야 하는 이유. 사용자가 기준 아래에서 깨어 있기를 다시 켜는 건 허용하지만,
    /// 뚜껑을 닫은 채 배터리가 바닥나지 않도록 뚜껑 모드는 막는다
    public func lidModeBlock(power: PowerSnapshot, thermalState: ProcessInfo.ThermalState) -> LidModeBlock? {
        if isLowBattery(power) { return .lowBattery(threshold: batteryThreshold) }
        if Self.isTooHot(thermalState) { return .tooHot }
        return nil
    }

    private func isLowBattery(_ power: PowerSnapshot) -> Bool {
        guard !power.isOnACPower, let percent = power.batteryPercent else { return false }
        return percent <= batteryThreshold
    }

    private static func isTooHot(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }
}

/// 뚜껑 닫힘 판단에 필요한 지금의 전원·화면 상태
public struct PowerSnapshot: Equatable, Sendable {
    /// 전원 어댑터로 전기를 받고 있는지
    public var isOnACPower: Bool
    /// 내장 화면이 있는지. 없으면 뚜껑이 없는 맥(Mac mini, iMac 등)이다
    public var hasBuiltInDisplay: Bool
    /// 외장 모니터가 연결돼 있는지
    public var hasExternalDisplay: Bool
    /// 뚜껑 닫아도 유지 모드가 켜져 있는지
    public var isLidModeOn: Bool
    /// 내장 배터리 잔량(%). 배터리가 없는 맥이면 `nil`
    public var batteryPercent: Int?

    public init(
        isOnACPower: Bool,
        hasBuiltInDisplay: Bool,
        hasExternalDisplay: Bool,
        isLidModeOn: Bool = false,
        batteryPercent: Int? = nil
    ) {
        self.isOnACPower = isOnACPower
        self.hasBuiltInDisplay = hasBuiltInDisplay
        self.hasExternalDisplay = hasExternalDisplay
        self.isLidModeOn = isLidModeOn
        self.batteryPercent = batteryPercent
    }
}

/// 지금 뚜껑을 닫으면 어떻게 되는지
public enum LidCloseOutcome: Equatable, Sendable {
    /// 뚜껑이 없는 맥
    case noLid
    case staysAwake(StayReason)
    case sleeps(SleepReason)

    public enum StayReason: Equatable, Sendable {
        /// 전원 + 외장 모니터 연결 (macOS 기본 클램쉘 모드)
        case clamshell
        /// 뚜껑 닫아도 유지 모드
        case lidMode
    }

    public enum SleepReason: Equatable, Sendable {
        case noPower
        case noExternalDisplay
        case noPowerAndNoExternalDisplay
    }
}

public enum LidClosePrediction {
    /// macOS 기본 동작 기준으로 뚜껑을 닫았을 때의 결과를 판단한다.
    ///
    /// 클램쉘 모드에서도 오래 손대지 않으면 잠드는 것은 막지 못한다. 그 부분은 깨어 있기 세션이 맡는다.
    public static func outcome(for snapshot: PowerSnapshot) -> LidCloseOutcome {
        guard snapshot.hasBuiltInDisplay else { return .noLid }
        if snapshot.isLidModeOn { return .staysAwake(.lidMode) }

        switch (snapshot.isOnACPower, snapshot.hasExternalDisplay) {
        case (true, true): return .staysAwake(.clamshell)
        case (true, false): return .sleeps(.noExternalDisplay)
        case (false, true): return .sleeps(.noPower)
        case (false, false): return .sleeps(.noPowerAndNoExternalDisplay)
        }
    }
}

import IOKit.pwr_mgt

/// 가만히 둬서 맥이 잠드는 것을 막는다 (`caffeinate -i`와 같은 방식).
///
/// 화면은 평소처럼 꺼진다. 권한이 필요 없고, 앱이 꺼지거나 죽으면 macOS가 자동으로 해제한다.
public final class IdleSleepBlocker {
    private var assertionID: IOPMAssertionID?

    public init() {}

    public var isActive: Bool { assertionID != nil }

    /// 막기 시작한다. 이미 막고 있으면 아무것도 하지 않는다. 실패하면 `false`
    @discardableResult
    public func activate(reason: String) -> Bool {
        guard assertionID == nil else { return true }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        return true
    }

    /// 막기를 그만둔다
    public func deactivate() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }

    deinit {
        if let assertionID { IOPMAssertionRelease(assertionID) }
    }
}

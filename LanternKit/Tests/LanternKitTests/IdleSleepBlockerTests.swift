import Foundation
import IOKit.pwr_mgt
import LanternKit
import Testing

@Suite("잠들지 않게 막기")
struct IdleSleepBlockerTests {
    /// 이 테스트 프로세스가 걸어 둔 요청 중 `reason` 이름을 가진 것이 있는지 macOS에 물어본다
    private func isRegistered(_ reason: String) -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
              let mine = byProcess[NSNumber(value: getpid())]
        else { return false }
        return mine.contains { $0[kIOPMAssertionNameKey] as? String == reason }
    }

    @Test("켜면 macOS에 등록되고, 끄면 사라진다") func activateAndDeactivate() {
        let reason = "랜턴 테스트 \(UUID().uuidString)"
        let blocker = IdleSleepBlocker()

        #expect(blocker.activate(reason: reason))
        #expect(blocker.isActive)
        #expect(isRegistered(reason))

        blocker.deactivate()
        #expect(!blocker.isActive)
        #expect(!isRegistered(reason))
    }
}

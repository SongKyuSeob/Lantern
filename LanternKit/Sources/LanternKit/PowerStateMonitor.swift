import CoreGraphics
import Foundation
import IOKit.ps

/// 전원 어댑터와 모니터 연결 상태를 읽고, 바뀌는 순간 알려 준다.
///
/// `start()` 뒤에는 어댑터를 꽂거나 뽑을 때, 모니터를 연결하거나 뺄 때 `onChange`가 불린다.
/// 다 쓰면 `stop()`을 불러 시스템 알림 등록을 해제한다.
@MainActor
public final class PowerStateMonitor {
    public private(set) var snapshot: PowerSnapshot
    public var onChange: ((PowerSnapshot) -> Void)?

    private var powerSource: CFRunLoopSource?
    private var isObservingDisplays = false

    public init() {
        snapshot = Self.readSnapshot()
    }

    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()

        if powerSource == nil,
           let source = IOPSNotificationCreateRunLoopSource({ context in
               PowerStateMonitor.scheduleRefresh(context)
           }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }

        if !isObservingDisplays {
            CGDisplayRegisterReconfigurationCallback(Self.displayCallback, context)
            isObservingDisplays = true
        }
    }

    public func stop() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
        if isObservingDisplays {
            // 해제할 때는 등록할 때와 같은 함수·context를 넘겨야 한다
            CGDisplayRemoveReconfigurationCallback(Self.displayCallback, Unmanaged.passUnretained(self).toOpaque())
            isObservingDisplays = false
        }
    }

    /// 모니터 구성이 바뀌기 시작할 때와 끝났을 때 두 번 불린다. 끝났을 때만 다시 읽는다
    private nonisolated static let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, context in
        guard !flags.contains(.beginConfigurationFlag) else { return }
        PowerStateMonitor.scheduleRefresh(context)
    }

    /// 시스템 알림은 C 함수로 들어오므로, 메인 스레드로 넘겨 상태를 다시 읽는다
    private nonisolated static func scheduleRefresh(_ context: UnsafeMutableRawPointer?) {
        guard let context else { return }
        let monitor = Unmanaged<PowerStateMonitor>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in monitor.refresh() }
    }

    private func refresh() {
        var latest = Self.readSnapshot()
        latest.isLidModeOn = snapshot.isLidModeOn
        guard latest != snapshot else { return }
        snapshot = latest
        onChange?(latest)
    }

    // MARK: - 시스템에서 읽기

    public static func readSnapshot() -> PowerSnapshot {
        let displays = onlineDisplays()
        return PowerSnapshot(
            isOnACPower: isOnACPower(),
            hasBuiltInDisplay: displays.contains { CGDisplayIsBuiltin($0) != 0 },
            hasExternalDisplay: displays.contains { CGDisplayIsBuiltin($0) == 0 }
        )
    }

    private static func isOnACPower() -> Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        return type == kIOPMACPowerKey
    }

    /// 연결된 모든 화면. 뚜껑이 닫혀 꺼진 내장 화면도 포함한다
    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}

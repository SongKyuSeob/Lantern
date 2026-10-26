import Foundation
import LanternKit
import UserNotifications

/// 배터리·발열 안전장치와, 앱을 켜고 끌 때 뚜껑 모드를 원래대로 돌리는 일을 맡는다.
///
/// - 충전기 없이 배터리가 기준 %에 닿으면 깨어 있기를 통째로 끈다 (뚜껑 모드도 함께 꺼진다)
/// - 뚜껑 모드 중 맥이 많이 뜨거우면 뚜껑 모드만 끈다
/// - 뚜껑이 닫혀 있었다면 바로 재운다. 이미 닫힌 뒤에 풀면 macOS는 스스로 잠들지 않는다 (2026-10-26 실기 확인)
/// - 안전장치가 동작할 때만 알림을 보낸다
@Observable
final class SafetyController {
    static let defaultBatteryThreshold = 20
    static let batteryThresholdRange = 5...50

    var batteryThreshold: Int {
        didSet {
            defaults.set(batteryThreshold, forKey: Self.batteryThresholdKey)
            guardian.batteryThreshold = batteryThreshold
            evaluate()
        }
    }
    private(set) var thermalState = ProcessInfo.processInfo.thermalState

    @ObservationIgnored private var guardian: SafetyGuard
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?
    private let awake: AwakeController
    private let power: PowerStateMonitor
    private let lidMode: LidModeController
    private let defaults: UserDefaults

    private static let batteryThresholdKey = "safety.batteryThreshold"

    init(awake: AwakeController, power: PowerStateMonitor, lidMode: LidModeController, defaults: UserDefaults = .standard) {
        self.awake = awake
        self.power = power
        self.lidMode = lidMode
        self.defaults = defaults
        let saved = defaults.object(forKey: Self.batteryThresholdKey) as? Int
        let threshold = saved.map { min(max($0, Self.batteryThresholdRange.lowerBound), Self.batteryThresholdRange.upperBound) }
            ?? Self.defaultBatteryThreshold
        batteryThreshold = threshold
        guardian = SafetyGuard(batteryThreshold: threshold)
    }

    /// 지금 뚜껑 모드를 켤 수 없는 이유
    var lidModeBlock: LidModeBlock? {
        guardian.lidModeBlock(power: power.snapshot, thermalState: thermalState)
    }

    func start() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.thermalState = ProcessInfo.processInfo.thermalState
                self?.evaluate()
            }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // 세션은 복원하지 않으므로, 지난번에 남은 뚜껑 모드는 원래대로 돌린다
        lidMode.refresh()
        if lidMode.isOn {
            lidMode.disable()
            notify("지난번에 켜져 있던 뚜껑 닫아도 유지를 껐어요.")
        }
        evaluate()
    }

    /// 앱이 끝날 때 뚜껑 모드를 남기지 않는다
    func appWillTerminate() {
        if lidMode.isOn { lidMode.disable() }
    }

    /// 뚜껑을 닫아 둔 채 뚜껑 모드가 풀렸으면 맥을 재운다.
    /// 충전기와 외장 모니터가 연결된 클램쉘 모드처럼, 뚜껑 모드가 없어도 원래 깨어 있을 상황이면 재우지 않는다
    func sleepIfLidClosed() {
        guard shouldSleepAfterLidModeEnds() else { return }
        lidMode.sleepNow()
    }

    private func shouldSleepAfterLidModeEnds() -> Bool {
        guard PowerStateMonitor.isLidClosed() else { return false }
        var withoutLidMode = power.snapshot
        withoutLidMode.isLidModeOn = false
        if case .sleeps = LidClosePrediction.outcome(for: withoutLidMode) { return true }
        return false
    }

    func evaluate() {
        guard let action = guardian.evaluate(power: power.snapshot, thermalState: thermalState, isAwake: awake.isAwake) else { return }
        let willSleep = shouldSleepAfterLidModeEnds()
        let sleepNote = willSleep ? " 뚜껑이 닫혀 있어 맥을 재울게요." : ""
        switch action {
        case .endAwakeForLowBattery(let percent):
            notify("배터리가 \(percent)%라 깨어 있기를 껐어요.\(sleepNote)")
            // 재우는 일은 세션이 끝날 때(awake.onWillEnd) 함께 처리된다
            awake.stop()
        case .disableLidModeForHeat:
            notify("맥이 많이 뜨거워서 뚜껑 닫아도 유지를 껐어요.\(sleepNote)")
            lidMode.disable()
            if willSleep { lidMode.sleepNow() }
        }
    }

    private func notify(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "랜턴"
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

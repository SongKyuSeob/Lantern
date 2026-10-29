import Foundation
import LanternKit

/// 깨어 있기의 실제 동작을 맡는다.
///
/// 세션 규칙(`AwakeSessionMachine`)과 시스템 호출(`IdleSleepBlocker`)을 연결하고,
/// 시간이 다 됐는지 주기적으로 확인하며, 마지막으로 쓴 옵션을 저장한다.
@Observable
final class AwakeController {
    private(set) var machine: AwakeSessionMachine
    /// 1초마다 바뀌어 남은 시간 표시를 갱신시킨다
    private(set) var now = Date()

    /// 세션이 끝나기 직전에 불린다 (사용자가 끄거나 시간이 다 됐을 때). 뚜껑 모드를 먼저 끄는 데 쓴다
    @ObservationIgnored var onWillEnd: (() -> Void)?
    /// 세션이 끝난 뒤 불린다. 기록을 남기는 데 쓴다 (다른 옵션으로 갈아 끼울 때도 앞 세션은 끝난 것으로 본다)
    @ObservationIgnored var onDidEnd: ((AwakeSession, AwakeEndReason) -> Void)?

    private let blocker = IdleSleepBlocker()
    /// 화면이 꺼진 동안 macOS가 앱 타이머를 늦추는 App Nap을 막는다 (끝 시각 처리가 늦어지지 않게)
    private var activity: NSObjectProtocol?
    private let defaults: UserDefaults
    private var timer: Timer?

    private static let lastOptionKey = "awake.lastOption"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.lastOptionKey)
            .flatMap { try? JSONDecoder().decode(AwakeOption.self, from: $0) }
        machine = AwakeSessionMachine(lastOption: saved ?? .hours(2))
    }

    var isAwake: Bool { machine.isAwake }
    var current: AwakeSession? { machine.current }
    var lastOption: AwakeOption { machine.lastOption }

    var remaining: TimeInterval? { machine.current?.remaining(at: now) }

    func start(_ option: AwakeOption) {
        let previous = machine.current
        machine.start(option, at: Date())
        if let previous { onDidEnd?(previous, .userStopped) }
        saveLastOption()
        applySystemState()
    }

    /// 지금 세션을 끊지 않고 끝 시각만 미룬다 (시간으로 끝나는 세션만)
    func extend(by interval: TimeInterval) {
        guard machine.extend(by: interval) else { return }
        now = Date()
    }

    func startWithLastOption() {
        start(machine.lastOption)
    }

    func stop(reason: AwakeEndReason = .userStopped) {
        guard machine.isAwake else { return }
        onWillEnd?()
        let ended = machine.stop()
        applySystemState()
        if let ended { onDidEnd?(ended, reason) }
    }

    /// 깨어 있는 동안 화면만 바로 끈다 (맥은 계속 깨어 있다)
    func turnOffDisplay() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }

    // MARK: - 내부

    /// 세션 상태에 맞춰 시스템 요청과 타이머를 붙이거나 뗀다
    private func applySystemState() {
        now = Date()
        if machine.isAwake {
            blocker.activate(reason: "랜턴: 깨어 있기")
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep, reason: "랜턴: 깨어 있기 끝 시각 확인"
                )
            }
            startTimer()
        } else {
            blocker.deactivate()
            if let activity { ProcessInfo.processInfo.endActivity(activity) }
            activity = nil
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        now = Date()
        if machine.current?.hasExpired(at: now) == true {
            onWillEnd?()
            let ended = machine.current
            _ = machine.tick(at: now)
            applySystemState()
            if let ended { onDidEnd?(ended, .timeElapsed) }
        }
    }

    private func saveLastOption() {
        if let data = try? JSONEncoder().encode(machine.lastOption) {
            defaults.set(data, forKey: Self.lastOptionKey)
        }
    }
}

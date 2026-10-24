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

    private let blocker = IdleSleepBlocker()
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
        machine.start(option, at: Date())
        saveLastOption()
        applySystemState()
    }

    func startWithLastOption() {
        start(machine.lastOption)
    }

    func stop() {
        machine.stop()
        applySystemState()
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
            startTimer()
        } else {
            blocker.deactivate()
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
        if machine.tick(at: now) != nil {
            applySystemState()
        }
    }

    private func saveLastOption() {
        if let data = try? JSONEncoder().encode(machine.lastOption) {
            defaults.set(data, forKey: Self.lastOptionKey)
        }
    }
}

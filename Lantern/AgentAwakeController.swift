import Foundation
import LanternKit

/// "에이전트가 끝날 때까지" 옵션을 맡는다. 에이전트가 모두 끝나면 깨어 있기를 끈다.
@Observable
final class AgentAwakeController {
    enum Phase: Equatable {
        /// 이 옵션으로 깨어 있지 않음
        case inactive
        /// 켰지만 아직 일하는 에이전트를 못 봄
        case waitingForAgents
        case working
        /// 모두 끝나서 곧 꺼짐
        case finishing
    }

    private(set) var phase: Phase = .inactive

    @ObservationIgnored private var watch: AgentFinishWatch?
    private let awake: AwakeController
    private let monitor: AgentMonitor

    init(awake: AwakeController, monitor: AgentMonitor) {
        self.awake = awake
        self.monitor = monitor
    }

    /// 깨어 있기 세션이 바뀌면 바로 다시 판단한다 (에이전트 판단은 `AgentMonitor.onUpdate`로 들어온다)
    func start() {
        observeSession()
        update()
    }

    private func observeSession() {
        withObservationTracking {
            _ = awake.current
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observeSession()
            }
        }
    }

    /// 에이전트 판단이 새로 될 때와 깨어 있기 옵션이 바뀔 때 부른다
    func update() {
        guard let session = awake.current, session.option == .untilAgentsFinish else {
            watch = nil
            setPhase(.inactive)
            return
        }
        if watch?.startedAt != session.startedAt {
            watch = AgentFinishWatch(startedAt: session.startedAt)
        }
        guard var current = watch else { return }
        let shouldEnd = current.update(anyWorking: monitor.anyWorking, now: Date())
        watch = current
        if shouldEnd {
            watch = nil
            awake.stop()
            setPhase(.inactive)
            return
        }
        if monitor.anyWorking {
            setPhase(.working)
        } else {
            setPhase(current.hasSeenWork ? .finishing : .waitingForAgents)
        }
    }

    private func setPhase(_ newPhase: Phase) {
        if phase != newPhase { phase = newPhase }
    }
}

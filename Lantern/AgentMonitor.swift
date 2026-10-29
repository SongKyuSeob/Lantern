import Foundation
import LanternKit

/// 에이전트 hook이 남긴 신호 파일을 읽어, 지금 일하는 에이전트 세션을 알려 준다.
///
/// 신호 폴더에 파일이 생기면 바로 읽고, 5초마다 프로세스가 살아 있는지·너무 오래 조용한지 다시 판단한다.
@Observable
final class AgentMonitor {
    struct ActiveSession: Identifiable, Equatable {
        let id: String
        let agent: AgentKind
        let status: AgentSessionTracker.Status
        let lastEventAt: Date
    }

    private(set) var activeSessions: [ActiveSession] = []
    /// 에이전트별로 마지막 신호를 받은 시각. 연결이 실제로 동작하는지 보여 주는 데 쓴다
    private(set) var lastSignalAt: [AgentKind: Date]
    /// 판단이 새로 될 때마다 불린다
    @ObservationIgnored var onUpdate: (() -> Void)?

    @ObservationIgnored private var tracker = AgentSessionTracker()
    @ObservationIgnored private var directorySource: DispatchSourceFileSystemObject?
    @ObservationIgnored private var timer: Timer?
    private let eventsPath = AgentHookConfig.eventsDirectory(home: NSHomeDirectory())
    private let defaults: UserDefaults

    private static let checkInterval: TimeInterval = 5
    private static let lastSignalKeyPrefix = "agent.lastSignal."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved: [AgentKind: Date] = [:]
        for agent in AgentKind.allCases {
            if let date = defaults.object(forKey: Self.lastSignalKeyPrefix + agent.rawValue) as? Date {
                saved[agent] = date
            }
        }
        lastSignalAt = saved
    }

    var anyWorking: Bool { !activeSessions.isEmpty }

    func count(of agent: AgentKind) -> Int {
        activeSessions.filter { $0.agent == agent }.count
    }

    func start() {
        try? FileManager.default.createDirectory(atPath: eventsPath, withIntermediateDirectories: true)
        drain()
        watchDirectory()
        // 폴더 알림을 놓치거나 폴더가 지워졌다 다시 생겨도 따라가도록, 주기적으로도 읽고 감시를 다시 붙인다
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.directorySource == nil { self.watchDirectory() }
                self.drain()
                self.reevaluate()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        directorySource?.cancel()
        directorySource = nil
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 신호 읽기

    private func watchDirectory() {
        try? FileManager.default.createDirectory(atPath: eventsPath, withIntermediateDirectories: true)
        let descriptor = open(eventsPath, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 폴더가 지워지거나 옮겨지면 지금 감시는 쓸모없으니 끊는다. 타이머가 새 폴더에 다시 붙인다
                if let source, !source.data.isDisjoint(with: [.delete, .rename]) {
                    source.cancel()
                    self.directorySource = nil
                    return
                }
                self.drain()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
    }

    /// 쌓인 신호 파일을 쓰인 순서대로 반영하고 지운다. 너무 오래된 신호는 읽지 않고 지운다
    private func drain() {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: eventsPath) else { return }
        let now = Date()
        let files: [(path: String, date: Date)] = names
            .filter { $0.hasSuffix(".event") }
            .compactMap { name in
                let path = "\(eventsPath)/\(name)"
                guard let date = (try? manager.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return nil }
                return (path, date)
            }
            .sorted { $0.date < $1.date }
        removeStaleTemporaryFiles(names, now: now)
        guard !files.isEmpty else { return }

        for file in files {
            defer { try? manager.removeItem(atPath: file.path) }
            guard now.timeIntervalSince(file.date) < AgentSessionTracker.busyLimit,
                  let contents = try? String(contentsOfFile: file.path, encoding: .utf8),
                  let event = AgentHookEvent.parse(fileContents: contents, receivedAt: file.date)
            else { continue }
            tracker.apply(event, agentStartedAt: event.agentPID.flatMap(ProcessIdentity.startTime))
            recordSignal(from: event.agent, at: file.date)
        }
        reevaluate()
    }

    /// hook이 쓰다가 끊겨 남은 임시 파일(.tmp)을 지운다. 1분 넘게 남은 것만 지워 쓰는 중인 파일은 건드리지 않는다
    private func removeStaleTemporaryFiles(_ names: [String], now: Date) {
        let manager = FileManager.default
        for name in names where name.hasSuffix(".tmp") {
            let path = "\(eventsPath)/\(name)"
            guard let date = (try? manager.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(date) > 60 else { continue }
            try? manager.removeItem(atPath: path)
        }
    }

    private func recordSignal(from agent: AgentKind, at date: Date) {
        guard (lastSignalAt[agent] ?? .distantPast) < date else { return }
        lastSignalAt[agent] = date
        defaults.set(date, forKey: Self.lastSignalKeyPrefix + agent.rawValue)
    }

    // MARK: - 판단

    private func reevaluate() {
        let now = Date()
        tracker.prune(now: now, isAlive: ProcessIdentity.isAlive)
        let sessions = tracker.activeSessions(
            now: now, isAlive: ProcessIdentity.isAlive, childStartTimes: ProcessIdentity.childStartTimes
        ).map {
            ActiveSession(
                id: "\($0.session.agent.rawValue):\($0.session.sessionID)",
                agent: $0.session.agent,
                status: $0.status,
                lastEventAt: $0.session.lastEventAt
            )
        }
        if sessions != activeSessions { activeSessions = sessions }
        onUpdate?()
    }
}

/// 프로세스가 아직 같은 프로그램으로 살아 있는지 확인한다
enum ProcessIdentity {
    /// 프로세스 시작 시각. 없는 프로세스면 `nil`
    static func startTime(of pid: Int32) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let time = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    /// `pid`의 자식 프로세스들이 시작한 시각. 허락받고 명령이 도는지 알아보는 데 쓴다
    static func childStartTimes(of pid: Int32) -> [Date] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // 그 사이 프로세스가 늘 수 있어 여유를 둔다
        let capacity = size / MemoryLayout<kinfo_proc>.stride + 32
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        size = capacity * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &processes, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return processes.prefix(count)
            .filter { $0.kp_eproc.e_ppid == pid }
            .map {
                let time = $0.kp_proc.p_un.__p_starttime
                return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
            }
    }

    /// 번호가 다른 프로그램에 재사용됐으면 시작 시각이 달라진다
    static func isAlive(_ pid: Int32, startedAt: Date?) -> Bool {
        guard let current = startTime(of: pid) else { return false }
        guard let startedAt else { return true }
        return abs(current.timeIntervalSince(startedAt)) < 1
    }
}

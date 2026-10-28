import Foundation

/// 기록 창에 쓰는 할 일 하나 (저장 모델과 떨어진 값)
public struct HistoryTodo: Equatable, Sendable {
    public let title: String
    public let isDone: Bool
    public let completedAt: Date?
    public let hiddenAt: Date?

    public init(title: String, isDone: Bool, completedAt: Date?, hiddenAt: Date?) {
        self.title = title
        self.isDone = isDone
        self.completedAt = completedAt
        self.hiddenAt = hiddenAt
    }
}

/// 기록 창에 쓰는 깨어 있기 한 번
public struct HistoryAwake: Equatable, Sendable {
    public let startedAt: Date
    public let endedAt: Date
    public let optionLabel: String
    public let usedLidMode: Bool

    public init(startedAt: Date, endedAt: Date, optionLabel: String, usedLidMode: Bool) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.optionLabel = optionLabel
        self.usedLidMode = usedLidMode
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

/// 하루치 기록
public struct HistoryDay: Equatable, Sendable {
    public let day: Date
    public internal(set) var completed: [HistoryTodo] = []
    public internal(set) var removed: [HistoryTodo] = []
    public internal(set) var awake: [HistoryAwake] = []

    public var awakeDuration: TimeInterval { awake.reduce(0) { $0 + $1.duration } }

    /// 조건에 맞는 할 일만 남긴 하루 (검색 결과용). 깨어 있기는 그대로 둔다
    public func filteringTodos(_ isIncluded: (HistoryTodo) -> Bool) -> HistoryDay {
        var copy = self
        copy.completed = completed.filter(isIncluded)
        copy.removed = removed.filter(isIncluded)
        return copy
    }
    public var isEmpty: Bool { completed.isEmpty && removed.isEmpty && awake.isEmpty }
}

/// 잔디 색을 무엇으로 정할지
public enum HistoryMetric: String, CaseIterable, Sendable {
    /// 그날 끝낸 할 일 수
    case todos
    /// 그날 깨어 있던 시간
    case awake
}

/// 기록 창에서 보여 줄 할 일 종류
public enum HistoryFilter: String, CaseIterable, Sendable {
    case all
    case completed
    case removed
}

/// 날짜별 묶기, 잔디 칸과 진하기, Markdown 내보내기
public enum History {
    /// 할 일은 끝낸 날(끝낸 일) 또는 치운 날(지운 일)에, 깨어 있기는 시작한 날에 넣는다
    public static func days(todos: [HistoryTodo], awake: [HistoryAwake], calendar: Calendar = .current) -> [Date: HistoryDay] {
        var result: [Date: HistoryDay] = [:]
        func update(_ date: Date, _ change: (inout HistoryDay) -> Void) {
            let day = calendar.startOfDay(for: date)
            var value = result[day] ?? HistoryDay(day: day)
            change(&value)
            result[day] = value
        }
        for todo in todos {
            if todo.isDone, let completedAt = todo.completedAt {
                update(completedAt) { $0.completed.append(todo) }
            } else if !todo.isDone, let hiddenAt = todo.hiddenAt {
                update(hiddenAt) { $0.removed.append(todo) }
            }
        }
        for record in awake {
            update(record.startedAt) { $0.awake.append(record) }
        }
        for (day, var value) in result {
            value.completed.sort { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            value.removed.sort { ($0.hiddenAt ?? .distantPast) < ($1.hiddenAt ?? .distantPast) }
            value.awake.sort { $0.startedAt < $1.startedAt }
            result[day] = value
        }
        return result
    }

    /// 잔디 칸. 바깥 배열은 주(오래된 것부터), 안쪽은 그 주의 7일(주의 첫날부터).
    /// 오늘 이후는 `nil`
    public static func grid(endingAt today: Date, weeks: Int, calendar: Calendar = .current) -> [[Date?]] {
        let todayStart = calendar.startOfDay(for: today)
        let weekday = calendar.component(.weekday, from: todayStart)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let thisWeekStart = calendar.date(byAdding: .day, value: -offset, to: todayStart),
              let firstWeekStart = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisWeekStart)
        else { return [] }
        return (0..<weeks).map { week in
            (0..<7).map { day -> Date? in
                guard let date = calendar.date(byAdding: .day, value: week * 7 + day, to: firstWeekStart),
                      date <= todayStart
                else { return nil }
                return date
            }
        }
    }

    /// 한 해의 잔디 칸 (GitHub처럼 1월 1일이 든 주부터 12월 31일이 든 주까지).
    /// 그해가 아닌 날은 `nil`. 오늘 이후도 칸은 있다 (화면에서 옅게 그린다)
    public static func grid(year: Int, calendar: Calendar = .current) -> [[Date?]] {
        guard let first = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let last = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
        else { return [] }
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: first) else { return [] }
        var weeks: [[Date?]] = []
        var weekStart = start
        while weekStart <= last {
            weeks.append((0..<7).map { day -> Date? in
                guard let date = calendar.date(byAdding: .day, value: day, to: weekStart),
                      date >= first, date <= last
                else { return nil }
                return date
            })
            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    /// 기록이 있는 가장 이른 해. 기록이 없으면 `nil`
    public static func earliestYear(in days: [Date: HistoryDay], calendar: Calendar = .current) -> Int? {
        days.keys.min().map { calendar.component(.year, from: $0) }
    }

    public static func value(of day: HistoryDay?, metric: HistoryMetric) -> Double {
        guard let day else { return 0 }
        switch metric {
        case .todos: return Double(day.completed.count)
        case .awake: return day.awakeDuration / 3600
        }
    }

    /// 0(없음) ~ 4(가장 많음). 보이는 기간에서 가장 많은 날을 4로 본다
    public static func level(_ value: Double, max: Double) -> Int {
        guard value > 0, max > 0 else { return 0 }
        return min(4, Swift.max(1, Int((value / max * 4).rounded(.up))))
    }

    // MARK: - Markdown

    /// 하루치 기록을 Markdown으로. Obsidian·Notion에 붙여 넣으면 체크리스트로 보인다
    public static func markdown(for day: HistoryDay, filter: HistoryFilter = .all, calendar: Calendar = .current) -> String {
        var lines = ["## \(dateTitle(day.day, calendar: calendar))"]
        if filter != .removed, !day.completed.isEmpty {
            lines.append("")
            lines.append("### 끝낸 일")
            lines += day.completed.map { "- [x] \($0.title)" }
        }
        if filter != .completed, !day.removed.isEmpty {
            lines.append("")
            lines.append("### 지운 일")
            lines += day.removed.map { "- [ ] ~~\($0.title)~~" }
        }
        if filter == .all, !day.awake.isEmpty {
            lines.append("")
            lines.append("### 깨어 있기 · \(durationText(day.awakeDuration))")
            lines += day.awake.map { record in
                var line = "- \(clock(record.startedAt, calendar: calendar)) ~ \(clock(record.endedAt, calendar: calendar)) (\(durationText(record.duration)))"
                if !record.optionLabel.isEmpty { line += " · \(record.optionLabel)" }
                if record.usedLidMode { line += " · 뚜껑 닫아도 유지" }
                return line
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "2026-10-29 (수)"
    public static func dateTitle(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let weekday = weekdays[((parts.weekday ?? 1) - 1) % 7]
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0) + " (\(weekday))"
    }

    /// "오후 3:05"
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let period = hour < 12 ? "오전" : "오후"
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(period) \(hour12):" + String(format: "%02d", parts.minute ?? 0)
    }

    /// "2시간 5분", "45분"
    public static func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)분" }
        return rest == 0 ? "\(hours)시간" : "\(hours)시간 \(rest)분"
    }
}

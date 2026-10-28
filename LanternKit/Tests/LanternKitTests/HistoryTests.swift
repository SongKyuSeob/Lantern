import Foundation
import LanternKit
import Testing

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    calendar.firstWeekday = 1
    return calendar
}()

/// 2026-10-29(목) 기준 시각
private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Suite("기록 묶기")
struct HistoryDaysTests {
    @Test("끝낸 일은 끝낸 날, 지운 일은 치운 날, 깨어 있기는 시작한 날에 들어간다") func groupsByDay() {
        let todos = [
            HistoryTodo(title: "끝냄", isDone: true, completedAt: date(28, 10), hiddenAt: date(29, 9)),
            HistoryTodo(title: "지움", isDone: false, completedAt: nil, hiddenAt: date(29, 11)),
            HistoryTodo(title: "아직", isDone: false, completedAt: nil, hiddenAt: nil),
        ]
        let awake = [HistoryAwake(startedAt: date(28, 23), endedAt: date(29, 1), optionLabel: "2시간", usedLidMode: false)]
        let days = History.days(todos: todos, awake: awake, calendar: calendar)
        let day28 = days[calendar.startOfDay(for: date(28, 0))]
        let day29 = days[calendar.startOfDay(for: date(29, 0))]
        #expect(day28?.completed.map(\.title) == ["끝냄"])
        #expect(day28?.awake.count == 1)
        #expect(day28?.awakeDuration == TimeInterval(2 * 3600))
        #expect(day29?.removed.map(\.title) == ["지움"])
        #expect(day29?.completed.isEmpty == true)
        #expect(days.count == 2)
    }

    @Test("하루 안에서는 시간순") func sortsWithinDay() {
        let todos = [
            HistoryTodo(title: "늦게", isDone: true, completedAt: date(29, 15), hiddenAt: nil),
            HistoryTodo(title: "일찍", isDone: true, completedAt: date(29, 9), hiddenAt: nil),
        ]
        let day = History.days(todos: todos, awake: [], calendar: calendar).values.first
        #expect(day?.completed.map(\.title) == ["일찍", "늦게"])
    }
}

@Suite("잔디")
struct HistoryGridTests {
    @Test("마지막 주에 오늘이 들어가고, 오늘 이후는 비운다") func gridEndsToday() {
        let grid = History.grid(endingAt: date(29, 12), weeks: 3, calendar: calendar)
        #expect(grid.count == 3)
        #expect(grid.allSatisfy { $0.count == 7 })
        let last = grid[2]
        // 10월 29일은 목요일(일요일 시작 주의 5번째)
        #expect(last[4] == calendar.startOfDay(for: date(29, 0)))
        #expect(last[5] == nil && last[6] == nil)
        #expect(grid[0][0] == calendar.startOfDay(for: date(11, 0)))
    }

    @Test("한 해 잔디는 1월 1일이 든 주부터 12월 31일이 든 주까지") func yearGrid() {
        let grid = History.grid(year: 2025, calendar: calendar)
        // 2025-01-01은 수요일 → 첫 주의 일·월·화는 비어 있다
        #expect(grid.first?[0] == nil && grid.first?[2] == nil)
        #expect(grid.first?[3] == calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))
        let all = grid.flatMap { $0 }.compactMap { $0 }
        #expect(all.count == 365)
        #expect(grid.count == 53)
    }

    @Test("올해도 남은 날까지 칸은 있다 (화면에서 옅게)") func currentYearGrid() {
        let grid = History.grid(year: 2026, calendar: calendar)
        let all = grid.flatMap { $0 }.compactMap { $0 }
        #expect(all.count == 365)
        #expect(all.last == calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)))
    }

    @Test("기록이 있는 가장 이른 해") func earliestYear() {
        let days = History.days(
            todos: [HistoryTodo(title: "a", isDone: true, completedAt: calendar.date(from: DateComponents(year: 2024, month: 5, day: 1)), hiddenAt: nil)],
            awake: [], calendar: calendar
        )
        #expect(History.earliestYear(in: days, calendar: calendar) == 2024)
        #expect(History.earliestYear(in: [:], calendar: calendar) == nil)
    }

    @Test("가장 많은 날이 4, 없으면 0") func levels() {
        #expect(History.level(0, max: 10) == 0)
        #expect(History.level(10, max: 10) == 4)
        #expect(History.level(1, max: 10) == 1)
        #expect(History.level(5, max: 10) == 2)
        #expect(History.level(3, max: 0) == 0)
    }

    @Test("잔디 값은 끝낸 할 일 수 또는 깨어 있던 시간") func values() {
        var day = History.days(
            todos: [HistoryTodo(title: "a", isDone: true, completedAt: date(29, 9), hiddenAt: nil)],
            awake: [HistoryAwake(startedAt: date(29, 10), endedAt: date(29, 11, 30), optionLabel: "", usedLidMode: false)],
            calendar: calendar
        ).values.first
        #expect(History.value(of: day, metric: .todos) == 1)
        #expect(History.value(of: day, metric: .awake) == 1.5)
        day = nil
        #expect(History.value(of: day, metric: .todos) == 0)
    }
}

@Suite("Markdown 내보내기")
struct HistoryMarkdownTests {
    private var day: HistoryDay {
        History.days(
            todos: [
                HistoryTodo(title: "README 정리", isDone: true, completedAt: date(29, 9), hiddenAt: nil),
                HistoryTodo(title: "안 할 일", isDone: false, completedAt: nil, hiddenAt: date(29, 10)),
            ],
            awake: [HistoryAwake(startedAt: date(29, 13, 5), endedAt: date(29, 15, 10), optionLabel: "2시간", usedLidMode: true)],
            calendar: calendar
        ).values.first!
    }

    @Test("체크리스트와 깨어 있기 줄을 쓴다") func fullDay() {
        #expect(History.markdown(for: day, calendar: calendar) == """
        ## 2026-10-29 (목)

        ### 끝낸 일
        - [x] README 정리

        ### 지운 일
        - [ ] ~~안 할 일~~

        ### 깨어 있기 · 2시간 5분
        - 오후 1:05 ~ 오후 3:10 (2시간 5분) · 2시간 · 뚜껑 닫아도 유지

        """)
    }

    @Test("필터에 맞는 묶음만 쓴다") func filtered() {
        let completed = History.markdown(for: day, filter: .completed, calendar: calendar)
        #expect(completed.contains("끝낸 일") && !completed.contains("지운 일") && !completed.contains("깨어 있기"))
        let removed = History.markdown(for: day, filter: .removed, calendar: calendar)
        #expect(removed.contains("지운 일") && !removed.contains("끝낸 일"))
    }

    @Test("시간 표기", arguments: [(0.0, "0분"), (45 * 60.0, "45분"), (3600.0, "1시간"), (3900.0, "1시간 5분")])
    func durations(_ pair: (TimeInterval, String)) {
        #expect(History.durationText(pair.0) == pair.1)
    }
}

import Foundation
import LanternKit
import Testing

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}()

private func day(_ month: Int, _ day: Int, year: Int = 2026, hour: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

@MainActor
@Suite("할 일 기한")
struct TodoDueTests {
    /// 지금은 2026-11-04 오후 3시
    private let now = day(11, 4, hour: 15)

    @Test("임박 기준 안이거나 이미 지난 기한은 임박", arguments: [
        (day(11, 3), 0, true),
        (day(11, 4), 0, true),
        (day(11, 5), 0, false),
        (day(11, 5), 1, true),
        (day(11, 6), 1, false),
        (day(11, 11), 7, true),
        (day(11, 12), 7, false),
    ])
    func isSoon(_ input: (Date, Int, Bool)) {
        #expect(TodoDue.isSoon(input.0, now: now, days: input.1, calendar: calendar) == input.2)
    }

    @Test("임박한 할 일은 기한 순으로 위에, 나머지는 끌어서 정한 순서 그대로") func arrange() throws {
        let store = TodoStore(container: try TodoStore.makeContainer(url: nil))
        let items = ["가", "나", "다", "라", "마"].compactMap { store.add($0) }
        store.setDueDate(items[1], to: day(11, 5), calendar: calendar)  // 나: 내일 (임박)
        store.setDueDate(items[3], to: day(11, 2), calendar: calendar)  // 라: 지남 (임박)
        store.setDueDate(items[4], to: day(11, 20), calendar: calendar) // 마: 멀었음
        let arranged = TodoDue.arrange(store.openItems(), now: now, days: 1, calendar: calendar)
        #expect(arranged.soon.map(\.title) == ["라", "나"])
        #expect(arranged.rest.map(\.title) == ["가", "다", "마"])
    }

    @Test("기한 표시: 올해는 월/일, 다른 해는 연도까지") func label() {
        #expect(TodoDue.label(day(11, 7), now: now, calendar: calendar) == "11/7")
        #expect(TodoDue.label(day(1, 5, year: 2027), now: now, calendar: calendar) == "2027/1/5")
    }

    @Test("남은 날 문구", arguments: [(day(11, 4), "오늘"), (day(11, 5), "내일"), (day(11, 7), "3일 남음"), (day(11, 2), "2일 지남")])
    func remaining(_ input: (Date, String)) {
        #expect(TodoDue.remainingText(input.0, now: now, calendar: calendar, language: .korean) == input.1)
    }

    @Test("영어 남은 날 문구", arguments: [(day(11, 4), "Today"), (day(11, 5), "Tomorrow"), (day(11, 7), "3 days left"), (day(11, 3), "1 day overdue"), (day(11, 2), "2 days overdue")])
    func remainingEnglish(_ input: (Date, String)) {
        #expect(TodoDue.remainingText(input.0, now: now, calendar: calendar, language: .english) == input.1)
    }

    @Test("달력은 늘 6주, 그달 1일은 요일 칸에 맞춘다") func monthGrid() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let grid = TodoDue.monthGrid(containing: day(11, 20), calendar: sundayFirst)
        #expect(grid.count == 6 && grid.allSatisfy { $0.count == 7 })
        // 2026년 11월 1일은 일요일
        #expect(grid[0][0] == day(11, 1))
        #expect(grid.flatMap { $0 }.compactMap { $0 }.count == 30)
        #expect(grid[4][1] == day(11, 30))
        #expect(grid[4][2] == nil)
    }

    @Test("Markdown에 기한을 붙인다") func markdown() {
        let days = History.days(
            todos: [HistoryTodo(title: "발표 자료", isDone: true, completedAt: day(11, 4, hour: 10), hiddenAt: nil, dueDate: day(11, 7))],
            awake: [],
            calendar: calendar
        )
        let text = History.markdown(for: days.values.first!, calendar: calendar, language: .korean)
        #expect(text.contains("- [x] 발표 자료 (기한 2026-11-07)"))
    }
}

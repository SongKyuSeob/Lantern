import Foundation

/// 할 일 기한: 임박 판단, 화면 순서, 표시 글자
public enum TodoDue {
    /// 설정에서 고르는 임박 기준 (기한 며칠 전부터 임박인지). 0은 당일
    public static let soonDayOptions = [0, 1, 2, 3, 7]
    public static let defaultSoonDays = 1
    /// 임박 기준을 저장하는 UserDefaults 키
    public static let soonDaysKey = "todo.dueSoonDays"

    /// 기한이 `days`일 안으로 다가왔거나 이미 지났는지
    public static func isSoon(_ dueDate: Date, now: Date, days: Int, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        guard let limit = calendar.date(byAdding: .day, value: days, to: today) else { return false }
        return calendar.startOfDay(for: dueDate) <= limit
    }

    /// 화면에 보여 줄 순서. 임박한 할 일을 기한이 빠른 것부터 맨 위에 모으고, 나머지는 받은 순서(끌어서 정한 순서) 그대로 둔다.
    /// `items`는 끌어서 정한 순서대로 넘긴다
    public static func arrange(_ items: [TodoItem], now: Date, days: Int, calendar: Calendar = .current) -> (soon: [TodoItem], rest: [TodoItem]) {
        var soon: [(offset: Int, item: TodoItem, due: Date)] = []
        var rest: [TodoItem] = []
        for (offset, item) in items.enumerated() {
            if let due = item.dueDate, isSoon(due, now: now, days: days, calendar: calendar) {
                soon.append((offset, item, due))
            } else {
                rest.append(item)
            }
        }
        // 기한이 같으면 끌어서 정한 순서를 따른다
        soon.sort { ($0.due, $0.offset) < ($1.due, $1.offset) }
        return (soon.map(\.item), rest)
    }

    /// "11/7". 올해가 아니면 "2027/1/5"
    public static func label(_ dueDate: Date, now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: dueDate)
        let monthDay = "\(parts.month ?? 0)/\(parts.day ?? 0)"
        return parts.year == calendar.component(.year, from: now) ? monthDay : "\(parts.year ?? 0)/" + monthDay
    }

    /// 남은 날: "오늘", "내일", "3일 남음", "2일 지남" / "Today", "Tomorrow", "3 days left", "2 days overdue"
    public static func remainingText(
        _ dueDate: Date, now: Date, calendar: Calendar = .current, language: AppLanguage = Localization.language
    ) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: dueDate)).day ?? 0
        switch days {
        case 0: return language.text("오늘", "Today")
        case 1: return language.text("내일", "Tomorrow")
        case ..<0: return language.text("\(-days)일 지남", -days == 1 ? "1 day overdue" : "\(-days) days overdue")
        default: return language.text("\(days)일 남음", "\(days) days left")
        }
    }

    /// 달력 한 달치 칸. 늘 6주(42칸)라 달이 바뀌어도 크기가 같다. 그달이 아닌 칸은 `nil`
    public static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [[Date?]] {
        guard let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date)),
              let dayCount = calendar.range(of: .day, in: .month, for: first)?.count
        else { return [] }
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let cells: [Date?] = (0..<42).map { index in
            let day = index - leading
            guard day >= 0, day < dayCount else { return nil }
            return calendar.date(byAdding: .day, value: day, to: first)
        }
        return stride(from: 0, to: 42, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// 설정 선택지 이름: "당일", "1일 전", "1주 전" / "On the due date", "1 day before", "1 week before"
    public static func soonDaysTitle(_ days: Int, language: AppLanguage = Localization.language) -> String {
        switch days {
        case 0: language.text("당일", "On the due date")
        case 7: language.text("1주 전", "1 week before")
        default: language.text("\(days)일 전", days == 1 ? "1 day before" : "\(days) days before")
        }
    }
}

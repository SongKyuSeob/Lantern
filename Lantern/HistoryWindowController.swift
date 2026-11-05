import AppKit
import LanternKit
import SwiftData
import SwiftUI

/// 기록 창. 날짜별 잔디와, 고른 날의 끝낸 일 · 지운 일 · 깨어 있기를 보여 준다
final class HistoryWindowController {
    private let todoStore: TodoStore
    private var window: NSWindow?

    init(todoStore: TodoStore) {
        self.todoStore = todoStore
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: HistoryView().modelContainer(todoStore.container))
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.title = L("랜턴 기록", "Lantern History")
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 740, height: 640))
            window.contentMinSize = NSSize(width: 740, height: 480)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // 메뉴바 앱은 앞으로 나오라는 요청이 거절될 수 있어 창도 맨 앞에 올린다
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    #if DEBUG
    /// SwiftUI가 직접 그리는 글자·도형은 cacheDisplay에 담기지 않아 ImageRenderer로 그린다
    /// (세그먼트·입력 칸 같은 macOS 컨트롤은 빈칸으로 나온다)
    func snapshot(to path: String) {
        let size = window?.contentView?.bounds.size ?? NSSize(width: 740, height: 640)
        let content = HistoryView()
            .modelContainer(todoStore.container)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return }
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif
}

struct HistoryView: View {
    @Query private var todos: [TodoItem]
    @Query(sort: \AwakeRecord.startedAt) private var records: [AwakeRecord]

    @AppStorage("history.metric") private var metric: HistoryMetric = .todos
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var filter: HistoryFilter = .all
    @State private var search = ""
    @State private var copied = false
    /// 잔디에 보여 줄 해. ‹ ›로 넘긴다
    @State private var year = Calendar.current.component(.year, from: Date())

    private var days: [Date: HistoryDay] {
        History.days(
            todos: todos.map { HistoryTodo(title: $0.title, isDone: $0.isDone, completedAt: $0.completedAt, hiddenAt: $0.hiddenAt, note: $0.note, dueDate: $0.dueDate) },
            awake: records.map { HistoryAwake(startedAt: $0.startedAt, endedAt: $0.endedAt, optionLabel: $0.optionLabel, usedLidMode: $0.usedLidMode) }
        )
    }

    var body: some View {
        let days = days
        let thisYear = Calendar.current.component(.year, from: Date())
        let earliest = min(History.earliestYear(in: days) ?? thisYear, thisYear)
        let grid = History.grid(year: year)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(L("기록", "History"))
                    .font(.title2.weight(.semibold))
                Spacer()
                HStack(spacing: 4) {
                    Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                        .disabled(year <= earliest)
                        .help(L("이전 해", "Previous Year"))
                    Text(verbatim: "\(year)")
                        .font(.headline)
                        .monospacedDigit()
                        .frame(minWidth: 44)
                    Button { year += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(year >= thisYear)
                        .help(L("다음 해", "Next Year"))
                }
                .buttonStyle(.borderless)
                Picker(L("잔디 기준", "Color by"), selection: $metric) {
                    Text(L("끝낸 할 일", "Completed To-dos")).tag(HistoryMetric.todos)
                    Text(L("깨어 있기", "Time Awake")).tag(HistoryMetric.awake)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HistoryGrid(days: days, metric: metric, grid: grid, selectedDay: $selectedDay)
            summary(days, grid: grid)
            Divider()
            detailHeader(days)
            ScrollView {
                if search.trimmingCharacters(in: .whitespaces).isEmpty {
                    HistoryDayDetail(day: days[selectedDay], filter: filter)
                } else {
                    searchResults(days)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 740, minHeight: 480)
    }

    private func summary(_ days: [Date: HistoryDay], grid: [[Date?]]) -> some View {
        let visible = Set(grid.flatMap { $0 }.compactMap { $0 })
        let inRange = days.filter { visible.contains($0.key) }.values
        let completed = inRange.reduce(0) { $0 + $1.completed.count }
        let awake = inRange.reduce(0) { $0 + $1.awakeDuration }
        return HStack(spacing: 6) {
            Text(verbatim: L("\(year)년 · 끝낸 일 \(completed)개 · 깨어 있기 \(History.durationText(awake))", "\(year) · \(completed) completed · \(History.durationText(awake)) awake"))
            Spacer()
            Text(L("적음", "Less"))
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(HistoryGrid.color(level: level))
                    .frame(width: 11, height: 11)
            }
            Text(L("많음", "More"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func detailHeader(_ days: [Date: HistoryDay]) -> some View {
        HStack(spacing: 10) {
            Text(search.isEmpty ? History.dateTitle(selectedDay) : L("검색 결과", "Search Results"))
                .font(.headline)
            Spacer()
            Picker(L("보기", "Show"), selection: $filter) {
                Text(L("전체", "All")).tag(HistoryFilter.all)
                Text(L("끝낸 일", "Completed")).tag(HistoryFilter.completed)
                Text(L("지운 일", "Removed")).tag(HistoryFilter.removed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            TextField(L("할 일 검색", "Search To-dos"), text: $search)
                .textFieldStyle(.roundedBorder)
                // 영어는 버튼 글자가 길어서, 자리가 모자라면 검색 칸이 먼저 줄어든다
                .frame(minWidth: 110, maxWidth: 150)
            Button(copied ? L("복사했어요", "Copied") : L("Markdown 복사", "Copy as Markdown")) {
                guard let day = days[selectedDay] else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(History.markdown(for: day, filter: filter), forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            .fixedSize()
            .disabled(days[selectedDay] == nil || !search.isEmpty)
            .help(L("고른 날의 기록을 Obsidian·Notion에 붙여 넣을 수 있는 체크리스트로 복사해요", "Copy the selected day as a checklist you can paste into Obsidian or Notion"))
        }
    }

    /// 검색어가 들어간 할 일을 날짜별로
    private func searchResults(_ days: [Date: HistoryDay]) -> some View {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matched = days.values
            .map { $0.filteringTodos { $0.matches(query) } }
            .filter { !$0.completed.isEmpty || !$0.removed.isEmpty }
            .sorted { $0.day > $1.day }
        return VStack(alignment: .leading, spacing: 16) {
            if matched.isEmpty {
                Text(L("\"\(query)\"이(가) 들어간 할 일이 없어요", "No to-dos match \"\(query)\""))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(matched, id: \.day) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Button(History.dateTitle(day.day)) {
                        selectedDay = day.day
                        search = ""
                    }
                    .buttonStyle(.link)
                    HistoryDayDetail(day: day, filter: filter, showsAwake: false)
                }
            }
        }
    }
}

/// 잔디: 열은 주, 행은 요일. 누르면 그날을 고른다
private struct HistoryGrid: View {
    let days: [Date: HistoryDay]
    let metric: HistoryMetric
    let grid: [[Date?]]
    @Binding var selectedDay: Date

    /// 한 해(53주)가 창 폭에 들어가는 크기
    private static let cell: CGFloat = 10
    private static let gap: CGFloat = 2.5

    static func color(level: Int) -> Color {
        switch level {
        case 0: Color.secondary.opacity(0.15)
        case 1: Color.accentColor.opacity(0.3)
        case 2: Color.accentColor.opacity(0.5)
        case 3: Color.accentColor.opacity(0.75)
        default: Color.accentColor
        }
    }

    var body: some View {
        let values = grid.flatMap { $0 }.compactMap { $0 }.map { History.value(of: days[$0], metric: metric) }
        let maxValue = values.max() ?? 0
        HStack(alignment: .top, spacing: Self.gap) {
            weekdayLabels
            ForEach(grid.indices, id: \.self) { week in
                VStack(spacing: Self.gap) {
                    monthLabel(grid[week])
                    ForEach(0..<7, id: \.self) { weekday in
                        if let date = grid[week][weekday] {
                            cell(date, maxValue: maxValue)
                        } else {
                            Color.clear.frame(width: Self.cell, height: Self.cell)
                        }
                    }
                }
            }
        }
    }

    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: Self.gap) {
            Text(" ").font(.system(size: 9)).frame(height: 12)
            ForEach(Array(L("일 월 화 수 목 금 토", "Sun Mon Tue Wed Thu Fri Sat").split(separator: " ").enumerated()), id: \.offset) { index, name in
                Text(index % 2 == 1 ? String(name) : "")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(height: Self.cell)
            }
        }
        .frame(width: Localization.language == .korean ? 14 : 22)
    }

    /// 그 주에 1일이 들어 있으면 "10월"("Oct")처럼 달을 적는다
    private func monthLabel(_ week: [Date?]) -> some View {
        let calendar = Calendar.current
        let firstOfMonth = week.compactMap { $0 }.first { calendar.component(.day, from: $0) == 1 }
        let text = firstOfMonth.map { L("\(calendar.component(.month, from: $0))월", $0.formatted(.dateTime.month(.abbreviated).locale(Localization.locale))) } ?? ""
        return Text(text)
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .fixedSize()
            .frame(width: Self.cell, height: 12, alignment: .leading)
    }

    @ViewBuilder
    private func cell(_ date: Date, maxValue: Double) -> some View {
        if date > Calendar.current.startOfDay(for: Date()) {
            // 아직 오지 않은 날: 한 해 모양만 보이게 옅게
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.06))
                .frame(width: Self.cell, height: Self.cell)
        } else {
            pastCell(date, maxValue: maxValue)
        }
    }

    private func pastCell(_ date: Date, maxValue: Double) -> some View {
        let day = days[date]
        let level = History.level(History.value(of: day, metric: metric), max: maxValue)
        let isSelected = date == selectedDay
        return RoundedRectangle(cornerRadius: 3)
            .fill(Self.color(level: level))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5)
                }
            }
            .frame(width: Self.cell, height: Self.cell)
            .contentShape(Rectangle())
            .onTapGesture { selectedDay = date }
            .help(tooltip(date, day))
    }

    private func tooltip(_ date: Date, _ day: HistoryDay?) -> String {
        var parts = [History.dateTitle(date)]
        parts.append(L("끝낸 일 \(day?.completed.count ?? 0)", "\(day?.completed.count ?? 0) completed"))
        if let removed = day?.removed.count, removed > 0 { parts.append(L("지운 일 \(removed)", "\(removed) removed")) }
        if let awake = day?.awakeDuration, awake > 0 { parts.append(L("깨어 있기 \(History.durationText(awake))", "\(History.durationText(awake)) awake")) }
        return parts.joined(separator: " · ")
    }
}

/// 고른 날의 끝낸 일 · 지운 일 · 깨어 있기
private struct HistoryDayDetail: View {
    let day: HistoryDay?
    let filter: HistoryFilter
    var showsAwake = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let day, !isEmpty(day) {
                if filter != .removed, !day.completed.isEmpty {
                    section(L("끝낸 일 \(day.completed.count)", "Completed \(day.completed.count)")) {
                        ForEach(Array(day.completed.enumerated()), id: \.offset) { _, todo in
                            row(icon: "checkmark.circle.fill", tint: .accentColor, todo: todo, strike: false, time: todo.completedAt)
                        }
                    }
                }
                if filter != .completed, !day.removed.isEmpty {
                    section(L("지운 일 \(day.removed.count)", "Removed \(day.removed.count)")) {
                        ForEach(Array(day.removed.enumerated()), id: \.offset) { _, todo in
                            row(icon: "xmark.circle", tint: .secondary, todo: todo, strike: true, time: todo.hiddenAt)
                        }
                    }
                }
                if showsAwake, filter == .all, !day.awake.isEmpty {
                    section(L("깨어 있기", "Keep Awake") + " · \(History.durationText(day.awakeDuration))") {
                        ForEach(Array(day.awake.enumerated()), id: \.offset) { _, record in
                            awakeRow(record)
                        }
                    }
                }
            } else {
                Text(L("이날은 기록이 없어요", "Nothing recorded on this day"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isEmpty(_ day: HistoryDay) -> Bool {
        switch filter {
        case .all: day.completed.isEmpty && day.removed.isEmpty && (day.awake.isEmpty || !showsAwake)
        case .completed: day.completed.isEmpty
        case .removed: day.removed.isEmpty
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// 메모가 있으면 제목 아래에 작게 붙인다
    private func row(icon: String, tint: Color, todo: HistoryTodo, strike: Bool, time: Date?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(todo.title)
                        .strikethrough(strike)
                        .foregroundStyle(strike ? .secondary : .primary)
                    if let dueDate = todo.dueDate {
                        Text(L("기한 ", "Due ") + TodoDue.label(dueDate, now: Date()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !todo.note.isEmpty {
                    Text(todo.note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            Spacer()
            if let time {
                Text(History.clock(time))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func awakeRow(_ record: HistoryAwake) -> some View {
        HStack(spacing: 8) {
            Image(systemName: record.usedLidMode ? "flame.fill" : "flame")
                .foregroundStyle(.orange)
            Text(History.clock(record.startedAt) + L(" ~ ", " – ") + History.clock(record.endedAt))
                .monospacedDigit()
            Text(History.durationText(record.duration))
                .foregroundStyle(.secondary)
            Spacer()
            Text([History.optionLabel(record.optionLabel), record.usedLidMode ? L("뚜껑 닫아도 유지", "Closed-Lid Mode") : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

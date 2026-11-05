import LanternKit
import SwiftUI

// 할 일 줄에서 말풍선으로 띄우는 편집 화면. 패널 안에서 바로 고치면 보는 것과 고치는 것이 헷갈려서 따로 띄운다

/// 메모 추가·편집. Enter는 줄바꿈, ⌘Enter·"저장"으로 저장, Esc·"취소"로 버린다
struct TodoNoteEditor: View {
    let title: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(title: String, note: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
        _draft = State(initialValue: note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(String(localized: "메모를 적어요"))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .scrollContentBackground(.hidden)
                    // 글 상자 안쪽 여백만큼 당겨 안내 글과 줄을 맞춘다
                    .padding(.leading, -5)
                    .focused($isFocused)
            }
            .font(.system(size: 12.5))
            .padding(8)
            .frame(height: 120)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.6)))
            HStack(spacing: 8) {
                Text(String(localized: "⌘↩ 저장"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(String(localized: "취소"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "저장")) { onSave(draft) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { isFocused = true }
    }
}

/// 기한 고르기: 한 달 달력에서 날짜를 누르고 "정하기"
struct TodoDueEditor: View {
    let title: String
    /// 지금 정해진 기한. 있으면 "기한 없애기"를 보여 준다
    let current: Date?
    let onSave: (Date?) -> Void
    let onCancel: () -> Void

    @State private var selected: Date
    /// 보고 있는 달 (그달 아무 날)
    @State private var month: Date

    private let calendar = Calendar.current
    private static var weekdays: [String] { History.weekdaySymbols() }
    private static let cellSize: CGFloat = 32

    init(title: String, current: Date?, onSave: @escaping (Date?) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.current = current
        self.onSave = onSave
        self.onCancel = onCancel
        let start = current ?? Calendar.current.startOfDay(for: Date())
        _selected = State(initialValue: start)
        _month = State(initialValue: start)
    }

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            header
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: Self.cellSize, height: 20)
                    }
                }
                ForEach(Array(TodoDue.monthGrid(containing: month, calendar: calendar).enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                            dayCell(date, now: now)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Text("\(dayTitle(selected)) · \(TodoDue.remainingText(selected, now: now, calendar: calendar))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                if current != nil {
                    Button(String(localized: "기한 없애기")) { onSave(nil) }
                }
                Spacer()
                Button(String(localized: "취소"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "정하기")) { onSave(selected) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(14)
        .fixedSize()
    }

    /// "2026년 11월   ‹ 오늘 ›"
    private var header: some View {
        HStack(spacing: 4) {
            Text(month.formatted(.dateTime.year().month(.wide).locale(Localization.locale)))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                .help(String(localized: "이전 달"))
            Button(String(localized: "오늘")) {
                let today = calendar.startOfDay(for: Date())
                month = today
                selected = today
            }
            .font(.system(size: 11.5, weight: .medium))
            Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
                .help(String(localized: "다음 달"))
        }
        .buttonStyle(.borderless)
    }

    /// 날짜 칸. 고른 날은 꽉 찬 원, 오늘은 테두리 원, 지난 날은 흐리게(고를 수는 있다)
    @ViewBuilder
    private func dayCell(_ date: Date?, now: Date) -> some View {
        if let date {
            let isSelected = calendar.isDate(date, inSameDayAs: selected)
            let isToday = calendar.isDate(date, inSameDayAs: now)
            let isPast = date < calendar.startOfDay(for: now)
            Button {
                selected = date
            } label: {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12.5, weight: isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                    .opacity(isPast && !isSelected ? 0.35 : 1)
                    .frame(width: Self.cellSize - 4, height: Self.cellSize - 4)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
                        }
                    }
                    .frame(width: Self.cellSize, height: Self.cellSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: Self.cellSize, height: Self.cellSize)
        }
    }

    /// 요일 이름을 달력의 주 시작 요일에 맞춰 돌린다
    private var weekdaySymbols: [String] {
        let start = calendar.firstWeekday - 1
        return Array(Self.weekdays[start...] + Self.weekdays[..<start])
    }

    /// "11월 7일 (토)" / "Sat, Nov 7" (시스템 날짜 형식)
    private func dayTitle(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(Localization.locale))
    }

    private func moveMonth(_ value: Int) {
        if let moved = calendar.date(byAdding: .month, value: value, to: month) { month = moved }
    }
}

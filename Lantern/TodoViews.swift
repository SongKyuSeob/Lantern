import LanternKit
import SwiftData
import SwiftUI

// MARK: - 할 일 탭 (활성 창)

/// 할 일 탭: 맨 위 입력 칸, 안 끝낸 목록(기한 임박한 것이 맨 위, 나머지는 끌어서 순서 바꾸기), 완료 묶음
struct TodoTab: View {
    let store: TodoStore
    @Bindable var state: PanelState
    let openHistory: () -> Void

    @Query(
        filter: TodoItem.openPredicate,
        sort: [SortDescriptor(\TodoItem.order), SortDescriptor(\TodoItem.createdAt)]
    ) private var openItems: [TodoItem]
    @Query(
        filter: TodoItem.donePredicate,
        sort: [SortDescriptor(\TodoItem.completedAt, order: .reverse)]
    ) private var doneItems: [TodoItem]

    @FocusState private var isAdding: Bool
    @State private var editingID: UUID?
    /// 제목 전체와 메모를 펼친 할 일 (한 번에 하나)
    @State private var expandedID: UUID?
    /// 메모를 쓰고 있는 할 일
    @State private var noteEditingID: UUID?
    /// 기한을 고르고 있는 할 일
    @State private var dueEditingID: UUID?
    @AppStorage(TodoDue.soonDaysKey) private var soonDays = TodoDue.defaultSoonDays
    /// 끌고 있는 할 일과 끈 거리(위아래)
    @State private var dragging: (id: UUID, offset: CGFloat)?

    /// 이보다 많으면 목록을 스크롤한다
    private static let maxVisibleRows = 8
    static let rowHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            addField
            if openItems.isEmpty && doneItems.isEmpty {
                Text("적어 둔 할 일은 평소 창에 위에서 세 개까지 보여요")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
            } else {
                list
            }
            HStack {
                Spacer()
                Button("기록 ›", action: openHistory)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .help("지금까지 끝낸 일 · 지운 일 · 깨어 있기를 날짜별로 봐요")
            }
            .padding(.horizontal, 2)
        }
        .onChange(of: isAdding) { syncEditingState() }
        .onChange(of: state.todoDraft) { syncEditingState() }
        .onChange(of: editingID) { syncEditingState() }
        .onChange(of: noteEditingID) { syncEditingState() }
        .onChange(of: dueEditingID) { syncEditingState() }
        // 창이 평소 상태로 바뀌거나 탭을 옮겨 이 화면이 사라지면 입력 중 표시를 푼다 (Esc·10초 무조작이 다시 동작하게)
        .onDisappear { state.isEditingText = false }
    }

    private var addField: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            TextField("할 일 추가", text: $state.todoDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isAdding)
                .onSubmit {
                    store.add(state.todoDraft)
                    state.todoDraft = ""
                    isAdding = true
                }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fillTrack))
    }

    @ViewBuilder
    private var list: some View {
        let arranged = arrangedItems
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(arranged.all.enumerated()), id: \.element.id) { index, item in
                let isDragged = dragging?.id == item.id
                let isSoon = index < arranged.soonCount
                row(item, isDragged: isDragged)
                    .offset(y: isDragged ? dragging?.offset ?? 0 : shift(at: index))
                    .zIndex(isDragged ? 1 : 0)
                    .animation(isDragged ? nil : .snappy(duration: 0.18), value: shift(at: index))
                    // 임박한 할 일은 기한 순으로 자리가 정해져 끌지 않는다. 펼친 줄은 메모 글을 끌어 고를 수 있게 끌기를 받지 않는다
                    .gesture(reorderGesture(for: item), including: isSoon || expandedID == item.id ? .subviews : .all)
            }
            // 안 끝낸 목록과 완료 묶음 사이 간격
            Color.clear.frame(height: 6)
            if !doneItems.isEmpty {
                doneHeader
                ForEach(doneItems) { item in
                    row(item, isDragged: false)
                }
            }
        }
        let rowCount = openItems.count + doneItems.count + (doneItems.isEmpty ? 0 : 1)
        if rowCount > Self.maxVisibleRows {
            ScrollView {
                // 스크롤 막대가 내용 위에 겹쳐 그려져서, 줄 오른쪽의 기한·×를 가리지 않게 막대 폭만큼 비운다
                rows.padding(.trailing, 10)
            }
            .frame(height: CGFloat(Self.maxVisibleRows) * Self.rowHeight)
        } else {
            rows
        }
    }

    private func row(_ item: TodoItem, isDragged: Bool) -> some View {
        TodoRow(
            item: item, store: store, editingID: $editingID, expandedID: $expandedID,
            noteEditingID: $noteEditingID, dueEditingID: $dueEditingID, isDragged: isDragged
        )
    }

    /// 화면 순서: 임박한 할 일(기한 순) 다음에 나머지(끌어서 정한 순서)
    private var arrangedItems: (all: [TodoItem], soonCount: Int) {
        let arranged = TodoDue.arrange(openItems, now: Date(), days: soonDays)
        return (arranged.soon + arranged.rest, arranged.soon.count)
    }

    private var doneHeader: some View {
        HStack {
            Text("완료 \(doneItems.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Button("지우기") { store.clearDone() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.primaryLight)
        }
        .padding(.horizontal, 2)
        .frame(height: Self.rowHeight)
    }

    // MARK: 끌어서 순서 바꾸기

    // 시스템 끌어 놓기(draggable·dropDestination)는 이 창에서 동작하지 않는다.
    // 평소 상태의 클릭 통과(ignoresMouseEvents)를 한 번 켰다 끄거나 창을 투명하게 두면 놓을 자리를 찾지 못한다.
    // 그래서 창 안에서 줄을 직접 움직인다

    /// 안 끝낸 할 일을 위아래로 끈다. 놓으면 끈 자리로 옮긴다
    private func reorderGesture(for item: TodoItem) -> some Gesture {
        // 끄는 줄이 따라 움직이므로 화면 기준으로 잰다
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard editingID != item.id else { return }
                // 줄 높이가 모두 같아야 비켜 줄 거리를 셀 수 있어서, 펼친 줄을 먼저 접는다
                if expandedID != nil { expandedID = nil }
                if dueEditingID != nil { dueEditingID = nil }
                dragging = (item.id, value.translation.height)
            }
            .onEnded { _ in
                guard let (source, target) = dragTarget() else { return }
                // 다른 줄은 이미 비켜 있으므로, 옮긴 결과와 같은 자리에 애니메이션 없이 놓는다
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if source != target {
                        // 놓은 자리에 원래 있던 할 일 앞으로 옮긴다 (끄는 줄을 뺀 목록 기준)
                        let others = arrangedItems.all.filter { $0.id != item.id }
                        store.move(item, before: target < others.count ? others[target] : nil)
                    }
                    dragging = nil
                }
            }
    }

    /// 끄는 할 일의 원래 자리와 지금 놓으면 갈 자리. 임박한 할 일 칸 위로는 올라가지 않는다
    private func dragTarget() -> (source: Int, target: Int)? {
        let arranged = arrangedItems
        guard let dragging, let source = arranged.all.firstIndex(where: { $0.id == dragging.id }) else { return nil }
        let target = source + Int((dragging.offset / Self.rowHeight).rounded())
        return (source, min(max(target, arranged.soonCount), arranged.all.count - 1))
    }

    /// 끄는 동안 다른 줄이 비켜 주는 거리
    private func shift(at index: Int) -> CGFloat {
        guard let (source, target) = dragTarget() else { return 0 }
        if source < target, index > source, index <= target { return -Self.rowHeight }
        if target < source, index >= target, index < source { return Self.rowHeight }
        return 0
    }

    /// 입력 중에는 10초 무조작·Esc로 창이 닫히지 않게 한다.
    /// 메뉴·말풍선이 닫히면 창이 첫 입력 칸("할 일 추가")에 포커스를 돌려주므로, 그 칸은 글을 적었을 때만 입력 중으로 본다
    private func syncEditingState() {
        state.isEditingText = (isAdding && !state.todoDraft.isEmpty) || editingID != nil || noteEditingID != nil || dueEditingID != nil
    }
}

/// 할 일 한 줄. 동그라미를 누르면 끝내기·되돌리기, 더블클릭하면 이름 고치기, 마우스를 올리면 ×로 지우기.
/// 오른쪽 클릭하면 메모 · 기한 · 이름 바꾸기 · 지우기 메뉴. 메모와 기한은 말풍선(`TodoNoteEditor`, `TodoDueEditor`)에서 고친다.
/// 메모가 있으면 제목 옆 아이콘을 눌러 제목 전체와 메모를 펼쳐 본다 (읽기 전용, "편집"으로 말풍선).
/// 기한이 있으면 오른쪽에 "11/7", 임박했거나 지났으면 주황색.
/// 안 끝낸 할 일은 끌어서 순서를 바꾼다 (`TodoTab.reorderGesture`)
private struct TodoRow: View {
    let item: TodoItem
    let store: TodoStore
    @Binding var editingID: UUID?
    @Binding var expandedID: UUID?
    @Binding var noteEditingID: UUID?
    @Binding var dueEditingID: UUID?
    /// 끌고 있는 줄이면 바탕을 깔아 다른 줄과 겹쳐도 읽히게 한다
    let isDragged: Bool

    @State private var isHovering = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool
    @AppStorage(TodoDue.soonDaysKey) private var soonDays = TodoDue.defaultSoonDays

    private var isExpanded: Bool { expandedID == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    store.setDone(item, !item.isDone)
                } label: {
                    // 테두리만 있는 동그라미는 선 위만 눌리므로, 둘레까지 넉넉히 누를 수 있게 한다
                    checkmark
                        .frame(width: 20, height: TodoTab.rowHeight)
                        .contentShape(Rectangle())
                        // 넓힌 만큼 양옆을 줄여 줄 배치는 그대로 둔다
                        .padding(.horizontal, -3.5)
                }
                .buttonStyle(.plain)
                .help(item.isDone ? "되돌리기" : "끝내기")

                // 메모 표시는 제목 바로 뒤에 붙여, 마우스를 올려 ×가 나타나도 자리가 바뀌지 않게 한다
                HStack(alignment: .top, spacing: 3) {
                    title
                    if !item.note.isEmpty {
                        noteToggle
                    }
                }
                Spacer(minLength: 4)
                if let dueDate = item.dueDate {
                    dueLabel(dueDate)
                }
                if isHovering && editingID != item.id {
                    Button {
                        store.hide(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 16, height: TodoTab.rowHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("지우기 (기록에는 남아요)")
                }
            }
            if isExpanded {
                noteView
                    // 제목 글자와 줄을 맞춘다 (동그라미 13 + 간격 8)
                    .padding(.leading, 21)
                    .padding(.bottom, 7)
            }
        }
        // 말풍선은 패널 바깥(왼쪽)으로 띄운다. 패널이 화면 가장자리에 붙어 있어서 반대쪽은 자리가 없다
        .popover(isPresented: isPresented($noteEditingID), arrowEdge: .leading) {
            TodoNoteEditor(title: item.title, note: item.note) { note in
                store.setNote(item, to: note)
                noteEditingID = nil
                if item.note.isEmpty, isExpanded { expandedID = nil }
            } onCancel: {
                noteEditingID = nil
            }
        }
        .popover(isPresented: isPresented($dueEditingID), arrowEdge: .leading) {
            TodoDueEditor(title: item.title, current: item.dueDate) { date in
                store.setDueDate(item, to: date)
                dueEditingID = nil
            } onCancel: {
                dueEditingID = nil
            }
        }
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .background {
            if isDragged || isExpanded {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDragged ? Theme.background.opacity(0.55) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 6).fill(isDragged ? Theme.fillTrack : .white.opacity(0.04)))
                    .padding(.horizontal, -4)
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            // 메뉴가 닫힐 때 창이 첫 입력 칸("할 일 추가")에 포커스를 돌려주므로, 그 뒤에 입력 칸을 연다
            Button(item.note.isEmpty ? "메모 추가…" : "메모 편집…") {
                afterMenuCloses { noteEditingID = item.id }
            }
            Button(item.dueDate == nil ? "기한 정하기…" : "기한 바꾸기…") {
                afterMenuCloses { dueEditingID = item.id }
            }
            if item.dueDate != nil {
                Button("기한 없애기") { store.setDueDate(item, to: nil) }
            }
            Button("이름 바꾸기") { afterMenuCloses { editingID = item.id } }
            Divider()
            Button("지우기") { store.hide(item) }
        }
    }

    @ViewBuilder
    private var title: some View {
        if editingID == item.id {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isFocused)
                .onSubmit(finishEditing)
                .onAppear {
                    draft = item.title
                    isFocused = true
                }
                .onChange(of: isFocused) { if !isFocused { finishEditing() } }
                // 고치던 중에 창이 바뀌어 사라져도 고친 이름을 저장한다
                .onDisappear(perform: finishEditing)
                .frame(minHeight: TodoTab.rowHeight)
        } else {
            // 펼치면 잘린 제목도 끝까지 보여 준다
            Text(item.title)
                .font(.system(size: 12.5))
                .strikethrough(item.isDone, color: .white.opacity(0.35))
                .foregroundStyle(.white.opacity(item.isDone ? 0.35 : 0.88))
                .lineLimit(isExpanded ? nil : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: isExpanded)
                .padding(.vertical, isExpanded ? 5 : 0)
                .frame(minHeight: TodoTab.rowHeight)
                .onTapGesture(count: 2) { editingID = item.id }
        }
    }

    /// 메모가 있다는 표시. 누르면 펼치거나 접는다
    private var noteToggle: some View {
        Button {
            if isExpanded {
                expandedID = nil
            } else {
                expandedID = item.id
            }
        } label: {
            Image(systemName: "text.alignleft")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(isExpanded ? 0.6 : 0.3))
                .frame(width: 16, height: TodoTab.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "메모 접기" : "메모 보기")
    }

    /// 펼친 메모 (읽기 전용, 글자는 골라 복사할 수 있다). 끝의 "편집"으로 말풍선을 띄운다
    private var noteView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.note)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.62))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("편집") { noteEditingID = item.id }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.primaryLight)
        }
    }

    /// "11/7". 임박했거나 지났으면 주황색 (끝낸 일은 흐리게)
    private func dueLabel(_ dueDate: Date) -> some View {
        let now = Date()
        let isSoon = !item.isDone && TodoDue.isSoon(dueDate, now: now, days: soonDays)
        return Text(TodoDue.label(dueDate, now: now))
            .font(.system(size: 10.5, weight: isSoon ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(isSoon ? AnyShapeStyle(Theme.flame) : AnyShapeStyle(.white.opacity(item.isDone ? 0.25 : 0.4)))
            .frame(height: TodoTab.rowHeight)
            .help("기한 " + History.dateTitle(dueDate))
    }

    @ViewBuilder
    private var checkmark: some View {
        if item.isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.primary.opacity(0.7))
        } else {
            Circle()
                .strokeBorder(.white.opacity(0.45), lineWidth: 1.2)
                .frame(width: 13, height: 13)
        }
    }

    private func afterMenuCloses(_ action: @escaping @MainActor () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            action()
        }
    }

    private func finishEditing() {
        guard editingID == item.id else { return }
        editingID = nil
        store.rename(item, to: draft)
    }

    /// 이 할 일을 고치는 중인지를 말풍선 표시 여부로 바꾼다. 말풍선이 닫히면(바깥 클릭 등) 고치기를 끝낸다
    private func isPresented(_ editingID: Binding<UUID?>) -> Binding<Bool> {
        Binding(
            get: { editingID.wrappedValue == item.id },
            set: { if !$0, editingID.wrappedValue == item.id { editingID.wrappedValue = nil } }
        )
    }
}

// MARK: - 평소 창

/// 평소 창에 보이는 할 일: 위에서 세 개(임박한 것 먼저), 더 있으면 "⋯ n more". 없으면 아무것도 그리지 않는다
struct PassiveTodoList: View {
    @Query(
        filter: TodoItem.openPredicate,
        sort: [SortDescriptor(\TodoItem.order), SortDescriptor(\TodoItem.createdAt)]
    ) private var openItems: [TodoItem]
    @AppStorage(TodoDue.soonDaysKey) private var soonDays = TodoDue.defaultSoonDays

    static let visibleCount = 3

    var body: some View {
        if !openItems.isEmpty {
            // 평소 창은 오래 떠 있으므로, 날짜가 바뀌면 임박 여부와 순서를 다시 정한다
            TimelineView(.everyMinute) { context in
                list(now: context.date)
            }
        }
    }

    private func list(now: Date) -> some View {
        let arranged = TodoDue.arrange(openItems, now: now, days: soonDays)
        let items = arranged.soon + arranged.rest
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.divider).frame(height: 1)
            ForEach(items.prefix(Self.visibleCount)) { item in
                HStack(spacing: 7) {
                    Circle()
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1.1)
                        .frame(width: 9, height: 9)
                    Text(item.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let dueDate = item.dueDate {
                        Spacer(minLength: 4)
                        let isSoon = TodoDue.isSoon(dueDate, now: now, days: soonDays)
                        Text(TodoDue.label(dueDate, now: now))
                            .font(.system(size: 10.5, weight: isSoon ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isSoon ? AnyShapeStyle(Theme.flameTextPassive) : AnyShapeStyle(.white.opacity(0.4)))
                    }
                }
            }
            if openItems.count > Self.visibleCount {
                // 할 일 줄과 같은 자리에 맞춰, 동그라미 대신 흐린 ⋯를 둔다
                HStack(spacing: 7) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 9)
                    Text("\(openItems.count - Self.visibleCount) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }
}

/// 접힌 바 오른쪽의 "할 일 3"
struct CollapsedTodoCount: View {
    @Query(filter: TodoItem.openPredicate) private var openItems: [TodoItem]

    var body: some View {
        if !openItems.isEmpty {
            Text("할 일 \(openItems.count)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
        }
    }
}

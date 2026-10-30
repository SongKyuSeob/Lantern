import LanternKit
import SwiftData
import SwiftUI

// MARK: - 할 일 탭 (활성 창)

/// 할 일 탭: 맨 위 입력 칸, 안 끝낸 목록(끌어서 순서 바꾸기), 완료 묶음
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
        .onChange(of: editingID) { syncEditingState() }
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
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(openItems.enumerated()), id: \.element.id) { index, item in
                let isDragged = dragging?.id == item.id
                TodoRow(item: item, store: store, editingID: $editingID, isDragged: isDragged)
                    .offset(y: isDragged ? dragging?.offset ?? 0 : shift(at: index))
                    .zIndex(isDragged ? 1 : 0)
                    .animation(isDragged ? nil : .snappy(duration: 0.18), value: shift(at: index))
                    .gesture(reorderGesture(for: item))
            }
            // 안 끝낸 목록과 완료 묶음 사이 간격
            Color.clear.frame(height: 6)
            if !doneItems.isEmpty {
                doneHeader
                ForEach(doneItems) { item in
                    TodoRow(item: item, store: store, editingID: $editingID, isDragged: false)
                }
            }
        }
        let rowCount = openItems.count + doneItems.count + (doneItems.isEmpty ? 0 : 1)
        if rowCount > Self.maxVisibleRows {
            ScrollView {
                rows
            }
            .frame(height: CGFloat(Self.maxVisibleRows) * Self.rowHeight)
        } else {
            rows
        }
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
                dragging = (item.id, value.translation.height)
            }
            .onEnded { _ in
                guard let (source, target) = dragTarget() else { return }
                // 다른 줄은 이미 비켜 있으므로, 옮긴 결과와 같은 자리에 애니메이션 없이 놓는다
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    if source != target {
                        store.move(fromOffsets: IndexSet(integer: source), toOffset: target > source ? target + 1 : target)
                    }
                    dragging = nil
                }
            }
    }

    /// 끄는 할 일의 원래 자리와 지금 놓으면 갈 자리
    private func dragTarget() -> (source: Int, target: Int)? {
        guard let dragging, let source = openItems.firstIndex(where: { $0.id == dragging.id }) else { return nil }
        let target = source + Int((dragging.offset / Self.rowHeight).rounded())
        return (source, min(max(target, 0), openItems.count - 1))
    }

    /// 끄는 동안 다른 줄이 비켜 주는 거리
    private func shift(at index: Int) -> CGFloat {
        guard let (source, target) = dragTarget() else { return 0 }
        if source < target, index > source, index <= target { return -Self.rowHeight }
        if target < source, index >= target, index < source { return Self.rowHeight }
        return 0
    }

    /// 입력 중에는 10초 무조작·Esc로 창이 닫히지 않게 한다
    private func syncEditingState() {
        state.isEditingText = isAdding || editingID != nil
    }
}

/// 할 일 한 줄. 동그라미를 누르면 끝내기·되돌리기, 더블클릭하면 이름 고치기, 마우스를 올리면 ×로 지우기.
/// 안 끝낸 할 일은 끌어서 순서를 바꾼다 (`TodoTab.reorderGesture`)
private struct TodoRow: View {
    let item: TodoItem
    let store: TodoStore
    @Binding var editingID: UUID?
    /// 끌고 있는 줄이면 바탕을 깔아 다른 줄과 겹쳐도 읽히게 한다
    let isDragged: Bool

    @State private var isHovering = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
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
            } else {
                Text(item.title)
                    .font(.system(size: 12.5))
                    .strikethrough(item.isDone, color: .white.opacity(0.35))
                    .foregroundStyle(.white.opacity(item.isDone ? 0.35 : 0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) { editingID = item.id }
            }
            Spacer(minLength: 4)
            if isHovering && editingID != item.id {
                Button {
                    store.hide(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("지우기 (기록에는 남아요)")
            }
        }
        .padding(.horizontal, 2)
        .frame(height: TodoTab.rowHeight)
        .contentShape(Rectangle())
        .background {
            if isDragged {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.background.opacity(0.55))
                    .overlay(RoundedRectangle(cornerRadius: 6).fill(Theme.fillTrack))
                    .padding(.horizontal, -4)
            }
        }
        .onHover { isHovering = $0 }
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

    private func finishEditing() {
        guard editingID == item.id else { return }
        editingID = nil
        store.rename(item, to: draft)
    }
}

// MARK: - 평소 창

/// 평소 창에 보이는 할 일: 위에서 세 개, 더 있으면 "⋯ n more". 없으면 아무것도 그리지 않는다
struct PassiveTodoList: View {
    @Query(
        filter: TodoItem.openPredicate,
        sort: [SortDescriptor(\TodoItem.order), SortDescriptor(\TodoItem.createdAt)]
    ) private var openItems: [TodoItem]

    static let visibleCount = 3

    var body: some View {
        if !openItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(Theme.divider).frame(height: 1)
                ForEach(openItems.prefix(Self.visibleCount)) { item in
                    HStack(spacing: 7) {
                        Circle()
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1.1)
                            .frame(width: 9, height: 9)
                        Text(item.title)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
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

import LanternKit
import SwiftData
import SwiftUI

// MARK: - 할 일 탭 (활성 창)

/// 할 일 탭: 맨 위 입력 칸, 안 끝낸 목록(끌어서 순서 바꾸기), 완료 묶음
struct TodoTab: View {
    let store: TodoStore
    @Bindable var state: PanelState

    @Query(
        filter: #Predicate<TodoItem> { !$0.isDone },
        sort: [SortDescriptor(\TodoItem.order), SortDescriptor(\TodoItem.createdAt)]
    ) private var openItems: [TodoItem]
    @Query(
        filter: #Predicate<TodoItem> { $0.isDone },
        sort: [SortDescriptor(\TodoItem.completedAt, order: .reverse)]
    ) private var doneItems: [TodoItem]

    @State private var newTitle = ""
    @FocusState private var isAdding: Bool
    @State private var editingID: UUID?

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
        }
        .onChange(of: isAdding) { syncEditingState() }
        .onChange(of: editingID) { syncEditingState() }
    }

    private var addField: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            TextField("할 일 추가", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isAdding)
                .onSubmit {
                    store.add(newTitle)
                    newTitle = ""
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
            ForEach(openItems) { item in
                TodoRow(item: item, store: store, editingID: $editingID, openItems: openItems)
            }
            // 목록 맨 아래로 끌어 놓을 자리
            TodoDropZone(store: store, openItems: openItems)
            if !doneItems.isEmpty {
                doneHeader
                ForEach(doneItems) { item in
                    TodoRow(item: item, store: store, editingID: $editingID, openItems: openItems)
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

    /// 입력 중에는 10초 무조작·Esc로 창이 닫히지 않게 한다
    private func syncEditingState() {
        state.isEditingText = isAdding || editingID != nil
    }
}

/// 할 일 한 줄. 동그라미를 누르면 끝내기·되돌리기, 더블클릭하면 이름 고치기, 마우스를 올리면 ×로 지우기.
/// 안 끝낸 할 일은 끌어서 다른 줄 위에 놓으면 그 자리로 옮긴다
private struct TodoRow: View {
    let item: TodoItem
    let store: TodoStore
    @Binding var editingID: UUID?
    let openItems: [TodoItem]

    @State private var isHovering = false
    @State private var isDropTarget = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.setDone(item, !item.isDone)
            } label: {
                checkmark
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
                    store.delete(item)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("지우기")
            }
        }
        .padding(.horizontal, 2)
        .frame(height: TodoTab.rowHeight)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            // 끌어 놓을 자리 표시
            if isDropTarget {
                Rectangle().fill(Theme.primary).frame(height: 2).offset(y: -1)
            }
        }
        .onHover { isHovering = $0 }
        .modifier(OpenItemDragging(item: item, store: store, openItems: openItems, isDropTarget: $isDropTarget))
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

/// 안 끝낸 할 일만 끌고 놓을 수 있게 한다. 놓으면 놓은 줄 바로 위로 옮긴다
private struct OpenItemDragging: ViewModifier {
    let item: TodoItem
    let store: TodoStore
    let openItems: [TodoItem]
    @Binding var isDropTarget: Bool

    func body(content: Content) -> some View {
        if item.isDone {
            content
        } else {
            content
                .draggable(item.id.uuidString) {
                    Text(item.title)
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.background))
                }
                .dropDestination(for: String.self) { ids, _ in
                    guard let target = openItems.firstIndex(where: { $0.id == item.id }) else { return false }
                    return TodoDrop.move(ids, before: target, store: store, openItems: openItems)
                } isTargeted: { isDropTarget = $0 }
        }
    }
}

/// 목록 맨 아래에 놓을 수 있는 얇은 자리
private struct TodoDropZone: View {
    let store: TodoStore
    let openItems: [TodoItem]
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .overlay(alignment: .top) {
                if isTargeted { Rectangle().fill(Theme.primary).frame(height: 2) }
            }
            .dropDestination(for: String.self) { ids, _ in
                TodoDrop.move(ids, before: openItems.count, store: store, openItems: openItems)
            } isTargeted: { isTargeted = $0 }
    }
}

private enum TodoDrop {
    /// 끌어 온 할 일을 `target` 번째 줄 앞으로 옮긴다
    @MainActor
    static func move(_ ids: [String], before target: Int, store: TodoStore, openItems: [TodoItem]) -> Bool {
        guard let id = ids.first.flatMap(UUID.init(uuidString:)),
              let source = openItems.firstIndex(where: { $0.id == id })
        else { return false }
        store.move(fromOffsets: IndexSet(integer: source), toOffset: target)
        return true
    }
}

// MARK: - 평소 창

/// 평소 창에 보이는 할 일: 위에서 세 개, 더 있으면 "⋯ n more". 없으면 아무것도 그리지 않는다
struct PassiveTodoList: View {
    @Query(
        filter: #Predicate<TodoItem> { !$0.isDone },
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
    @Query(filter: #Predicate<TodoItem> { !$0.isDone }) private var openItems: [TodoItem]

    var body: some View {
        if !openItems.isEmpty {
            Text("할 일 \(openItems.count)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
        }
    }
}

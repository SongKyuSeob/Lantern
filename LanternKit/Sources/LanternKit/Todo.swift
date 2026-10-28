import Foundation
import SwiftData

/// 할 일 하나.
///
/// 나중에 iCloud 동기화(CloudKit)를 붙일 수 있도록 모든 속성에 기본값을 두고, 고유 제약은 걸지 않는다.
@Model
public final class TodoItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var isDone: Bool = false
    /// 안 끝낸 할 일의 순서. 작을수록 위. 평소 창에는 위에서 세 개가 보인다
    public var order: Double = 0
    public var createdAt: Date = Date()
    public var completedAt: Date?

    public init(title: String, order: Double, createdAt: Date = Date()) {
        self.title = title
        self.order = order
        self.createdAt = createdAt
    }
}

/// 할 일 목록을 읽고 바꾼다. 목록은 하나뿐이고, 날짜로 나누지 않는다.
///
/// - 새 할 일은 안 끝낸 목록 맨 아래에 붙는다
/// - 끝내면 줄이 그어져 완료 묶음으로 내려가고, 되돌리면 안 끝낸 목록 맨 아래로 돌아간다
/// - 순서는 끌어서 바꾼다
@MainActor
public final class TodoStore {
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    /// 저장 위치를 지정한 저장소. `url`이 `nil`이면 메모리에만 둔다 (테스트용)
    public static func makeContainer(url: URL?) throws -> ModelContainer {
        let configuration = if let url {
            ModelConfiguration("Lantern", schema: Schema([TodoItem.self]), url: url)
        } else {
            ModelConfiguration("Lantern", schema: Schema([TodoItem.self]), isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: TodoItem.self, configurations: configuration)
    }

    // MARK: - 읽기

    /// 안 끝낸 할 일, 위에서부터
    public func openItems() -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { !$0.isDone },
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 끝낸 할 일, 최근에 끝낸 것부터
    public func doneItems() -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate { $0.isDone },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - 바꾸기

    /// 앞뒤 공백을 지운 제목이 비어 있으면 추가하지 않는다
    @discardableResult
    public func add(_ title: String, now: Date = Date()) -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let item = TodoItem(title: trimmed, order: nextOrder(), createdAt: now)
        context.insert(item)
        save()
        return item
    }

    public func setDone(_ item: TodoItem, _ isDone: Bool, now: Date = Date()) {
        guard item.isDone != isDone else { return }
        if isDone {
            item.isDone = true
            item.completedAt = now
        } else {
            item.order = nextOrder()
            item.isDone = false
            item.completedAt = nil
        }
        save()
    }

    /// 제목을 비우면 지운다
    public func rename(_ item: TodoItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(item)
        } else if trimmed != item.title {
            item.title = trimmed
            save()
        }
    }

    public func delete(_ item: TodoItem) {
        context.delete(item)
        save()
    }

    /// 안 끝낸 목록에서 끌어서 옮긴다 (SwiftUI `onMove`와 같은 인자)
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var items = openItems()
        // SwiftUI의 Array.move(fromOffsets:toOffset:)와 같은 동작 (LanternKit은 SwiftUI에 기대지 않는다)
        let moving = source.map { items[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { items.remove(at: index) }
        items.insert(contentsOf: moving, at: insertAt)
        for (index, item) in items.enumerated() {
            item.order = Double(index)
        }
        save()
    }

    public func clearDone() {
        for item in doneItems() { context.delete(item) }
        save()
    }

    // MARK: - 내부

    private func nextOrder() -> Double {
        (openItems().last?.order ?? -1) + 1
    }

    private func save() {
        try? context.save()
    }
}

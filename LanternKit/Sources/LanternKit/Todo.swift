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
    /// 작은 창에서 치운 시각. 끝낸 일은 "지우기", 안 끝낸 일은 ×로 치운다.
    /// 실제로 지우지 않고 기록 창에 남긴다 (끝낸 일 / 지운 일)
    public var hiddenAt: Date?

    /// 안 끝내고 지운 일
    public var isRemoved: Bool { !isDone && hiddenAt != nil }

    public init(title: String, order: Double, createdAt: Date = Date()) {
        self.title = title
        self.order = order
        self.createdAt = createdAt
    }
}

public extension TodoItem {
    /// 작은 창의 안 끝낸 목록 (치운 것 제외)
    static var openPredicate: Predicate<TodoItem> {
        #Predicate<TodoItem> { item in item.isDone == false && item.hiddenAt == nil }
    }

    /// 작은 창의 완료 묶음 (치운 것 제외)
    static var donePredicate: Predicate<TodoItem> {
        #Predicate<TodoItem> { item in item.isDone == true && item.hiddenAt == nil }
    }
}

/// 할 일 목록을 읽고 바꾼다. 목록은 하나뿐이고, 날짜로 나누지 않는다.
///
/// - 새 할 일은 안 끝낸 목록 맨 아래에 붙는다
/// - 끝내면 줄이 그어져 완료 묶음으로 내려가고, 되돌리면 안 끝낸 목록 맨 아래로 돌아간다
/// - 순서는 끌어서 바꾼다
/// - 치운 할 일(`hiddenAt`)은 작은 창에서만 사라지고 기록에는 남는다
@MainActor
public final class TodoStore {
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
    }

    /// 랜턴이 저장하는 모든 것(할 일, 깨어 있기 기록). `url`이 `nil`이면 메모리에만 둔다 (테스트용)
    public static func makeContainer(url: URL?) throws -> ModelContainer {
        let schema = Schema([TodoItem.self, AwakeRecord.self])
        let configuration = if let url {
            ModelConfiguration("Lantern", schema: schema, url: url)
        } else {
            ModelConfiguration("Lantern", schema: schema, isStoredInMemoryOnly: true)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }

    // MARK: - 읽기

    /// 안 끝낸 할 일, 위에서부터
    public func openItems() -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: TodoItem.openPredicate,
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 끝낸 할 일, 최근에 끝낸 것부터
    public func doneItems() -> [TodoItem] {
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: TodoItem.donePredicate,
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

    /// 제목을 비우면 치운다
    public func rename(_ item: TodoItem, to title: String, now: Date = Date()) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            hide(item, now: now)
        } else if trimmed != item.title {
            item.title = trimmed
            save()
        }
    }

    /// 작은 창에서 치운다. 기록에는 남는다
    public func hide(_ item: TodoItem, now: Date = Date()) {
        guard item.hiddenAt == nil else { return }
        item.hiddenAt = now
        save()
    }

    /// 정말 지운다 (기록에서도 사라짐)
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

    /// 완료 묶음을 작은 창에서 치운다. 기록에는 남는다
    public func clearDone(now: Date = Date()) {
        for item in doneItems() { item.hiddenAt = now }
        save()
    }

    /// 기록 창에 보여 줄 할 일 (치운 것 포함 전부)
    public func allItems() -> [TodoItem] {
        (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
    }

    // MARK: - 내부

    private func nextOrder() -> Double {
        (openItems().last?.order ?? -1) + 1
    }

    private func save() {
        try? context.save()
    }
}

/// 깨어 있기 한 번의 기록. 기록 창에서 날짜별로 보여 준다
@Model
public final class AwakeRecord {
    public var id: UUID = UUID()
    public var startedAt: Date = Date()
    public var endedAt: Date = Date()
    /// "2시간", "에이전트가 끝날 때까지"처럼 고른 옵션
    public var optionLabel: String = ""
    /// `AwakeEndReason`의 rawValue
    public var endReason: String = ""
    public var usedLidMode: Bool = false

    public init(startedAt: Date, endedAt: Date, optionLabel: String, endReason: AwakeEndReason, usedLidMode: Bool) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.optionLabel = optionLabel
        self.endReason = endReason.rawValue
        self.usedLidMode = usedLidMode
    }

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

@MainActor
public extension TodoStore {
    /// 끝난 깨어 있기 세션을 기록한다. 1분보다 짧으면 남기지 않는다 (잘못 눌렀다 끈 경우)
    func recordAwake(_ session: AwakeSession, endedAt: Date, optionLabel: String, reason: AwakeEndReason, usedLidMode: Bool) {
        guard endedAt.timeIntervalSince(session.startedAt) >= 60 else { return }
        context.insert(AwakeRecord(
            startedAt: session.startedAt, endedAt: endedAt,
            optionLabel: optionLabel, endReason: reason, usedLidMode: usedLidMode
        ))
        try? context.save()
    }

    func awakeRecords() -> [AwakeRecord] {
        (try? context.fetch(FetchDescriptor<AwakeRecord>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
    }
}

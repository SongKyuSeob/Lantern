import Foundation
import LanternKit
import Testing

@MainActor
@Suite("할 일 목록")
struct TodoStoreTests {
    private func makeStore() throws -> TodoStore {
        TodoStore(container: try TodoStore.makeContainer(url: nil))
    }

    private func titles(_ items: [TodoItem]) -> [String] {
        items.map(\.title)
    }

    @Test("새 할 일은 맨 아래에 붙고, 공백뿐이면 추가하지 않는다") func addAppends() throws {
        let store = try makeStore()
        store.add("하나")
        store.add("  둘  ")
        #expect(store.add("   ") == nil)
        #expect(titles(store.openItems()) == ["하나", "둘"])
    }

    @Test("끝내면 완료 묶음으로, 되돌리면 안 끝낸 목록 맨 아래로") func toggleDone() throws {
        let store = try makeStore()
        let first = try #require(store.add("하나"))
        store.add("둘")
        store.setDone(first, true)
        #expect(titles(store.openItems()) == ["둘"])
        #expect(titles(store.doneItems()) == ["하나"])
        #expect(first.completedAt != nil)
        store.setDone(first, false)
        #expect(titles(store.openItems()) == ["둘", "하나"])
        #expect(first.completedAt == nil)
    }

    @Test("완료 묶음은 최근에 끝낸 것부터") func doneOrder() throws {
        let store = try makeStore()
        let a = try #require(store.add("가"))
        let b = try #require(store.add("나"))
        store.setDone(a, true, now: Date(timeIntervalSince1970: 100))
        store.setDone(b, true, now: Date(timeIntervalSince1970: 200))
        #expect(titles(store.doneItems()) == ["나", "가"])
    }

    @Test("끌어서 순서를 바꾼다") func move() throws {
        let store = try makeStore()
        for title in ["가", "나", "다", "라"] { store.add(title) }
        store.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(titles(store.openItems()) == ["라", "가", "나", "다"])
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(titles(store.openItems()) == ["가", "나", "다", "라"])
        store.add("마")
        #expect(titles(store.openItems()).last == "마")
    }

    @Test("이름을 비우면 지우고, 공백은 다듬는다") func rename() throws {
        let store = try makeStore()
        let item = try #require(store.add("하나"))
        store.rename(item, to: "  바뀐 이름 ")
        #expect(titles(store.openItems()) == ["바뀐 이름"])
        store.rename(item, to: "  ")
        #expect(store.openItems().isEmpty)
    }

    @Test("완료한 것만 지운다") func clearDone() throws {
        let store = try makeStore()
        let done = try #require(store.add("끝남"))
        store.add("남음")
        store.setDone(done, true)
        store.clearDone()
        #expect(titles(store.openItems()) == ["남음"])
        #expect(store.doneItems().isEmpty)
    }

    @Test("파일에 저장하고 다시 열면 그대로다") func persists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let store = TodoStore(container: try TodoStore.makeContainer(url: url))
            store.add("남아 있어야 함")
        }
        let reopened = TodoStore(container: try TodoStore.makeContainer(url: url))
        #expect(titles(reopened.openItems()) == ["남아 있어야 함"])
    }
}

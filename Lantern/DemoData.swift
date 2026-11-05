#if DEBUG
import Foundation
import LanternKit

/// README 화면 캡처용 시연 데이터 (디버그 빌드 전용).
///
/// `LANTERN_DEMO=1`로 실행하면 실제 저장 파일 대신 메모리에 예시 할 일과 기록을 채운 저장소를 쓴다.
/// 끄면 사라지므로 실제 할 일·기록에는 흔적이 남지 않는다.
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["LANTERN_DEMO"] == "1" }
    /// 화면을 그림으로 저장하는 중 (`LANTERN_RENDER`). 유리 효과 대신 단색 바탕으로 그린다
    static var rendersFlatBackground: Bool { ProcessInfo.processInfo.environment["LANTERN_RENDER"] != nil }

    @MainActor
    static func makeStore() -> TodoStore {
        let store = TodoStore(container: try! TodoStore.makeContainer(url: nil))
        let context = store.context
        let calendar = Calendar.current
        let now = Date()

        let open = [
            L("로그인 화면 리팩터링", "Refactor the login screen"), L("PR 리뷰 반영하기", "Address PR review comments"),
            L("위젯 다크 모드 확인", "Check widget dark mode"), L("릴리스 노트 쓰기", "Write release notes"), L("온보딩 문구 다듬기", "Polish onboarding copy"),
        ]
        for (index, title) in open.enumerated() {
            let item = TodoItem(title: title, order: Double(index + 1), createdAt: now.addingTimeInterval(-3600 * Double(5 - index)))
            if index == 0 { item.note = L("토큰 갱신 로직은 그대로 두고\nUI만 먼저 나누기", "Keep the token refresh logic as is\nSplit up the UI first") }
            // 기한: 하나는 내일(임박), 하나는 다음 주
            if index == 2 { item.dueDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) }
            if index == 3 { item.dueDate = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now)) }
            context.insert(item)
        }
        for (offset, title) in [(40, L("크래시 로그 확인", "Look into crash logs")), (95, L("디자인 QA 피드백 정리", "Sort out design QA feedback"))] {
            let item = TodoItem(title: title, order: 0, createdAt: now.addingTimeInterval(-86_400))
            item.isDone = true
            item.completedAt = now.addingTimeInterval(-60 * Double(offset))
            context.insert(item)
        }

        // 지난 기록: 날마다 끝낸 일·깨어 있기를 조금씩 (같은 결과가 나오게 고정된 난수)
        var random = SeededRandom(seed: 7)
        let pastTitles = L(
            "API 응답 캐싱|단위 테스트 보강|접근성 라벨 점검|빌드 설정 정리|푸시 알림 문구 수정|메모리 누수 확인|설정 화면 개편|앱스토어 스크린샷 교체|오프라인 모드 점검|로그 정리",
            "Cache API responses|Add more unit tests|Review accessibility labels|Clean up build settings|Fix push notification copy|Check for memory leaks|Redesign the settings screen|Replace App Store screenshots|Test offline mode|Clean up logs"
        ).split(separator: "|").map(String.init)
        let today = calendar.startOfDay(for: now)
        for daysAgo in 1...300 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let weekend = calendar.isDateInWeekend(day)
            let activity = random.next(upTo: 10) + (daysAgo < 120 ? 2 : 0) - (weekend ? 4 : 0)
            guard activity > 2 else { continue }
            for index in 0..<min(activity / 2, 6) {
                let item = TodoItem(title: pastTitles[random.next(upTo: pastTitles.count)], order: 0, createdAt: day)
                let at = day.addingTimeInterval(3600 * Double(10 + index))
                if random.next(upTo: 8) == 0 {
                    item.hiddenAt = at
                } else {
                    item.isDone = true
                    item.completedAt = at
                    item.hiddenAt = at.addingTimeInterval(3600 * 8)
                }
                context.insert(item)
            }
            if activity > 4 {
                let start = day.addingTimeInterval(3600 * Double(13 + random.next(upTo: 6)))
                let hours = Double(1 + random.next(upTo: 5))
                let agent = random.next(upTo: 3) != 0
                context.insert(AwakeRecord(
                    startedAt: start, endedAt: start.addingTimeInterval(3600 * hours),
                    optionLabel: agent ? "에이전트가 끝날 때까지" : "2시간",
                    endReason: agent ? .agentsFinished : .timeElapsed,
                    usedLidMode: agent && random.next(upTo: 2) == 0
                ))
            }
        }
        try? context.save()
        return store
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(upTo bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
}
#endif

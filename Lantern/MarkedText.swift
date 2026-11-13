import AppKit

/// 한글처럼 조합 중인 글자는 화면에는 보여도 SwiftUI 입력 칸의 값(바인딩)에는 아직 들어가 있지 않다.
/// 그 상태로 저장하거나 입력 칸이 사라지면 마지막 음절이 빠지므로, 저장하기 전·창이 바뀌기 전에 확정한다.
/// (2026-11-14 화면 밖 시험 창으로 확인: 이름을 고치다 조합 중에 창이 평소로 바뀌면 "수정" → "수",
/// 메모를 쓰다 조합 중에 ⌘↩·"저장"을 누르면 "내용" → "내")
@MainActor
enum MarkedText {
    /// 랜턴의 모든 창에서 조합 중인 글자를 확정한다. 확정하면 입력 칸 값이 바로 갱신된다
    static func commit() {
        for window in NSApp.windows {
            if let textView = window.firstResponder as? NSTextView, textView.hasMarkedText() {
                textView.unmarkText()
            }
        }
    }
}

import CoreGraphics
import LanternKit
import Testing

@Suite("창 모서리")
struct PanelCornerTests {
    private let screen = CGRect(x: 0, y: 60, width: 1728, height: 1024)
    private let size = CGSize(width: 300, height: 200)
    private let margin = CGSize(width: 12, height: 10)

    @Test("모서리마다 화면 안쪽 여백을 두고 붙는다") func origins() {
        #expect(PanelCorner.topRight.origin(size: size, in: screen, margin: margin) == CGPoint(x: 1416, y: 874))
        #expect(PanelCorner.topLeft.origin(size: size, in: screen, margin: margin) == CGPoint(x: 12, y: 874))
        #expect(PanelCorner.bottomRight.origin(size: size, in: screen, margin: margin) == CGPoint(x: 1416, y: 70))
        #expect(PanelCorner.bottomLeft.origin(size: size, in: screen, margin: margin) == CGPoint(x: 12, y: 70))
    }

    @Test("아래 모서리는 창이 커져도 아래 끝이 그대로라 위로 펼쳐진다") func bottomGrowsUp() {
        let small = PanelCorner.bottomRight.origin(size: CGSize(width: 300, height: 40), in: screen, margin: margin)
        let large = PanelCorner.bottomRight.origin(size: CGSize(width: 300, height: 400), in: screen, margin: margin)
        #expect(small.y == large.y)
    }

    @Test("위 모서리는 창이 커져도 위 끝이 그대로라 아래로 펼쳐진다") func topGrowsDown() {
        let small = PanelCorner.topLeft.origin(size: CGSize(width: 300, height: 40), in: screen, margin: margin)
        let large = PanelCorner.topLeft.origin(size: CGSize(width: 300, height: 400), in: screen, margin: margin)
        #expect(small.y + 40 == large.y + 400)
    }

    @Test("가장 가까운 모서리를 고른다", arguments: [
        (CGPoint(x: 1600, y: 1000), PanelCorner.topRight),
        (CGPoint(x: 100, y: 1000), .topLeft),
        (CGPoint(x: 1600, y: 100), .bottomRight),
        (CGPoint(x: 100, y: 100), .bottomLeft),
    ])
    func nearest(_ pair: (CGPoint, PanelCorner)) {
        #expect(PanelCorner.nearest(to: pair.0, in: screen) == pair.1)
    }
}

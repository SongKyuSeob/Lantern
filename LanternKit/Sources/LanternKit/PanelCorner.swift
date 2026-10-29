import CoreGraphics

/// 플로팅 창을 붙일 화면 모서리.
///
/// 창은 화면 가운데에 두지 않고 네 모서리 중 하나에 붙인다. 위쪽 모서리면 아래로, 아래쪽 모서리면 위로 펼쳐지므로
/// 내용이 늘어나도 화면 밖으로 나가지 않는다. 좌표는 macOS 화면 좌표(아래가 0)를 쓴다.
public enum PanelCorner: String, CaseIterable, Sendable {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft

    public var isTop: Bool { self == .topRight || self == .topLeft }
    public var isRight: Bool { self == .topRight || self == .bottomRight }

    /// 이 모서리에 붙였을 때 창의 왼쪽 아래 좌표. `frame`은 화면에서 메뉴바·Dock을 뺀 영역
    public func origin(size: CGSize, in frame: CGRect, margin: CGSize) -> CGPoint {
        CGPoint(
            x: isRight ? frame.maxX - size.width - margin.width : frame.minX + margin.width,
            y: isTop ? frame.maxY - size.height - margin.height : frame.minY + margin.height
        )
    }

    /// `point`(보통 창 가운데)에서 가장 가까운 모서리
    public static func nearest(to point: CGPoint, in frame: CGRect) -> PanelCorner {
        let right = point.x >= frame.midX
        let top = point.y >= frame.midY
        switch (top, right) {
        case (true, true): return .topRight
        case (true, false): return .topLeft
        case (false, true): return .bottomRight
        case (false, false): return .bottomLeft
        }
    }
}

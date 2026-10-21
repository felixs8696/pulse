import CoreGraphics

/// Match the shelf's visible gap while fitting a compact reply beside either pill edge.
public struct ReplyBannerPlacement {
    public let frame: CGRect
    public let opensOnLeft: Bool
    private let screen: CGRect

    public init(pill: CGRect, screen: CGRect) {
        self.screen = screen
        let overlap = 2 * ShelfPlacement.padding - ShelfPlacement.gap
        let left = max(0, pill.minX - screen.minX + overlap)
        let right = max(0, screen.maxX - pill.maxX + overlap)
        opensOnLeft = left >= 384 || left >= right
        let width = min(384, opensOnLeft ? left : right)
        let height = min(132, screen.height)
        frame = CGRect(x: opensOnLeft ? pill.minX + overlap - width : pill.maxX - overlap,
                       y: max(screen.minY, min(pill.maxY - height, screen.maxY - height)),
                       width: width, height: height)
    }
    /// Grow down from the pill first, then shift upward to keep the whole stack
    /// reachable. The view scrolls when persistent replies exceed screen height.
    public func stackFrame(count: Int) -> CGRect {
        let height = min(screen.height, 132 + CGFloat(max(0, count - 1)) * 116)
        return CGRect(x: frame.minX, y: max(screen.minY, frame.maxY - height), width: frame.width, height: height)
    }

}

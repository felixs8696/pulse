import CoreGraphics

/// Match the shelf's visible gap while fitting a compact reply beside either pill edge.
public struct ReplyBannerPlacement {
    public let frame: CGRect
    public let opensOnLeft: Bool

    public init(pill: CGRect, screen: CGRect) {
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
}

import Foundation
import CoreGraphics

/// Absolute pointer displacement avoids accumulating frame rounding or screen-edge corrections.
public struct ShelfPointerDrag {
    private let origin: CGPoint
    private let pointer: CGPoint
    public init(windowOrigin: CGPoint, pointer: CGPoint) {
        origin = windowOrigin
        self.pointer = pointer
    }
    public func windowOrigin(at point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x - pointer.x, y: origin.y + point.y - pointer.y)
    }
}

/// Place visible edges, accounting for the transparent shadow padding in both windows.
public struct ShelfPlacement {
    public static let padding: CGFloat = 12
    public static let gap: CGFloat = 10
    public static let pillSize = CGSize(width: 60, height: 116)
    public let pillFrame: CGRect
    public let shelfFrame: CGRect
    public let opensOnLeft: Bool

    public init(anchor: CGPoint, screen: CGRect) {
        let size = Self.pillSize
        let x = max(screen.minX, min(anchor.x - size.width, screen.maxX - size.width))
        let y = max(screen.minY, min(anchor.y - size.height, screen.maxY - size.height))
        pillFrame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        let overlap = 2 * Self.padding - Self.gap
        let leftSpace = max(0, pillFrame.minX - screen.minX + overlap)
        let rightSpace = max(0, screen.maxX - pillFrame.maxX + overlap)
        opensOnLeft = leftSpace >= 436 || leftSpace >= rightSpace
        let width = min(436, opensOnLeft ? leftSpace : rightSpace)
        let height = min(600, screen.height)
        shelfFrame = CGRect(x: opensOnLeft ? pillFrame.minX + overlap - width : pillFrame.maxX - overlap,
                            y: max(screen.minY, min(pillFrame.maxY - height, screen.maxY - height)),
                            width: width, height: height)
    }
}

/// During a drag, both surfaces occupy one window so the compositor moves them together.
public struct ShelfDragLayout {
    public let windowFrame: CGRect
    public let pillInWindow: CGRect
    public let shelfInWindow: CGRect
    public init(pill: CGRect, shelf: CGRect) {
        windowFrame = pill.union(shelf)
        pillInWindow = pill.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
        shelfInWindow = shelf.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY)
    }
    public func pillFrame(windowOrigin: CGPoint) -> CGRect {
        pillInWindow.offsetBy(dx: windowOrigin.x, dy: windowOrigin.y)
    }
    public func shelfFrame(windowOrigin: CGPoint) -> CGRect {
        shelfInWindow.offsetBy(dx: windowOrigin.x, dy: windowOrigin.y)
    }
}

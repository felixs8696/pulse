import Foundation
import CoreGraphics

/// Edge-relative positions survive rearranging displays and keep disconnected displays' positions.
public struct DisplayPillPositions: Codable, Sendable {
    private struct Offset: Codable, Sendable {
        let right: Double
        let top: Double
    }
    private var offsets: [String: Offset] = [:]
    public init() {}

    public mutating func record(anchor: CGPoint, displayID: String, screen: CGRect) {
        offsets[displayID] = Offset(right: screen.maxX - anchor.x, top: screen.maxY - anchor.y)
    }
    public func anchor(displayID: String, screen: CGRect) -> CGPoint {
        let offset = offsets[displayID] ?? Offset(right: 18, top: 18)
        let desired = CGPoint(x: screen.maxX - offset.right, y: screen.maxY - offset.top)
        let frame = ShelfPlacement(anchor: desired, screen: screen).pillFrame
        return CGPoint(x: frame.maxX, y: frame.maxY)
    }
}

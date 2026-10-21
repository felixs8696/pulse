import Foundation
import Testing
@testable import PulseCore

struct DisplayPillPositionsTests {
    @Test func eachDisplayRetainsItsOwnPositionAcrossRestartsAndRearrangement() throws {
        var positions = DisplayPillPositions()
        let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let external = CGRect(x: -2560, y: 300, width: 2560, height: 1440)
        positions.record(anchor: CGPoint(x: 1420, y: 820), displayID: "laptop", screen: laptop)
        positions.record(anchor: CGPoint(x: -80, y: 1500), displayID: "external", screen: external)
        let restored = try JSONDecoder().decode(DisplayPillPositions.self, from: JSONEncoder().encode(positions))
        #expect(restored.anchor(displayID: "laptop", screen: laptop) == CGPoint(x: 1420, y: 820))
        #expect(restored.anchor(displayID: "external", screen: external) == CGPoint(x: -80, y: 1500))
        let moved = external.offsetBy(dx: 4072, dy: -300)
        #expect(restored.anchor(displayID: "external", screen: moved) == CGPoint(x: 3992, y: 1200))
        // Plugging in an unseen display doesn't reuse another display's saved coordinates.
        #expect(restored.anchor(displayID: "new", screen: moved) == CGPoint(x: moved.maxX - 18, y: moved.maxY - 18))
    }
    @Test func resolutionChangesAndOffscreenDragsAlwaysLeaveThePillReachable() {
        var positions = DisplayPillPositions()
        let original = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        positions.record(anchor: CGPoint(x: 100, y: 150), displayID: "external", screen: original)
        for screen in [CGRect(x: -1280, y: -800, width: 1280, height: 800), original] {
            let anchor = positions.anchor(displayID: "external", screen: screen)
            let frame = ShelfPlacement(anchor: anchor, screen: screen).pillFrame
            #expect(screen.contains(frame))
        }
        positions.record(anchor: CGPoint(x: 9000, y: -9000), displayID: "external", screen: original)
        let anchor = positions.anchor(displayID: "external", screen: original)
        #expect(original.contains(ShelfPlacement(anchor: anchor, screen: original).pillFrame))
    }
}

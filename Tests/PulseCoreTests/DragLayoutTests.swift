import Foundation
import CoreGraphics
import Testing
@testable import PulseCore

struct DragLayoutTests {
    @Test func verticalDragTracksEverySampleAndReversesAcrossScreenEdges() {
        let placement = ShelfPlacement(anchor: CGPoint(x: 100, y: 135),
                                       screen: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let layout = ShelfDragLayout(pill: placement.pillFrame, shelf: placement.shelfFrame)
        let pointer = CGPoint(x: placement.pillFrame.midX, y: placement.pillFrame.midY)
        let drag = ShelfPointerDrag(windowOrigin: layout.windowFrame.origin, pointer: pointer)
        // Move both above and below the screen, then reverse, including fractional steps.
        for dy in stride(from: -300.0, through: 1000.0, by: 0.5).reversed() {
            let moved = drag.windowOrigin(at: CGPoint(x: pointer.x, y: pointer.y + dy))
            #expect(layout.pillFrame(windowOrigin: moved) == placement.pillFrame.offsetBy(dx: 0, dy: dy))
            #expect(layout.shelfFrame(windowOrigin: moved) == placement.shelfFrame.offsetBy(dx: 0, dy: dy))
        }
        #expect(drag.windowOrigin(at: pointer) == layout.windowFrame.origin)
    }

    @Test func draggingFromPanelTitleOrBackgroundMovesBothSurfacesByTheSameDelta() {
        let placement = ShelfPlacement(anchor: CGPoint(x: 1200, y: 800),
                                       screen: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let layout = ShelfDragLayout(pill: placement.pillFrame, shelf: placement.shelfFrame)
        for pointer in [CGPoint(x: placement.shelfFrame.midX, y: placement.shelfFrame.maxY - 30),
                        CGPoint(x: placement.shelfFrame.midX, y: placement.shelfFrame.minY + 100)] {
            let drag = ShelfPointerDrag(windowOrigin: layout.windowFrame.origin, pointer: pointer)
            for delta in [CGPoint(x: -71.5, y: 22.25), CGPoint(x: 40, y: -95)] {
                let origin = drag.windowOrigin(at: CGPoint(x: pointer.x + delta.x, y: pointer.y + delta.y))
                #expect(layout.pillFrame(windowOrigin: origin) == placement.pillFrame.offsetBy(dx: delta.x, dy: delta.y))
                #expect(layout.shelfFrame(windowOrigin: origin) == placement.shelfFrame.offsetBy(dx: delta.x, dy: delta.y))
            }
        }
    }

    @Test func joiningAndSeparatingPreservesBothSurfacesAtEveryEdge() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        for anchor in [CGPoint(x: -1380, y: 900), CGPoint(x: -20, y: 900), CGPoint(x: -20, y: 116)] {
            let placement = ShelfPlacement(anchor: anchor, screen: screen)
            let drag = ShelfDragLayout(pill: placement.pillFrame, shelf: placement.shelfFrame)
            #expect(drag.pillFrame(windowOrigin: drag.windowFrame.origin) == placement.pillFrame)
            #expect(drag.shelfFrame(windowOrigin: drag.windowFrame.origin) == placement.shelfFrame)
            // Fractional movement stays identical for both surfaces, with no per-window rounding.
            let movedOrigin = CGPoint(x: drag.windowFrame.minX + 17.5, y: drag.windowFrame.minY - 33.25)
            #expect(drag.pillFrame(windowOrigin: movedOrigin) == placement.pillFrame.offsetBy(dx: 17.5, dy: -33.25))
            #expect(drag.shelfFrame(windowOrigin: movedOrigin) == placement.shelfFrame.offsetBy(dx: 17.5, dy: -33.25))
        }
    }
}

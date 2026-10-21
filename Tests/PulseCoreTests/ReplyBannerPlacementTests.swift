import Foundation
import Testing
@testable import PulseCore

struct ReplyBannerPlacementTests {
    @Test func testRightPillOpensLeftWithSameVisibleGapAsShelf() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let pill = ShelfPlacement(anchor: CGPoint(x: 1422, y: 882), screen: screen).pillFrame
        let banner = ReplyBannerPlacement(pill: pill, screen: screen)
        #expect(banner.opensOnLeft)
        #expect((pill.minX + 12) - (banner.frame.maxX - 12) == ShelfPlacement.gap)
        #expect(banner.frame.maxY == pill.maxY)
        #expect(screen.contains(banner.frame))
    }
    @Test func testLeftPillOpensRightOnNegativeOriginDisplay() {
        let screen = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        let pill = ShelfPlacement(anchor: CGPoint(x: -1380, y: 1082), screen: screen).pillFrame
        let banner = ReplyBannerPlacement(pill: pill, screen: screen)
        #expect(!(banner.opensOnLeft))
        #expect((banner.frame.minX + 12) - (pill.maxX - 12) == ShelfPlacement.gap)
        #expect(screen.contains(banner.frame))
    }
    @Test func testLowPillClampsBannerAboveBottomEdge() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let pill = ShelfPlacement(anchor: CGPoint(x: 780, y: 116), screen: screen).pillFrame
        let banner = ReplyBannerPlacement(pill: pill, screen: screen)
        #expect(banner.frame.minY == screen.minY)
        #expect(screen.contains(banner.frame))
    }
}

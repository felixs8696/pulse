import Testing
@testable import PulseCore

struct ShelfPresentationTests {
    @Test func firstClickHoldsPreviewThroughPointerExitAndSecondClickCloses() {
        var panel = ShelfPresentation()
        panel.pointerChanged(inside: true)
        panel.applyHover(inside: true)
        #expect(panel.expanded && !panel.heldOpen)
        panel.clickPill()
        panel.pointerChanged(inside: false)
        panel.applyHover(inside: false)
        #expect(panel.expanded && panel.heldOpen)
        panel.pointerChanged(inside: true)
        panel.applyHover(inside: true)
        panel.clickPill()
        #expect(!panel.expanded && !panel.heldOpen)
        // Exit/enter events from the disappearing shelf must not reopen under the pill.
        panel.pointerChanged(inside: true)
        panel.applyHover(inside: true)
        #expect(!panel.expanded)
    }

    @Test func hoverRearmsOnlyAfterLeavingAndReturning() {
        var panel = ShelfPresentation()
        panel.clickPill()
        panel.clickPill()
        panel.applyHover(inside: true)
        #expect(!panel.expanded)
        panel.pointerChanged(inside: false)
        panel.applyHover(inside: false)
        panel.pointerChanged(inside: true)
        panel.applyHover(inside: true)
        #expect(panel.expanded && !panel.heldOpen)
        panel.pointerChanged(inside: false)
        panel.applyHover(inside: false)
        #expect(!panel.expanded)
    }

    @Test func fastClickBeforeHoverDelayStillHoldsOpen() {
        var panel = ShelfPresentation()
        panel.clickPill()
        panel.applyHover(inside: true)
        panel.applyHover(inside: false)
        #expect(panel.expanded && panel.heldOpen)
        panel.clickPill()
        panel.clickPill()
        #expect(panel.expanded && panel.heldOpen)
    }

    @Test func escapeClearsHoldAndShortcutTogglesVisibility() {
        var panel = ShelfPresentation()
        panel.holdOpen()
        panel.dismiss()
        panel.applyHover(inside: true)
        #expect(!panel.expanded && !panel.heldOpen)
        panel.toggleVisibility()
        #expect(panel.expanded && panel.heldOpen)
        panel.toggleVisibility()
        #expect(!panel.expanded && !panel.heldOpen)
    }
}

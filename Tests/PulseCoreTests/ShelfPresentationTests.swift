import Testing
@testable import PulseCore

struct ShelfPresentationTests {
    @Test func optInKeepsPanelOpenUntilSecondClick() {
        var panel = ShelfPresentation()
        panel.applyHover(inside: true)
        panel.clickPill(keepOpen: true)
        panel.applyHover(inside: false)
        #expect(panel.expanded && panel.heldOpen)
        panel.clickPill(keepOpen: true)
        panel.applyHover(inside: true)
        #expect(!panel.expanded)
    }

    @Test func disablingOptionReleasesExistingHold() {
        var panel = ShelfPresentation()
        panel.clickPill(keepOpen: true)
        panel.releaseHold()
        #expect(!panel.heldOpen && !panel.expanded)
        panel.pointerChanged(inside: false)
        panel.applyHover(inside: true)
        #expect(panel.expanded)
    }

    @Test func repeatedClicksNeverPinPreview() {
        var panel = ShelfPresentation()
        panel.applyHover(inside: true)
        panel.clickPill()
        panel.clickPill()
        #expect(panel.expanded)
        panel.pointerChanged(inside: false)
        panel.applyHover(inside: false)
        #expect(!panel.expanded)
    }

    @Test func fastClickCollapsesOnExit() {
        var panel = ShelfPresentation()
        panel.clickPill()
        #expect(panel.expanded)
        panel.applyHover(inside: false)
        #expect(!panel.expanded)
    }

    @Test func escapeSuppressesHoverUntilPointerReturns() {
        var panel = ShelfPresentation()
        panel.show()
        panel.dismiss()
        panel.applyHover(inside: true)
        #expect(!panel.expanded)
        panel.pointerChanged(inside: false)
        panel.pointerChanged(inside: true)
        panel.applyHover(inside: true)
        #expect(panel.expanded)
    }

    @Test func shortcutShowsTemporarilyAndTogglesClosed() {
        var panel = ShelfPresentation()
        panel.toggleVisibility()
        #expect(panel.expanded)
        panel.applyHover(inside: false)
        #expect(!panel.expanded)
        panel.toggleVisibility()
        panel.toggleVisibility()
        #expect(!panel.expanded)
    }
}

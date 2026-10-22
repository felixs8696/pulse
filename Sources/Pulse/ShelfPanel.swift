import AppKit

final class ShelfPanel: NSPanel {
    var followsDragPointer = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The combined window can cross a screen edge while its pill remains onscreen.
        // AppKit's vertical window constraints must not fight the pointer during a drag.
        followsDragPointer ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}


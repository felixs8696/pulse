/// Hover is temporary. Keeping the panel open on click is opt-in.
public struct ShelfPresentation: Equatable, Sendable {
    private enum Mode: Equatable, Sendable { case closed, preview, held }
    private var mode: Mode = .closed
    private var suppressHover = false

    public init() {}
    public var heldOpen: Bool { mode == .held }
    public var expanded: Bool { mode != .closed }

    /// Re-arm hover as soon as the pointer leaves both surfaces.
    public mutating func pointerChanged(inside: Bool) {
        if !inside { suppressHover = false }
    }

    /// Called after the hover delay, including after explicit show actions.
    public mutating func applyHover(inside: Bool) {
        guard !heldOpen else { return }
        if !inside { mode = .closed }
        else if !suppressHover { mode = .preview }
    }

    public mutating func clickPill(keepOpen: Bool = false) {
        guard keepOpen else { show(); return }
        if heldOpen { dismiss() } else { mode = .held; suppressHover = false }
    }

    public mutating func releaseHold() {
        if heldOpen { dismiss() }
    }

    public mutating func show() {
        mode = .preview
        suppressHover = false
    }

    public mutating func dismiss() {
        mode = .closed
        // Closing under the pointer must not immediately create another preview.
        suppressHover = true
    }

    public mutating func toggleVisibility() {
        if expanded { dismiss() } else { show() }
    }
}

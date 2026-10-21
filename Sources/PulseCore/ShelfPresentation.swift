/// Hover previews are temporary; only explicit actions hold the panel open.
public struct ShelfPresentation: Equatable, Sendable {
    private enum Mode: Equatable, Sendable { case closed, preview, held }
    private var mode: Mode = .closed
    private var suppressHover = false

    public init() {}
    public var expanded: Bool { mode != .closed }
    public var heldOpen: Bool { mode == .held }

    /// Re-arm hover as soon as the pointer leaves both surfaces.
    public mutating func pointerChanged(inside: Bool) {
        if !inside { suppressHover = false }
    }

    /// Called after the hover delay. A pending exit can never close a held panel.
    public mutating func applyHover(inside: Bool) {
        guard mode != .held else { return }
        if !inside { mode = .closed }
        else if !suppressHover { mode = .preview }
    }

    public mutating func clickPill() {
        if heldOpen { dismiss() } else { holdOpen() }
    }

    public mutating func holdOpen() {
        mode = .held
        suppressHover = false
    }

    public mutating func dismiss() {
        mode = .closed
        // Closing under the pointer must not immediately create another preview.
        suppressHover = true
    }

    public mutating func toggleVisibility() {
        if expanded { dismiss() } else { holdOpen() }
    }
}

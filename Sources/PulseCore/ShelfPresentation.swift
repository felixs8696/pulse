/// Clicking opens the panel. Keeping it open after pointer exit is opt-in.
public struct ShelfPresentation: Equatable, Sendable {
    private enum Mode: Equatable, Sendable { case closed, preview, held }
    private var mode: Mode = .closed

    public init() {}
    public var heldOpen: Bool { mode == .held }
    public var expanded: Bool { mode != .closed }

    /// Called after the hover delay, including after explicit show actions.
    public mutating func applyHover(inside: Bool) {
        guard !heldOpen else { return }
        if !inside { mode = .closed }

    }

    public mutating func clickPill(keepOpen: Bool = false) {
        guard keepOpen else { show(); return }
        if heldOpen { dismiss() } else { mode = .held }
    }

    public mutating func releaseHold() {
        if heldOpen { dismiss() }
    }

    public mutating func show() {
        mode = .preview
    }

    public mutating func dismiss() {
        mode = .closed
    }

    public mutating func toggleVisibility() {
        if expanded { dismiss() } else { show() }
    }
}

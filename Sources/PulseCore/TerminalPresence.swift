import Foundation

/// A nil inventory means the host could not be checked, not that every pane closed.
public enum TerminalPresence {
    public static func paneID(_ value: String) -> String {
        value.components(separatedBy: ":").last ?? value
    }
    public static func isVisible(_ session: Session, openITermPanes: Set<String>?) -> Bool {
        guard session.route?.kind == .iTerm, let openITermPanes else { return true }
        guard let terminal = session.terminalID, !terminal.isEmpty else { return false }
        return openITermPanes.contains(paneID(terminal))
    }
}

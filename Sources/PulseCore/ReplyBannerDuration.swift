/// A persisted banner lifetime. Zero means explicit dismissal, never a zero-second timer.
public enum ReplyBannerDuration: Int, CaseIterable, Sendable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case sixtySeconds = 60
    case untilClicked = 0

    public var label: String {
        self == .untilClicked ? "Until clicked" : "\(rawValue) seconds"
    }
    public var seconds: Double? {
        self == .untilClicked ? nil : Double(rawValue)
    }
}

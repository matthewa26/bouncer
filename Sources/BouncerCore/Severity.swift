/// How serious a `Finding` is.
///
/// Order matters: cases are declared from least to most severe so that
/// `Severity` conforms to `Comparable` in the obvious way, letting a
/// `--severity-threshold` flag filter with a plain `>=` comparison.
public enum Severity: String, Comparable, Codable, Sendable {
    case info
    case warning
    case error

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }

    /// Orders severities from least to most severe.
    ///
    /// - Parameters:
    ///   - lhs: The first severity.
    ///   - rhs: The second severity.
    /// - Returns: Whether `lhs` is strictly less severe than `rhs`.
    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}

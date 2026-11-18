/// A declaration's access level, as far as an analyzer can determine it.
///
/// Lives in `BouncerCore` because both `BouncerSwiftAnalyzer` and
/// `BouncerTreeSitterAnalyzer` need the same three-way distinction to honor
/// `missing-documentation`'s `scope` parameter, and neither module depends on
/// the other.
public enum DeclarationVisibility: Sendable {
    case `public`
    case `internal`
    case `private`

    /// Reports whether this visibility falls within a configured `scope`.
    ///
    /// - Parameter scope: `"public"`, `"internal"`, or `"all"`.
    /// - Returns: Whether a declaration at this visibility should be checked.
    public func isIncluded(inScope scope: String) -> Bool {
        switch scope {
        case "all": return true
        case "internal": return self != .private
        default: return self == .public
        }
    }
}

extension DeclarationVisibility: Equatable {}

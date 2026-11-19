import BouncerCore

/// Which lack-of-cohesion measure `lack-of-cohesion` checks, chosen by its `variant` parameter, and the
/// limit that applies to it.
struct CohesionVariant {
    /// The measures: `lcom4` (the default) and `lcom3` count method groups, `lcom1` and `lcom2` count
    /// method pairs, and `lcom-hs` is Henderson-Sellers' 0–1 score.
    enum Kind: String {
        case lcom1, lcom2, lcom3, lcom4
        case hendersonSellers = "lcom-hs"
    }

    let kind: Kind
    let maxGroups: Int
    let maxPairs: Int
    let maxScore: Double

    /// Reads the variant and its limit from the rule's parameters; an unknown variant falls back to LCOM4.
    ///
    /// - Parameter parameters: The rule's parameters.
    init(_ parameters: RuleParameters) {
        kind = Kind(rawValue: parameters.string("variant", default: "lcom4").lowercased()) ?? .lcom4
        maxGroups = parameters.int("maxGroups", default: 2)
        maxPairs = parameters.int("maxPairs", default: 20)
        maxScore = parameters.double("maxScore", default: 0.9)
    }

    /// Checks one type against this variant's limit.
    ///
    /// - Parameter type: The collected type.
    /// - Returns: The finding message if the type is over the limit, else `nil`.
    func violation(by type: CollectedType) -> String? {
        if kind == .lcom4 { return groupViolation(type.cohesionGroups, type: type, label: "LCOM4") }
        guard let structure = type.structure else { return nil }
        let (methods, fields) = (structure.methods, structure.fieldNames)
        switch kind {
        case .lcom1: return pairViolation(CohesionGraph.lcom1(methods, fields: fields), type: type, label: "LCOM1")
        case .lcom2: return pairViolation(CohesionGraph.lcom2(methods, fields: fields), type: type, label: "LCOM2")
        case .hendersonSellers: return scoreViolation(CohesionGraph.hendersonSellers(methods, fields: fields), type)
        case .lcom3, .lcom4: return groupViolation(CohesionGraph.lcom3(methods, fields: fields), type: type)
        }
    }

    /// Checks a method-group count against `maxGroups`.
    ///
    /// - Parameters:
    ///   - groups: The group count, if measured.
    ///   - type: The type.
    ///   - label: The variant's name for the message.
    /// - Returns: The finding message, or `nil`.
    private func groupViolation(_ groups: Int?, type: CollectedType, label: String = "LCOM3") -> String? {
        guard let groups, groups > maxGroups else { return nil }
        return "Type \"\(type.name)\" splits into \(groups) unrelated method groups (\(label)), over \(maxGroups)."
    }

    /// Checks a method-pair count against `maxPairs`.
    ///
    /// - Parameters:
    ///   - pairs: The pair count.
    ///   - type: The type.
    ///   - label: The variant's name for the message.
    /// - Returns: The finding message, or `nil`.
    private func pairViolation(_ pairs: Int, type: CollectedType, label: String) -> String? {
        guard pairs > maxPairs else { return nil }
        return "Type \"\(type.name)\" has \(pairs) method pairs sharing no field (\(label)), over \(maxPairs)."
    }

    /// Checks a Henderson-Sellers score against `maxScore`.
    ///
    /// - Parameters:
    ///   - score: The score.
    ///   - type: The type.
    /// - Returns: The finding message, or `nil`.
    private func scoreViolation(_ score: Double, _ type: CollectedType) -> String? {
        guard score > maxScore else { return nil }
        let shown = (score * 100).rounded() / 100
        return "Type \"\(type.name)\" has lack of cohesion \(shown) (LCOM-HS), over \(maxScore)."
    }
}

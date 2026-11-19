/// What a type's methods do with its fields and each other, for the class-design rules: WMC, the
/// LCOM variants, TCC/LCC, lazy class, and middle man.
public struct TypeStructure: Sendable, Equatable {
    /// Instance methods, excluding initializers, with the member names each one references.
    public let methods: [CohesionGraph.Method]
    /// Stored properties, plus (for TS/JS and Python) members only ever reached as `this.x`/`self.x`.
    public let fieldNames: Set<String>
    /// The cyclomatic complexity of every method, static method, and initializer the type declares.
    public let methodComplexities: [Int]
    /// Whether the type is internal to its module and declares no supertype, conformance, attribute,
    /// decorator, or generic parameter: nothing that could make a near-empty body deliberate.
    public let isPlain: Bool
    /// Whether its body is all of it, with no extension in the same file adding members.
    public let isComplete: Bool

    /// Creates a type's structure.
    ///
    /// - Parameters:
    ///   - methods: Its instance methods, excluding initializers.
    ///   - fieldNames: Its fields.
    ///   - methodComplexities: Every method's and initializer's cyclomatic complexity.
    ///   - isPlain: Whether it's internal and declares no supertype, conformance, attribute, or generic parameter.
    ///   - isComplete: Whether no extension in the same file adds to it.
    public init(
        methods: [CohesionGraph.Method], fieldNames: Set<String>, methodComplexities: [Int], isPlain: Bool,
        isComplete: Bool = true
    ) {
        self.methods = methods
        self.fieldNames = fieldNames
        self.methodComplexities = methodComplexities
        self.isPlain = isPlain
        self.isComplete = isComplete
    }

    /// WMC, Chidamber and Kemerer's weighted methods per class: the sum of its methods' complexities.
    public var weightedMethods: Int { methodComplexities.reduce(0, +) }
}

/// The other lack-of-cohesion variants and Bieman and Kang's TCC/LCC, from the same method-field graph
/// that LCOM4 uses. Each method's field set is the fields among its references.
extension CohesionGraph {
    /// LCOM1 (Chidamber and Kemerer): the method pairs that share no field.
    ///
    /// - Parameters:
    ///   - methods: The type's methods.
    ///   - fields: The type's field names.
    /// - Returns: The number of disjoint pairs.
    public static func lcom1(_ methods: [Method], fields: Set<String>) -> Int {
        pairs(of: methods, fields: fields).filter { !$0 }.count
    }

    /// LCOM2 (Chidamber and Kemerer, 1994): pairs sharing no field minus pairs sharing one, floored at 0.
    ///
    /// - Parameters:
    ///   - methods: The type's methods.
    ///   - fields: The type's field names.
    /// - Returns: The LCOM2 value.
    public static func lcom2(_ methods: [Method], fields: Set<String>) -> Int {
        let sharing = pairs(of: methods, fields: fields)
        return max(0, sharing.filter { !$0 }.count - sharing.filter { $0 }.count)
    }

    /// LCOM3 (Li and Henry): the groups methods form by sharing fields, ignoring calls between them.
    ///
    /// - Parameters:
    ///   - methods: The type's methods.
    ///   - fields: The type's field names.
    /// - Returns: The group count; a type with fewer than two methods is 1.
    public static func lcom3(_ methods: [Method], fields: Set<String>) -> Int {
        guard methods.count > 1 else { return 1 }
        let used = methods.map { $0.references.intersection(fields) }
        return Set(components(methods.count) { !used[$0].isDisjoint(with: used[$1]) }).count
    }

    /// LCOM-HS (Henderson-Sellers' LCOM*): (m − mean methods per field) / (m − 1), over the fields at
    /// least one method uses, from 0 (every method uses every field) to 1 (each field has one user).
    ///
    /// - Parameters:
    ///   - methods: The type's methods.
    ///   - fields: The type's field names.
    /// - Returns: The score, or 0 for fewer than two methods or no used fields.
    public static func hendersonSellers(_ methods: [Method], fields: Set<String>) -> Double {
        let users = fields.map { field in methods.filter { $0.references.contains(field) }.count }.filter { $0 > 0 }
        guard methods.count > 1, !users.isEmpty else { return 0 }
        let mean = Double(users.reduce(0, +)) / Double(users.count)
        return (Double(methods.count) - mean) / Double(methods.count - 1)
    }

    /// TCC and LCC (Bieman and Kang): the share of method pairs connected directly (both reach a common
    /// field, through their own bodies or the methods they call) and directly or transitively. Methods
    /// that reach no field at all are stateless helpers and are left out.
    ///
    /// - Parameters:
    ///   - methods: The type's methods.
    ///   - fields: The type's field names.
    /// - Returns: Both ratios, from 0 to 1, and how many methods they cover; `nil` for fewer than two.
    public static func classCohesion(
        _ methods: [Method], fields: Set<String>
    ) -> (tight: Double, loose: Double, methods: Int)? {
        let reach = reachedFields(methods, fields: fields).filter { !$0.isEmpty }, all = indexPairs(reach.count)
        guard reach.count > 1 else { return nil }
        let isDirect: (Int, Int) -> Bool = { !reach[$0].isDisjoint(with: reach[$1]) }
        let groups = components(reach.count, isEdge: isDirect)
        let direct = all.filter { isDirect($0.0, $0.1) }.count
        let loose = all.filter { groups[$0.0] == groups[$0.1] }.count
        return (Double(direct) / Double(all.count), Double(loose) / Double(all.count), reach.count)
    }

    /// Lists, for every method, whether it shares a field with each later method.
    ///
    /// - Parameters:
    ///   - methods: The type's methods.
    ///   - fields: The type's field names.
    /// - Returns: One flag per unordered pair.
    private static func pairs(of methods: [Method], fields: Set<String>) -> [Bool] {
        let used = methods.map { $0.references.intersection(fields) }
        return indexPairs(methods.count).map { !used[$0.0].isDisjoint(with: used[$0.1]) }
    }

    /// Lists every unordered pair of indices below a count.
    ///
    /// - Parameter count: The number of elements.
    /// - Returns: Each `(i, j)` with `i < j`.
    private static func indexPairs(_ count: Int) -> [(Int, Int)] {
        (0..<count).flatMap { i in ((i + 1)..<max(i + 1, count)).map { (i, $0) } }
    }

    /// Collects the fields each method reaches, directly or through the methods it calls, transitively.
    ///
    /// - Parameters:
    ///   - methods: The type's methods.
    ///   - fields: The type's field names.
    /// - Returns: One field set per method, in order.
    private static func reachedFields(_ methods: [Method], fields: Set<String>) -> [Set<String>] {
        let byName = Dictionary(methods.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        return methods.map { fieldsReached(from: $0, methods: byName, fields: fields) }
    }

    /// Collects the fields one method reaches, directly or through the methods it calls, transitively.
    ///
    /// - Parameters:
    ///   - method: The method.
    ///   - methods: The type's methods by name.
    ///   - fields: The type's field names.
    /// - Returns: The fields it reaches.
    private static func fieldsReached(
        from method: Method, methods: [String: Method], fields: Set<String>
    ) -> Set<String> {
        var seen: Set<String> = [method.name], pending = [method], reached: Set<String> = []
        while let next = pending.popLast() {
            reached.formUnion(next.references.intersection(fields))
            let callees = next.references.subtracting(seen).compactMap { methods[$0] }
            seen.formUnion(callees.map(\.name))
            pending += callees
        }
        return reached
    }
}

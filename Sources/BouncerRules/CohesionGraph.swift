/// Computes LCOM4, the "lack of cohesion of methods" metric, for one type.
///
/// Two methods belong to the same group when they use a common member (a field, or a
/// method both call) or when one calls the other. LCOM4 is the number of groups: 1 means
/// every method is connected, and anything higher means the type holds that many
/// independent responsibilities that could be split apart. Initializers are left out, since
/// they touch every field by design. Parsers supply each method's referenced member names.
public enum CohesionGraph {
    /// One method and the names of the type's members it references.
    public struct Method: Sendable {
        public let name: String
        public let references: Set<String>

        /// Creates a method entry.
        ///
        /// - Parameters:
        ///   - name: The method's name.
        ///   - references: Member names its body uses, such as `count` from `self.count`.
        public init(name: String, references: Set<String>) {
            self.name = name
            self.references = references
        }
    }

    /// Counts the connected method groups.
    ///
    /// - Parameter methods: The type's methods, excluding initializers.
    /// - Returns: The LCOM4 value; a type with fewer than two methods is 1.
    public static func groupCount(_ methods: [Method]) -> Int {
        guard methods.count > 1 else { return 1 }
        var groups = Array(0..<methods.count)
        for i in methods.indices {
            for j in methods.indices where j > i && areConnected(methods[i], methods[j]) {
                merge(&groups, i, j)
            }
        }
        return Set(methods.indices.map { root(groups, $0) }).count
    }

    /// Reports whether two methods share a member or one calls the other.
    ///
    /// - Parameters:
    ///   - a: One method.
    ///   - b: Another method.
    /// - Returns: Whether they belong in the same group.
    private static func areConnected(_ a: Method, _ b: Method) -> Bool {
        a.references.contains(b.name) || b.references.contains(a.name) || !a.references.isDisjoint(with: b.references)
    }

    /// Finds the representative of an element's group.
    ///
    /// - Parameters:
    ///   - groups: Each element's parent in the union-find forest.
    ///   - index: The element.
    /// - Returns: Its group's root.
    private static func root(_ groups: [Int], _ index: Int) -> Int {
        var current = index
        while groups[current] != current { current = groups[current] }
        return current
    }

    /// Joins two elements' groups.
    ///
    /// - Parameters:
    ///   - groups: Each element's parent in the union-find forest.
    ///   - a: One element.
    ///   - b: Another element.
    private static func merge(_ groups: inout [Int], _ a: Int, _ b: Int) {
        groups[root(groups, a)] = root(groups, b)
    }
}

import Foundation
import BouncerCore

/// One type declared in the project, with where it's declared.
struct DeclaredType: Sendable {
    let fact: TypeFact
    let path: String
    /// The module it belongs to: its Swift target, Go package, or folder.
    let unit: String

    /// Identifies the declaration: its path, line, and name.
    var id: String { "\(path):\(fact.line):\(fact.name)" }
    var name: String { fact.name }
}

/// The project's types and how they inherit from and conform to one another, resolved by name.
///
/// A supertype resolves to a type with that name in the same language, preferring one in the same module;
/// names that match nothing (`NSObject`, `React.Component`) are outside the project and ignored. Swift
/// extensions' conformances are merged into the extended type.
struct TypeHierarchy: Sendable {
    /// Every declared type except extensions, sorted by path and line.
    let types: [DeclaredType]
    /// Each class's parent classes in the project, by `id`.
    let parents: [String: [DeclaredType]]
    /// Each class's direct subclasses in the project, by `id`.
    let children: [String: [DeclaredType]]
    /// Each type's resolved supertypes of any kind, including extension conformances, by `id`.
    let supertypes: [String: [DeclaredType]]
    /// Swift extensions that add conformances, including to types declared outside the project.
    let extensions: [DeclaredType]
    /// Resolves written names to project types.
    let resolver: TypeResolver

    /// Builds the hierarchy from every file's structure facts.
    ///
    /// - Parameter index: The project's dependency graph and facts.
    init(index: ProjectIndex) {
        let all = Self.declarations(in: index)
        let types = all.filter { $0.fact.kind != .extension }, extensions = all.filter { $0.fact.kind == .extension }
        let resolver = TypeResolver(types: types)
        let supertypes = Self.resolvedSupertypes(types, extensions: extensions, resolver: resolver)
        let parents = Self.parentClasses(types, supertypes: supertypes)
        (self.types, self.extensions, self.resolver, self.supertypes) = (types, extensions, resolver, supertypes)
        (self.parents, children) = (parents, Self.inverted(parents, types: types))
    }

    /// Lists every type and extension in the project's facts.
    ///
    /// - Parameter index: The project's facts.
    /// - Returns: The declarations, sorted by path and line.
    private static func declarations(in index: ProjectIndex) -> [DeclaredType] {
        index.facts.keys.sorted().flatMap { path in
            (index.facts[path]?.module.structure.types ?? []).map {
                DeclaredType(fact: $0, path: path, unit: ProjectUnits.unit(of: path, in: index))
            }
        }
    }

    /// Resolves each type's written supertypes, adding the conformances its extensions declare.
    ///
    /// - Parameters:
    ///   - types: The declared types.
    ///   - extensions: The extensions.
    ///   - resolver: Resolves names to types.
    /// - Returns: Each type's supertypes in the project, by `id`.
    private static func resolvedSupertypes(
        _ types: [DeclaredType], extensions: [DeclaredType], resolver: TypeResolver
    ) -> [String: [DeclaredType]] {
        let added = Dictionary(grouping: extensions) { resolver.key(of: $0) }
        let pairs = types.map { type in
            let written = type.fact.supertypes + (added[resolver.key(of: type)] ?? []).flatMap(\.fact.supertypes)
            return (type.id, written.compactMap { resolver.resolve($0, from: type) })
        }
        return Dictionary(pairs) { first, _ in first }
    }

    /// Inverts each class's parents into each class's children.
    ///
    /// - Parameters:
    ///   - parents: Each class's parents, by `id`.
    ///   - types: The declared types, in order.
    /// - Returns: Each class's direct subclasses, by `id`.
    private static func inverted(
        _ parents: [String: [DeclaredType]], types: [DeclaredType]
    ) -> [String: [DeclaredType]] {
        let pairs = types.flatMap { child in (parents[child.id] ?? []).map { (parent: $0.id, child: child) } }
        return Dictionary(grouping: pairs, by: \.parent).mapValues { $0.map(\.child) }
    }

    /// Finds each class's parent classes: for Swift and TS/JS, only the first supertype can be one; Python
    /// allows several.
    ///
    /// - Parameters:
    ///   - types: The declared types.
    ///   - supertypes: Each type's resolved supertypes.
    /// - Returns: Each class's parent classes, by `id`.
    private static func parentClasses(
        _ types: [DeclaredType], supertypes: [String: [DeclaredType]]
    ) -> [String: [DeclaredType]] {
        let pairs = types.filter(\.fact.kind.isClass).map { type in
            let first = type.fact.supertypes.first
            let resolved = (supertypes[type.id] ?? []).filter { parent in
                parent.fact.kind.isClass && (type.path.hasSuffix(".py") || parent.name == first)
            }
            return (type.id, resolved)
        }
        return Dictionary(pairs) { first, _ in first }
    }

    /// Lists a class's ancestors in the project, nearest first, each once.
    ///
    /// - Parameter type: The class.
    /// - Returns: Its ancestors.
    func ancestors(of type: DeclaredType) -> [DeclaredType] {
        var seen: Set<String> = [type.id], result: [DeclaredType] = [], queue = parents[type.id] ?? []
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard seen.insert(next.id).inserted else { continue }
            result.append(next)
            queue += parents[next.id] ?? []
        }
        return result
    }

    /// Measures a class's depth of inheritance: the longest chain of project ancestors above it.
    ///
    /// - Parameters:
    ///   - type: The class.
    ///   - visiting: Classes on the current chain, which guards against cycles.
    /// - Returns: 0 for a class with no parent in the project.
    func depth(of type: DeclaredType, visiting: Set<String> = []) -> Int {
        let parents = (parents[type.id] ?? []).filter { !visiting.contains($0.id) }
        return parents.map { 1 + depth(of: $0, visiting: visiting.union([type.id])) }.max() ?? 0
    }
}

/// Resolves written supertype names to project types.
struct TypeResolver: Sendable {
    private let byName: [String: [DeclaredType]]

    /// Indexes types by language and name.
    ///
    /// - Parameter types: The declared types.
    init(types: [DeclaredType]) {
        byName = Dictionary(grouping: types) { Self.key($0.name, $0.path) }
    }

    /// The key a type is indexed under: its language family and name.
    ///
    /// - Parameter type: The type or extension.
    /// - Returns: The key.
    func key(of type: DeclaredType) -> String { Self.key(type.name, type.path) }

    /// Resolves a supertype written in one type's declaration.
    ///
    /// - Parameters:
    ///   - name: The supertype's bare name.
    ///   - type: The declaring type.
    /// - Returns: The project type, preferring one in the same module, or `nil` if none matches.
    func resolve(_ name: String, from type: DeclaredType) -> DeclaredType? {
        let candidates = (byName[Self.key(name, type.path)] ?? []).filter { $0.id != type.id }
        return candidates.first { $0.unit == type.unit } ?? candidates.first
    }

    /// Builds a key from a name and the language of the file it's written in.
    ///
    /// - Parameters:
    ///   - name: The type name.
    ///   - path: A file path.
    /// - Returns: The key.
    private static func key(_ name: String, _ path: String) -> String {
        ProjectUnits.family(of: path) + ":" + name
    }
}

/// The modules design metrics are measured per: Swift targets and Go packages as the dependency graph
/// has them, and folders for TypeScript, JavaScript, and Python, whose graph nodes are single files.
enum ProjectUnits {
    /// The module a file belongs to.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - index: The project's dependency graph.
    /// - Returns: `swift:<Target>`, `go:<dir>`, or `dir:<dir>`.
    static func unit(of path: String, in index: ProjectIndex) -> String {
        if let node = index.nodeOfFile[path], node.hasPrefix("swift:") || node.hasPrefix("go:") { return node }
        return "dir:" + ProjectPath.directory(of: path)
    }

    /// Maps every indexed file to its module.
    ///
    /// - Parameter index: The project's dependency graph.
    /// - Returns: Each file's module.
    static func units(in index: ProjectIndex) -> [String: String] {
        Dictionary(uniqueKeysWithValues: index.facts.keys.map { ($0, unit(of: $0, in: index)) })
    }

    /// Displays a module: a target or package name, or a folder.
    ///
    /// - Parameter unit: The module.
    /// - Returns: Its display name.
    static func display(_ unit: String) -> String {
        guard unit.hasPrefix("dir:") else { return ProjectFinding.display(unit) }
        let folder = String(unit.dropFirst(4))
        return folder.isEmpty ? "the root folder" : folder + "/"
    }

    /// Groups extensions into language families whose types can inherit from one another.
    ///
    /// - Parameter path: A file path.
    /// - Returns: `swift`, `js`, `py`, `go`, or the extension.
    static func family(of path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return JavaScriptImportResolver.extensions.contains(ext) ? "js" : ext
    }

    /// Reports whether a file is code the design rules don't judge: a test, a DocC catalog's sample code,
    /// or a generated file.
    ///
    /// - Parameters:
    ///   - path: The repo-relative path.
    ///   - index: The project's facts, for whether the file is generated.
    /// - Returns: Whether to leave it alone.
    static func isIncidental(_ path: String, in index: ProjectIndex) -> Bool {
        isTest(path) || path.contains(".docc/") || index.facts[path]?.module.structure.isGenerated == true
    }

    /// Reports whether a path is a test file or under a test folder.
    ///
    /// - Parameter path: The repo-relative path.
    /// - Returns: Whether it's test code.
    static func isTest(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        let stem = ((parts.last.map(String.init) ?? "") as NSString).deletingPathExtension
        return parts.dropLast().contains { ["Tests", "tests", "test", "__tests__", "testdata"].contains($0) }
            || [".test", ".spec", "Tests", "Test", "_test"].contains { stem.hasSuffix($0) } || stem.hasPrefix("test_")
    }
}

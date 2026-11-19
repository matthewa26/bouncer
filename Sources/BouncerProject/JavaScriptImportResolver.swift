import Foundation
import BouncerCore

/// TypeScript/JavaScript: each file is a node. Relative specifiers and `tsconfig.json` path aliases resolve
/// to files, trying TypeScript and JavaScript extensions and `index` files; package imports are external.
struct JavaScriptImportResolver: ImportResolver {
    static let extensions = ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs"]
    private let paths: Set<String>
    private let config: TSConfig

    /// Creates the resolver over the project's files.
    ///
    /// - Parameters:
    ///   - paths: Every indexed file's repo-relative path.
    ///   - config: The root `tsconfig.json`'s module resolution settings.
    init(paths: Set<String>, config: TSConfig) {
        self.paths = paths
        self.config = config
    }

    /// The node for a TS/JS file: the file itself.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: The path.
    func node(of path: String) -> String { path }

    /// Resolves a relative or aliased specifier to a project file.
    ///
    /// - Parameters:
    ///   - specifier: The import as written.
    ///   - path: The importing file.
    /// - Returns: The imported file, or `nil` for a package or unresolvable import.
    func resolve(_ specifier: String, from path: String) -> String? {
        let bases = specifier.hasPrefix(".")
            ? [ProjectPath.join(ProjectPath.directory(of: path), specifier)].compactMap { $0 }
            : config.candidates(for: specifier)
        return bases.lazy.compactMap(file(for:)).first
    }

    /// Finds the file a resolved base path refers to.
    ///
    /// - Parameter base: A path that may lack its extension, name a directory, or use `.js` for a `.ts` file.
    /// - Returns: The first existing candidate file.
    private func file(for base: String) -> String? {
        let path = base as NSString
        let stem = Self.extensions.contains(path.pathExtension) ? path.deletingPathExtension : base
        let candidates = [base] + Self.extensions.map { stem + "." + $0 }
            + Self.extensions.map { base + "/index." + $0 }
        return candidates.first(where: paths.contains)
    }
}

/// The module resolution settings from a project's root `tsconfig.json`: `baseUrl` and `paths`.
struct TSConfig: Sendable {
    private let baseUrl: String?
    private let paths: [String: [String]]

    /// Reads `tsconfig.json` at the repo root, tolerating its comments and trailing commas.
    ///
    /// - Parameter repoRoot: The repository root.
    init(repoRoot: URL) {
        let url = repoRoot.appendingPathComponent("tsconfig.json")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let object = (try? JSONSerialization.jsonObject(with: Data(Self.stripJSONC(text).utf8))) as? [String: Any]
        let options = object?["compilerOptions"] as? [String: Any]
        baseUrl = (options?["baseUrl"] as? String).flatMap { ProjectPath.join("", $0) }
        paths = options?["paths"] as? [String: [String]] ?? [:]
    }

    /// Lists the base paths a non-relative specifier could mean: each matching `paths` alias, then `baseUrl`.
    ///
    /// - Parameter specifier: The import as written.
    /// - Returns: Repo-relative candidates, without extensions.
    func candidates(for specifier: String) -> [String] {
        let root = baseUrl ?? ""
        let aliased = paths.flatMap { pattern, targets in
            Self.match(specifier, pattern).map { rest in
                targets.map { $0.replacingOccurrences(of: "*", with: rest) }
            } ?? []
        }
        let fromBase = baseUrl == nil ? [] : [specifier]
        return (aliased + fromBase).compactMap { ProjectPath.join(root, $0) }
    }

    /// Matches a specifier against a `paths` pattern with at most one `*`.
    ///
    /// - Parameters:
    ///   - specifier: The import as written.
    ///   - pattern: The alias pattern, such as `@app/*`.
    /// - Returns: The text the `*` matched (empty for an exact match), or `nil` if it doesn't match.
    private static func match(_ specifier: String, _ pattern: String) -> String? {
        guard let star = pattern.firstIndex(of: "*") else { return specifier == pattern ? "" : nil }
        let prefix = pattern[..<star], suffix = pattern[pattern.index(after: star)...]
        guard specifier.hasPrefix(prefix), specifier.hasSuffix(suffix),
              specifier.count >= prefix.count + suffix.count else { return nil }
        return String(specifier.dropFirst(prefix.count).dropLast(suffix.count))
    }

    /// Removes `//` and `/* */` comments and trailing commas, which `tsconfig.json` allows and JSON doesn't.
    ///
    /// - Parameter text: The file's text.
    /// - Returns: Plain JSON.
    static func stripJSONC(_ text: String) -> String {
        let withoutComments = text.replacingOccurrences(
            of: #"("(?:\\.|[^"\\])*")|//[^\n]*|/\*[\s\S]*?\*/"#, with: "$1", options: .regularExpression
        )
        return withoutComments.replacingOccurrences(of: #",(\s*[}\]])"#, with: "$1", options: .regularExpression)
    }
}

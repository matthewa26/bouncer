import Foundation
import BouncerCore

/// Flags a dependency a package manifest declares but no code imports.
///
/// - SwiftPM: a `.package(…)` no target refers to, and a target's `.product(name:package:)` that none of
///   the target's files import (products named like modules only; targets with no indexed files skipped).
/// - `package.json`: a `dependencies` entry no file in the package imports, unless it's an `@types/`
///   package, a peer dependency, a tool its `scripts` run, mentioned elsewhere in the manifest, or listed in
///   `ignore`. A workspace root's dependencies count as used by every workspace. `devDependencies` aren't
///   checked, since tools and test runners use them without imports.
/// - `go.mod`: a direct `require` no file in the module imports.
///
/// Python isn't checked: distribution names (`beautifulsoup4`) differ from import names (`bs4`).
public struct UnusedDependencyRule: ProjectRule {
    public let id = "unused-dependency"
    static let implicitPackages = ["tslib", "@babel/runtime", "regenerator-runtime", "core-js"]
    static let npmManifest = "package.json", goManifest = "go.mod"

    /// Creates the rule.
    public init() {}

    /// Checks every manifest above an indexed source file.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph and facts.
    ///   - targets: Unused; each finding lands in the manifest.
    ///   - context: Repo-wide state, with `ignore` (dependency names).
    /// - Returns: One finding per unused dependency.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        let ignored = Set(context.settings(for: id).parameters.stringList("ignore", default: []))
        let files = ManifestFiles(index: index, repoRoot: context.repoRoot)
        let unused = swiftPackages(files, index: index) + npmPackages(files) + goModules(files)
        return unused.filter { !ignored.contains($0.name) }.map {
            ProjectFinding.make(id, $0.path, $0.line, $0.message, context)
        }
    }

    /// Checks each `Package.swift`.
    ///
    /// - Parameters:
    ///   - files: The manifests and the files they govern.
    ///   - index: The project's facts.
    /// - Returns: The unused packages and products.
    private func swiftPackages(_ files: ManifestFiles, index: ProjectIndex) -> [UnusedDependency] {
        files.manifests(named: "Package.swift").flatMap { path -> [UnusedDependency] in
            guard let text = files.read(path) else { return [] }
            let manifest = SwiftPackageManifest(path: path, repoRoot: files.repoRoot, text: text)
            let packages = manifest.packages.filter { !manifest.mentions($0.name) && !Self.isPluginPackage($0.name) }
                .map { UnusedDependency(name: $0.name, path: path, line: $0.line, message: Self.unused($0.name)) }
            return packages + manifest.targets.flatMap { unusedProducts(of: $0, manifest: path, index: index) }
        }
    }

    /// Lists a target's product dependencies that none of its files import.
    ///
    /// - Parameters:
    ///   - target: The target.
    ///   - manifest: The manifest's path.
    ///   - index: The project's facts.
    /// - Returns: The unused products.
    private func unusedProducts(
        of target: SwiftPackageManifest.Target, manifest: String, index: ProjectIndex
    ) -> [UnusedDependency] {
        let prefix = target.directory + "/"
        let sources = index.facts.values.filter { $0.path.hasPrefix(prefix) && $0.path.hasSuffix(".swift") }
        guard target.kind != "plugin", !sources.isEmpty else { return [] }
        let imported = Set(sources.flatMap { $0.module.imports.map(\.specifier) })
        return target.products.filter { Self.isModuleName($0.name) && !imported.contains($0.name) }.map {
            let message = "Target \"\(target.name)\" depends on product \"\($0.name)\", but none of its files "
                + "import it; remove the dependency."
            return UnusedDependency(name: $0.name, path: manifest, line: $0.line, message: message)
        }
    }

    /// Checks each `package.json`'s `dependencies`.
    ///
    /// - Parameter files: The manifests and the files they govern.
    /// - Returns: The unused packages.
    private func npmPackages(_ files: ManifestFiles) -> [UnusedDependency] {
        files.manifests(named: Self.npmManifest).flatMap { path -> [UnusedDependency] in
            guard let text = files.read(path), let manifest = NPMManifest(text: text) else { return [] }
            let imported = files.specifiers(governedBy: path, named: Self.npmManifest, everything: manifest.isWorkspace)
            return manifest.dependencies.filter { dependency in
                !manifest.isExempt(dependency.name) && !imported.contains { Self.specifier($0, names: dependency.name) }
            }.map { UnusedDependency(name: $0.name, path: path, line: $0.line, message: Self.unused($0.name)) }
        }
    }

    /// Checks each `go.mod`'s direct requirements.
    ///
    /// - Parameter files: The manifests and the files they govern.
    /// - Returns: The unused modules.
    private func goModules(_ files: ManifestFiles) -> [UnusedDependency] {
        files.manifests(named: Self.goManifest).flatMap { path -> [UnusedDependency] in
            guard let text = files.read(path) else { return [] }
            let module = GoModule(path: path, text: text)
            let imported = files.specifiers(governedBy: path, named: Self.goManifest, everything: false)
            return module.requirements.filter { requirement in
                !imported.contains { Self.specifier($0, names: requirement.name) }
            }.map { UnusedDependency(name: $0.name, path: path, line: $0.line, message: Self.unusedModule($0.name)) }
        }
    }

    /// Reports whether an import specifier refers to a package or one of its subpaths.
    ///
    /// - Parameters:
    ///   - specifier: The import as written.
    ///   - name: The package or module name.
    /// - Returns: Whether it imports from that package.
    static func specifier(_ specifier: String, names name: String) -> Bool {
        specifier == name || specifier.hasPrefix(name + "/")
    }

    /// Reports whether a name could be a Swift module name, so a missing `import` of it means something.
    ///
    /// - Parameter name: The product name.
    /// - Returns: Whether it's a plain identifier.
    private static func isModuleName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Reports whether a SwiftPM package is a command plugin, which `swift package` runs without any target
    /// depending on it, such as `swift-docc-plugin`.
    ///
    /// - Parameter identity: The package identity.
    /// - Returns: Whether it's a plugin package.
    private static func isPluginPackage(_ identity: String) -> Bool {
        identity.lowercased().contains("plugin")
    }

    /// Explains an unused package.
    ///
    /// - Parameter name: The package.
    /// - Returns: The message.
    private static func unused(_ name: String) -> String {
        "Dependency \"\(name)\" isn't used by any code in the package; remove it from the manifest."
    }

    /// Explains an unused Go module.
    ///
    /// - Parameter name: The module.
    /// - Returns: The message.
    private static func unusedModule(_ name: String) -> String {
        "Module \"\(name)\" is required but no package in the module imports it; run `go mod tidy`."
    }
}

/// One unused dependency, ready to report.
struct UnusedDependency {
    let name: String
    let path: String
    let line: Int
    let message: String
}

/// What `unused-dependency` reads from a `package.json`.
struct NPMManifest {
    let dependencies: [DeclaredDependency]
    /// Whether it declares `workspaces`, so its dependencies are shared by every workspace package.
    let isWorkspace: Bool
    private let exempt: Set<String>
    private let scripts: String
    private let text: String
    private static let tools = ["typescript": "tsc", "@angular/cli": "ng", "@nestjs/cli": "nest"]

    /// Parses a manifest.
    ///
    /// - Parameter text: Its contents.
    init?(text: String) {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else {
            return nil
        }
        let keys = { (field: String) in (json[field] as? [String: Any] ?? [:]).keys.sorted() }
        dependencies = Self.located(keys("dependencies"), in: text)
        isWorkspace = json["workspaces"] != nil
        exempt = Set(keys("peerDependencies") + UnusedDependencyRule.implicitPackages)
        scripts = (json["scripts"] as? [String: Any] ?? [:]).values.compactMap { $0 as? String }.joined(separator: " ")
        self.text = text
    }

    /// Finds the line declaring each dependency: its first quoted mention after `"dependencies"`.
    ///
    /// - Parameters:
    ///   - names: The dependencies' names.
    ///   - text: The manifest's text.
    /// - Returns: Each dependency with its line.
    private static func located(_ names: [String], in text: String) -> [DeclaredDependency] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let block = lines.firstIndex { $0.contains("\"dependencies\"") } ?? 0
        return names.map { name in
            let line = lines[block...].firstIndex { $0.contains("\"\(name)\"") }.map { $0 + 1 } ?? 1
            return DeclaredDependency(name: name, line: line)
        }
    }

    /// Reports whether a dependency is used without an import: types, peers, implicit helpers, a tool the
    /// scripts run, or a package the manifest names again (such as in a config section).
    ///
    /// - Parameter name: The dependency.
    /// - Returns: Whether it's exempt.
    func isExempt(_ name: String) -> Bool {
        let declaredOnly = text.components(separatedBy: "\"\(name)").count <= 2
        return name.hasPrefix("@types/") || exempt.contains(name) || isRunByScripts(name) || !declaredOnly
    }

    /// Reports whether a `scripts` command runs a package's tool or preloads it, by its package name, a
    /// subpath of it (`node -r dotenv/config`), or its command.
    ///
    /// - Parameter name: The dependency.
    /// - Returns: Whether a script names it.
    private func isRunByScripts(_ name: String) -> Bool {
        let command = Self.tools[name] ?? String(name.split(separator: "/").last ?? "")
        let words = scripts.split { !($0.isLetter || $0.isNumber || "-_.@/".contains($0)) }.map(String.init)
        return words.contains { $0 == command || UnusedDependencyRule.specifier($0, names: name) }
    }
}

/// The manifests above the project's source files, and which files each one governs.
struct ManifestFiles {
    private let index: ProjectIndex
    let repoRoot: URL
    private let directories: Set<String>

    /// Collects the folders holding indexed files.
    ///
    /// - Parameters:
    ///   - index: The project's facts.
    ///   - repoRoot: The repository root.
    init(index: ProjectIndex, repoRoot: URL) {
        self.index = index
        self.repoRoot = repoRoot
        directories = Set(index.facts.keys.map(ProjectPath.directory(of:)))
    }

    /// Lists every manifest with a name at or above an indexed folder.
    ///
    /// - Parameter name: The manifest's file name.
    /// - Returns: Their repo-relative paths, sorted.
    func manifests(named name: String) -> [String] {
        NearestFiles.all(named: name, above: directories, repoRoot: repoRoot).sorted()
    }

    /// Reads a manifest.
    ///
    /// - Parameter path: Its repo-relative path.
    /// - Returns: Its text, or `nil` if it can't be read.
    func read(_ path: String) -> String? {
        try? String(contentsOf: RepoPath.url(path, in: repoRoot), encoding: .utf8)
    }

    /// Lists the import specifiers of the files a manifest governs: those whose nearest manifest of that
    /// name it is, or every file below it.
    ///
    /// - Parameters:
    ///   - manifest: The manifest's path.
    ///   - name: The manifest's file name.
    ///   - everything: Whether every file below it counts, as for a workspace root.
    /// - Returns: The specifiers.
    func specifiers(governedBy manifest: String, named name: String, everything: Bool) -> Set<String> {
        let folder = ProjectPath.directory(of: manifest)
        let nearest = NearestFiles(named: name, from: directories, repoRoot: repoRoot).byDirectory
        let governed = index.facts.values.filter { facts in
            let directory = ProjectPath.directory(of: facts.path)
            let below = folder.isEmpty || directory == folder || directory.hasPrefix(folder + "/")
            return below && (everything || nearest[directory] == manifest)
        }
        return Set(governed.flatMap { $0.module.imports.map(\.specifier) })
    }
}

/// Flags a SwiftPM target, a `package.json` package, or a Go module without a README. Off unless configured.
///
/// A file named `README` in any case and with any extension counts, and so does a DocC catalog (`*.docc`)
/// in a Swift target. Test targets are skipped unless `includeTests` is set.
public struct MissingReadmeRule: ProjectRule {
    public let id = "missing-readme"

    /// Creates the rule.
    public init() {}

    /// Flags each package or target folder without a README.
    ///
    /// - Parameters:
    ///   - index: The project's facts.
    ///   - targets: Unused; each finding lands in the manifest, or a Swift target's first file.
    ///   - context: Repo-wide state; the rule only runs when configured, with `includeTests`.
    /// - Returns: One finding per undocumented package or target.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled else { return [] }
        let files = ManifestFiles(index: index, repoRoot: context.repoRoot)
        let packages = [UnusedDependencyRule.npmManifest, UnusedDependencyRule.goManifest].flatMap(files.manifests)
            .map { (folder: ProjectPath.directory(of: $0), report: $0, kind: Self.kind(of: $0)) }
        let swift = swiftTargets(index, includeTests: settings.parameters.bool("includeTests", default: false))
        return (packages + swift).filter { !hasReadme($0.folder, repoRoot: context.repoRoot) }.map { unit in
            let name = unit.folder.isEmpty ? "at the repository root" : unit.folder + "/"
            return ProjectFinding.make(id, unit.report, 1, "\(unit.kind) \(name) \(Self.advice)", context)
        }
    }

    private static let advice = "has no README; add one saying what it's for and how to use it."

    /// Names what a manifest declares.
    ///
    /// - Parameter manifest: The manifest's path.
    /// - Returns: `Go module` or `Package`.
    private static func kind(of manifest: String) -> String {
        manifest.hasSuffix(UnusedDependencyRule.goManifest) ? "Go module" : "Package"
    }

    /// Lists SwiftPM target folders: `Sources/<Target>` (and `Tests/<Target>`) beside a `Package.swift`.
    ///
    /// - Parameters:
    ///   - index: The project's facts.
    ///   - includeTests: Whether test targets count.
    /// - Returns: Each target's folder and its first file.
    private func swiftTargets(
        _ index: ProjectIndex, includeTests: Bool
    ) -> [(folder: String, report: String, kind: String)] {
        let roots = includeTests ? ["Sources", "Tests"] : ["Sources"]
        let folders = Dictionary(grouping: index.facts.keys.sorted().filter { $0.hasSuffix(".swift") }) {
            Self.targetFolder(of: $0, roots: roots, index: index)
        }
        return folders.filter { !$0.key.isEmpty }.sorted { $0.key < $1.key }.map {
            (folder: $0.key, report: $0.value[0], kind: "Target")
        }
    }

    /// Finds the SwiftPM target folder a Swift file is in.
    ///
    /// - Parameters:
    ///   - path: The file's repo-relative path.
    ///   - roots: The folders targets live in, such as `Sources`.
    ///   - index: The project's facts, to confirm a `Package.swift` sits beside the root folder.
    /// - Returns: The target folder, or `""` if the file isn't in one.
    private static func targetFolder(of path: String, roots: [String], index: ProjectIndex) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard let position = parts.firstIndex(where: roots.contains), position + 2 < parts.count,
              index.facts[(parts[..<position] + ["Package.swift"]).joined(separator: "/")] != nil else { return "" }
        return parts[...(position + 1)].joined(separator: "/")
    }

    /// Reports whether a folder holds a README or a DocC catalog.
    ///
    /// - Parameters:
    ///   - folder: The repo-relative folder.
    ///   - repoRoot: The repository root.
    /// - Returns: Whether it's documented.
    private func hasReadme(_ folder: String, repoRoot: URL) -> Bool {
        let url = folder.isEmpty ? repoRoot : RepoPath.url(folder, in: repoRoot)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.contains { $0.lowercased().hasPrefix("readme") || $0.hasSuffix(".docc") }
    }
}

import Foundation
import BouncerCore

/// Flags a Swift `public`/`open` declaration that no file in another target refers to. Off unless configured.
///
/// Swift imports name a module, not symbols, so usage is inferred by name: a public symbol counts as used
/// if any file in a different target (test targets included) mentions it. That makes it approximate: two
/// symbols sharing a name hide each other, and symbols a framework calls by convention (SwiftUI's `body`) or
/// a library's API for other packages look unused, hence `ignoreNames` and `publicTargets`.
public struct UnusedPublicSymbolRule: ProjectRule {
    public let id = "unused-public-symbol"
    private static let defaultIgnoredNames = ["body", "description", "debugDescription", "hash", "encode", "id"]

    /// Creates the rule.
    public init() {}

    /// Flags each public Swift symbol unused outside its own target.
    ///
    /// - Parameters:
    ///   - index: The project's dependency graph.
    ///   - targets: Unused; each finding lands at the declaration.
    ///   - context: Repo-wide state; the rule only runs when configured, with `publicTargets` and `ignoreNames`.
    /// - Returns: One finding per unused public symbol.
    public func evaluate(_ index: ProjectIndex, targets: Set<String>, context: AnalysisContext) -> [Finding] {
        guard let settings = context.ruleSettings[id], settings.enabled else { return [] }
        let skippedTargets = Set(settings.parameters.stringList("publicTargets", default: []))
        let ignored = Set(Self.defaultIgnoredNames + settings.parameters.stringList("ignoreNames", default: []))
        let usage = SwiftUsage(index: index)
        return usage.declarations(skipping: skippedTargets).flatMap { file, target in
            unusedExports(of: file, in: target, index: index, usage: usage, ignored: ignored).map {
                ProjectFinding.make(id, file, $0.line, Self.message($0.name, target), context)
            }
        }
    }

    /// Lists one file's public declarations that no other target uses.
    ///
    /// - Parameters:
    ///   - file: The repo-relative path.
    ///   - target: The file's target.
    ///   - index: The project's dependency graph.
    ///   - usage: Which names each target uses.
    ///   - ignored: Names never reported.
    /// - Returns: The unused declarations.
    private func unusedExports(
        of file: String, in target: String, index: ProjectIndex, usage: SwiftUsage, ignored: Set<String>
    ) -> [ExportFact] {
        (index.facts[file]?.module.exports ?? []).filter {
            !ignored.contains($0.name) && !usage.isUsed($0.name, outside: target)
        }
    }

    /// Describes one unused public symbol.
    ///
    /// - Parameters:
    ///   - name: The symbol.
    ///   - target: Its target.
    /// - Returns: The message.
    private static func message(_ name: String, _ target: String) -> String {
        "Public \"\(name)\" isn't used outside target \(target); make it internal, "
            + "or list \(target) in publicTargets if it's API for other packages."
    }
}

/// Which names each Swift target's files refer to or implement. A same-named public declaration in another
/// target counts too, since that's how a protocol requirement's implementation in another target shows up.
struct SwiftUsage {
    private let targetOfFile: [String: String]
    private let referencesByTarget: [String: Set<String>]

    /// Groups Swift files' references by target.
    ///
    /// - Parameter index: The project's dependency graph.
    init(index: ProjectIndex) {
        let swiftFiles = index.nodeOfFile.filter { $0.value.hasPrefix("swift:") }
        targetOfFile = swiftFiles.mapValues { String($0.dropFirst("swift:".count)) }
        let filesByNode = Dictionary(grouping: swiftFiles.keys, by: { swiftFiles[$0] ?? "" })
        referencesByTarget = filesByNode.reduce(into: [:]) { result, group in
            let target = String(group.key.dropFirst("swift:".count))
            result[target] = Set(group.value.flatMap { Self.usedNames(in: index.facts[$0]) })
        }
    }

    /// Lists the names one file refers to or publicly declares.
    ///
    /// - Parameter facts: The file's facts.
    /// - Returns: Its referenced and exported names.
    private static func usedNames(in facts: FileFacts?) -> [String] {
        (facts?.module.references ?? []) + (facts?.module.exports.map(\.name) ?? [])
    }

    /// Lists Swift files with their targets, sorted, leaving out skipped targets.
    ///
    /// - Parameter skipped: Targets whose public API is meant for other packages.
    /// - Returns: Each file and its target.
    func declarations(skipping skipped: Set<String>) -> [(file: String, target: String)] {
        targetOfFile.filter { !skipped.contains($0.value) }.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// Reports whether any other target refers to a name.
    ///
    /// - Parameters:
    ///   - name: The symbol name.
    ///   - target: The declaring target.
    /// - Returns: Whether a file in another target mentions it.
    func isUsed(_ name: String, outside target: String) -> Bool {
        referencesByTarget.contains { $0.key != target && $0.value.contains(name) }
    }
}

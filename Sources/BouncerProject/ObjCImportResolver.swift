import Foundation

/// Objective-C: a header and its implementation (`Foo.h` beside `Foo.m` or `Foo.mm`) are one node, named by
/// their shared path without an extension, so `A.m` importing `B.h` while `B.m` imports `A.h` is a cycle.
///
/// A quoted `#import "Foo.h"` resolves beside the importing file, then anywhere in the project when only one
/// file has that path suffix. `#import <Module/Foo.h>` and `@import Module;` resolve only when the project
/// holds a `Module/` folder with that header (or `Module/Module.h` for `@import`); anything else is a system
/// or package module. Mixed Swift and Objective-C meet at two headers: `#import "App-Swift.h"` is an edge to
/// Swift module `App` (`swift:App`, the same node the Swift resolver gives target `App`'s files, even when no
/// folder is named for it), and a `*-Bridging-Header.h` belongs to the Swift target whose folder holds it, so
/// its imports are edges from that Swift module to the Objective-C headers it exposes.
struct ObjCImportResolver: ImportResolver {
    /// The extensions this resolver handles; `.h` headers that aren't Objective-C carry no import facts.
    static let extensions = ["m", "mm", "h"]
    private static let swiftHeaderSuffix = "-Swift.h"
    private static let bridgingHeaderSuffix = "-Bridging-Header.h"

    private let paths: Set<String>
    /// Every Objective-C file, keyed by its file name, for resolving a quoted import repo-wide.
    private let byFileName: [String: [String]]

    /// Creates the resolver over the project's files.
    ///
    /// - Parameter paths: Every indexed file's repo-relative path.
    init(paths: Set<String>) {
        self.paths = paths
        let objc = paths.filter { Self.extensions.contains(($0 as NSString).pathExtension.lowercased()) }
        byFileName = Dictionary(grouping: objc.sorted()) { ($0 as NSString).lastPathComponent }
    }

    /// The node for an Objective-C file: its header-and-implementation pair, or a bridging header's Swift target.
    ///
    /// - Parameter path: The file's repo-relative path.
    /// - Returns: The path without its extension, or `swift:<Target>` for a bridging header.
    func node(of path: String) -> String {
        if path.hasSuffix(Self.bridgingHeaderSuffix) { return "swift:" + SwiftImportResolver.target(of: path) }
        return (path as NSString).deletingPathExtension
    }

    /// Resolves a `#import`, `#include`, or `@import` to the project node it refers to.
    ///
    /// - Parameters:
    ///   - specifier: `Foo.h`, `<Module/Foo.h>`, or `@import Module`, as `ObjCModuleFacts` records them.
    ///   - path: The importing file.
    /// - Returns: The imported node, or `nil` for a system, SDK, or package header.
    func resolve(_ specifier: String, from path: String) -> String? {
        if let module = Self.swiftModule(in: specifier) { return "swift:" + module }
        if specifier.hasPrefix("@import ") { return moduleUmbrella(specifier.dropFirst("@import ".count)) }
        if specifier.hasPrefix("<") { return frameworkHeader(String(specifier.dropFirst().dropLast())) }
        return localHeader(specifier, from: path)
    }

    /// Names the Swift module a generated `<Module>-Swift.h` header exposes.
    ///
    /// - Parameter specifier: The import as recorded.
    /// - Returns: The module, or `nil` if the specifier isn't a Swift header.
    private static func swiftModule(in specifier: String) -> String? {
        let header = specifier.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        let name = (header as NSString).lastPathComponent
        guard name.hasSuffix(swiftHeaderSuffix), name.count > swiftHeaderSuffix.count else { return nil }
        return String(name.dropLast(swiftHeaderSuffix.count))
    }

    /// Resolves a quoted header: beside the importing file, else the one project file with that path suffix.
    ///
    /// - Parameters:
    ///   - header: The quoted path, such as `Foo.h` or `Sub/Foo.h`.
    ///   - path: The importing file.
    /// - Returns: The header's node, or `nil` if no file, or more than one, matches.
    private func localHeader(_ header: String, from path: String) -> String? {
        if let sibling = ProjectPath.join(ProjectPath.directory(of: path), header), paths.contains(sibling) {
            return node(of: sibling)
        }
        return uniqueFile(endingWith: header).map(node(of:))
    }

    /// Resolves `<Module/Foo.h>` to a project file under a `Module/` folder, if exactly one exists.
    ///
    /// - Parameter header: The header without its angle brackets.
    /// - Returns: The header's node, or `nil` for a system or SDK header.
    private func frameworkHeader(_ header: String) -> String? {
        guard header.contains("/") else { return nil }
        return uniqueFile(endingWith: header).map(node(of:))
    }

    /// Resolves `@import Module` (or `Module.Submodule`) to the project's `Module/Module.h` umbrella header.
    ///
    /// - Parameter module: The imported module.
    /// - Returns: The umbrella header's node, or `nil` for a system or package module.
    private func moduleUmbrella(_ module: Substring) -> String? {
        let name = module.split(separator: ".").first.map(String.init) ?? String(module)
        return frameworkHeader(name + "/" + name + ".h")
    }

    /// Finds the one Objective-C file whose path ends in a header path, on a folder boundary.
    ///
    /// - Parameter suffix: The header path, such as `Foo.h` or `Module/Foo.h`.
    /// - Returns: The file, or `nil` if none or several match.
    private func uniqueFile(endingWith suffix: String) -> String? {
        let candidates = (byFileName[(suffix as NSString).lastPathComponent] ?? []).filter {
            $0 == suffix || $0.hasSuffix("/" + suffix)
        }
        return candidates.count == 1 ? candidates.first : nil
    }
}

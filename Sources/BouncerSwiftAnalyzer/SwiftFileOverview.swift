import SwiftSyntax

/// File-wide facts the per-declaration rules need up front: which function names are overloaded, and
/// which types an extension adds to.
final class SwiftFileOverview: SyntaxVisitor {
    private var nameCounts: [String: Int] = [:]
    private(set) var extendedTypes: Set<String> = []

    /// Creates an empty overview.
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    /// Reports whether more than one function in the file has a name, so a call by that name may mean an
    /// overload, perhaps with defaulted parameters left out.
    ///
    /// - Parameter name: The function name.
    /// - Returns: Whether it's overloaded within the file.
    func isOverloaded(_ name: String) -> Bool {
        (nameCounts[name] ?? 0) > 1
    }

    /// Counts a function's name.
    ///
    /// - Parameter node: The function.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        nameCounts[node.name.text, default: 0] += 1
        return .visitChildren
    }

    /// Records the type an extension adds to, by its last name component.
    ///
    /// - Parameter node: The extension.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription.split(separator: ".").last.map(String.init)
        if let name { extendedTypes.insert(name) }
        return .visitChildren
    }
}

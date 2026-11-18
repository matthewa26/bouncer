import SwiftSyntax
import BouncerCore

/// Walks a Swift syntax tree once, collecting everything the AST rules need.
final class SwiftDeclarationSummaryBuilder: SyntaxVisitor {
    private var functions: [CollectedFunction] = []
    private var types: [CollectedType] = []
    private var switches: [CollectedSwitch] = []
    private var importCount = 0
    private var forceUnwrapLines: [Int] = []
    private var forceTryLines: [Int] = []
    private let converter: SourceLocationConverter

    /// Creates a summary builder for a parsed file.
    ///
    /// - Parameter converter: Converts syntax positions to line numbers.
    init(converter: SourceLocationConverter) {
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    /// Assembles the collected summary. Call after visiting the whole tree.
    ///
    /// - Returns: Everything gathered during the walk.
    func summary() -> SwiftDeclarationSummary {
        SwiftDeclarationSummary(
            functions: functions, types: types, switches: switches,
            importCount: importCount, forceUnwrapLines: forceUnwrapLines, forceTryLines: forceTryLines
        )
    }

    /// Collects a function declaration's body, name, and doc comment status.
    ///
    /// - Parameter node: The function declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else { return .visitChildren }
        let function = collectFunction(
            name: node.name.text, body: body, leadingTrivia: node.leadingTrivia, modifiers: node.modifiers
        )
        functions.append(function)
        return .visitChildren
    }

    /// Collects an initializer's body and doc comment status, under the name `"init"`.
    ///
    /// - Parameter node: The initializer declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else { return .visitChildren }
        let function = collectFunction(
            name: "init", body: body, leadingTrivia: node.leadingTrivia, modifiers: node.modifiers
        )
        functions.append(function)
        return .visitChildren
    }

    /// Collects a class declaration's member count and extent.
    ///
    /// - Parameter node: The class declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        types.append(collectedType(name: node.name.text, node: node))
        return .visitChildren
    }

    /// Collects a struct declaration's member count and extent.
    ///
    /// - Parameter node: The struct declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        types.append(collectedType(name: node.name.text, node: node))
        return .visitChildren
    }

    /// Collects a switch expression's branch count and starting line.
    ///
    /// - Parameter node: The switch expression being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        let line = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        switches.append(CollectedSwitch(caseCount: node.cases.count, startLine: line))
        return .visitChildren
    }

    /// Counts one import declaration toward the file's coupling proxy.
    ///
    /// - Parameter node: The import declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        importCount += 1
        return .visitChildren
    }

    /// Records a force-unwrap expression's line.
    ///
    /// - Parameter node: The force-unwrap expression being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        forceUnwrapLines.append(converter.location(for: node.positionAfterSkippingLeadingTrivia).line)
        return .visitChildren
    }

    /// Records a `try!` expression's line, ignoring plain `try`/`try?`.
    ///
    /// - Parameter node: The try expression being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
            forceTryLines.append(converter.location(for: node.positionAfterSkippingLeadingTrivia).line)
        }
        return .visitChildren
    }

    /// Builds a `CollectedFunction` from a declaration's body, leading trivia, and modifiers.
    ///
    /// - Parameters:
    ///   - name: The function or initializer's name.
    ///   - body: The declaration's body block.
    ///   - leadingTrivia: The declaration's leading trivia, checked for a doc comment.
    ///   - modifiers: The declaration's modifiers, checked for access level.
    /// - Returns: The collected function.
    private func collectFunction(
        name: String, body: CodeBlockSyntax, leadingTrivia: Trivia, modifiers: DeclModifierListSyntax
    ) -> CollectedFunction {
        let counter = BranchCounter()
        counter.walk(body)
        let start = converter.location(for: body.positionAfterSkippingLeadingTrivia).line
        let end = converter.location(for: body.endPositionBeforeTrailingTrivia).line
        return CollectedFunction(
            name: name, startLine: start, endLine: end, branchCount: counter.count,
            hasDocComment: hasComment(leadingTrivia), visibility: visibility(of: modifiers)
        )
    }

    /// Determines a declaration's access level from its modifiers.
    ///
    /// - Parameter modifiers: The declaration's modifiers.
    /// - Returns: `.public` for `public`/`open`, `.private` for `private`/`fileprivate`, else `.internal`.
    private func visibility(of modifiers: DeclModifierListSyntax) -> DeclarationVisibility {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.open): return .public
            case .keyword(.private), .keyword(.fileprivate): return .private
            default: continue
            }
        }
        return .internal
    }

    /// Builds a `CollectedType` from a class or struct declaration's member block.
    ///
    /// - Parameters:
    ///   - name: The type's name.
    ///   - node: The type declaration, for its member block and start position.
    /// - Returns: The collected type.
    private func collectedType(name: String, node: some DeclGroupSyntax) -> CollectedType {
        let memberBlock = node.memberBlock
        let startLine = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        let endLine = converter.location(for: memberBlock.endPositionBeforeTrailingTrivia).line
        return CollectedType(name: name, memberCount: memberBlock.members.count, startLine: startLine, endLine: endLine)
    }

    /// Reports whether a trivia collection contains any comment, doc or otherwise.
    ///
    /// - Parameter trivia: The trivia to check.
    /// - Returns: Whether a comment piece is present.
    private func hasComment(_ trivia: Trivia) -> Bool {
        trivia.contains {
            switch $0 {
            case .lineComment, .docLineComment, .blockComment, .docBlockComment: return true
            default: return false
            }
        }
    }
}

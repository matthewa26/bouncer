import SwiftSyntax
import BouncerCore
import BouncerRules

/// Walks a Swift syntax tree once, collecting everything the AST rules need.
final class SwiftDeclarationSummaryBuilder: SyntaxVisitor {
    private var functions: [CollectedFunction] = []
    private var types: [CollectedType] = []
    private var switches: [CollectedSwitch] = []
    private var importCount = 0
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
    /// - Parameters:
    ///   - markers: The file's single-location smells, from `SwiftMarkerCollector`.
    ///   - names: The file's declared names and string literals, from `SwiftNameCollector`.
    /// - Returns: Everything gathered during the walk.
    func summary(markers: [CollectedMarker], names: SwiftNameCollector) -> DeclarationSummary {
        DeclarationSummary(
            functions: functions, types: types, switches: switches, importCount: importCount, markers: markers,
            declaredNames: names.names, stringLiterals: names.strings
        )
    }

    /// Collects a function declaration's body, name, and doc comment status.
    ///
    /// - Parameter node: The function declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(name: node.name.text, node: node, signature: node.signature, body: node.body)
    }

    /// Collects an initializer's body and doc comment status, under the name `"init"`.
    ///
    /// - Parameter node: The initializer declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(name: "init", node: node, signature: node.signature, body: node.body)
    }

    /// Collects a function or initializer that has a body; protocol requirements have none.
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - node: The declaration, for its leading trivia and modifiers.
    ///   - signature: Its signature, for its parameter count.
    ///   - body: Its body, if any.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    private func collect(
        name: String, node: some WithModifiersSyntax, signature: FunctionSignatureSyntax, body: CodeBlockSyntax?
    ) -> SyntaxVisitorContinueKind {
        guard let body else { return .visitChildren }
        let declaration = FunctionDeclaration(
            name: name, leadingTrivia: node.leadingTrivia, modifiers: node.modifiers,
            parameters: signature.parameterClause.parameters
        )
        functions.append(collectFunction(declaration, body: body))
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

    /// The parts of a function or initializer declaration that `collectFunction` reads.
    private struct FunctionDeclaration {
        let name: String
        let leadingTrivia: Trivia
        let modifiers: DeclModifierListSyntax
        let parameters: FunctionParameterListSyntax

        /// The boolean flag parameters; 0 for an initializer, since storing a `Bool` isn't branching on one.
        var flagCount: Int {
            name == "init" ? 0 : parameters.filter(SwiftFunctionMetricsCollector.isBooleanFlag).count
        }

        /// Measures this declaration's body together with its parameters.
        ///
        /// - Parameter body: The declaration's body block.
        /// - Returns: The function's measurements.
        func metrics(of body: CodeBlockSyntax) -> FunctionMetrics {
            SwiftFunctionMetricsCollector.measure(
                body, parameterCount: parameters.count, booleanParameterCount: flagCount
            )
        }
    }

    /// Builds a `CollectedFunction` from a declaration and its body.
    ///
    /// - Parameters:
    ///   - declaration: The declaration's name, leading trivia, modifiers, and parameters.
    ///   - body: The declaration's body block.
    /// - Returns: The collected function.
    private func collectFunction(_ declaration: FunctionDeclaration, body: CodeBlockSyntax) -> CollectedFunction {
        let counter = BranchCounter()
        counter.walk(body)
        let start = converter.location(for: body.positionAfterSkippingLeadingTrivia).line
        let end = converter.location(for: body.endPositionBeforeTrailingTrivia).line
        return CollectedFunction(
            name: declaration.name, startLine: start, endLine: end, branchCount: counter.count,
            hasDocComment: declaration.leadingTrivia.hasComment, visibility: visibility(of: declaration.modifiers),
            metrics: declaration.metrics(of: body)
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
        return CollectedType(
            name: name, memberCount: memberBlock.members.count, startLine: startLine, endLine: endLine,
            cohesionGroups: SwiftCohesion.groupCount(of: memberBlock),
            shape: SwiftCohesion.shape(of: memberBlock, isClass: node.is(ClassDeclSyntax.self))
        )
    }
}

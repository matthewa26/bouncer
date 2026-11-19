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
    private let overview = SwiftFileOverview()

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
    ///   - shapes: The file's type extents, closures, and typed names, from `SwiftShapeCollector`.
    ///   - unused: The file's unused declarations, from `SwiftDeadCodeCollector`.
    /// - Returns: Everything gathered during the walk.
    func summary(
        markers: [CollectedMarker], names: SwiftNameCollector, shapes: ShapeFacts, unused: [UnusedDeclaration]
    ) -> DeclarationSummary {
        DeclarationSummary(
            functions: functions, types: types, switches: switches, importCount: importCount, markers: markers,
            declaredNames: names.names, stringLiterals: names.strings, unusedDeclarations: unused, shapes: shapes
        )
    }

    /// Collects a function declaration's body, name, and doc comment status.
    ///
    /// - Parameter node: The function declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let labels = node.signature.parameterClause.parameters.map(\.firstName.text)
        let name = node.name.text, isTest = SwiftAssertionFinder.isTest(node)
        return collect(name: name, node: node, signature: node.signature, body: node.body, traits: Traits(
            selfCall: overview.isOverloaded(name) ? nil : SwiftCallSignature(name: name, labels: labels),
            isTest: isTest
        ))
    }

    /// Collects an initializer's body and doc comment status, under the name `"init"`.
    ///
    /// - Parameter node: The initializer declaration being visited.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(name: "init", node: node, signature: node.signature, body: node.body, traits: Traits())
    }

    /// Reads the file-wide facts before any declaration is collected.
    ///
    /// - Parameter node: The file.
    /// - Returns: `.visitChildren`.
    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        overview.walk(node)
        return .visitChildren
    }

    /// How a function is checked beyond its body: the self-call signature (`nil` for an initializer or an
    /// overload, whose same-labeled calls may mean another declaration) and whether it's a test.
    private struct Traits {
        var selfCall: SwiftCallSignature?
        var isTest = false
    }

    /// Collects a function or initializer that has a body; protocol requirements have none.
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - node: The declaration, for its leading trivia and modifiers.
    ///   - signature: Its signature, for its parameters, return type, and effects.
    ///   - body: Its body, if any.
    ///   - traits: Its self-call signature and test status.
    /// - Returns: `.visitChildren`, so nested declarations are also visited.
    private func collect(
        name: String, node: some WithModifiersSyntax, signature: FunctionSignatureSyntax, body: CodeBlockSyntax?,
        traits: Traits
    ) -> SyntaxVisitorContinueKind {
        guard let body else { return .visitChildren }
        let declaration = FunctionDeclaration(
            name: name, leadingTrivia: node.leadingTrivia, modifiers: node.modifiers, signature: signature,
            traits: traits
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
        let signature: FunctionSignatureSyntax
        let traits: Traits

        /// The declared parameters.
        var parameters: FunctionParameterListSyntax { signature.parameterClause.parameters }

        /// Reads the doc comment and signature facts, for the doc-completeness rules.
        ///
        /// - Parameter body: The declaration's body block.
        /// - Returns: The facts, or `nil` without a doc comment.
        func documentation(of body: CodeBlockSyntax) -> DocumentationFacts? {
            SwiftDocumentation.facts(trivia: leadingTrivia, signature: signature, body: body)
        }

        /// Lists the parameters callers must pass, with their types, for `primitive-obsession`; parameters
        /// with a default value, such as `line: UInt = #line`, are left out.
        ///
        /// - Parameter line: The line to record them on.
        /// - Returns: One name per required parameter the body can refer to.
        func typedParameters(line: Int) -> [CollectedName] {
            parameters.filter { $0.defaultValue == nil }.compactMap { parameter in
                let name = (parameter.secondName ?? parameter.firstName).text
                let type = parameter.type.trimmedDescription
                return name == "_" ? nil : CollectedName(name: name, line: line, typeName: type, isParameter: true)
            }
        }

        /// The boolean flag parameters; 0 for an initializer, since storing a `Bool` isn't branching on one.
        var flagCount: Int {
            name == "init" ? 0 : parameters.filter(SwiftFunctionMetricsCollector.isBooleanFlag).count
        }

        /// Measures this declaration's body together with its parameters.
        ///
        /// - Parameter body: The declaration's body block.
        /// - Returns: The function's measurements.
        func metrics(of body: CodeBlockSyntax) -> FunctionMetrics {
            let shape = SwiftFunctionMetricsCollector.BodyShape(
                flow: SwiftFlowCollector.measure(body, signature: traits.selfCall),
                halstead: SwiftHalstead.counts(of: body),
                testAssertionCount: traits.isTest ? SwiftAssertionFinder.assertionCount(in: body) : nil
            )
            return SwiftFunctionMetricsCollector.measure(
                body, parameterCount: parameters.count, booleanParameterCount: flagCount, shape: shape
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
        let start = converter.location(for: body.positionAfterSkippingLeadingTrivia).line
        let end = converter.location(for: body.endPositionBeforeTrailingTrivia).line
        return CollectedFunction(
            name: declaration.name, startLine: start, endLine: end, branchCount: Self.branchCount(in: body),
            hasDocComment: declaration.leadingTrivia.hasComment, visibility: Self.visibility(of: declaration.modifiers),
            metrics: declaration.metrics(of: body), documentation: declaration.documentation(of: body),
            parameters: declaration.typedParameters(line: start)
        )
    }

    /// Counts a body's decision points.
    ///
    /// - Parameter body: The body.
    /// - Returns: Its branch count, for cyclomatic complexity.
    private static func branchCount(in body: CodeBlockSyntax) -> Int {
        let counter = BranchCounter()
        counter.walk(body)
        return counter.count
    }

    /// Determines a declaration's access level from its modifiers.
    ///
    /// - Parameter modifiers: The declaration's modifiers.
    /// - Returns: `.public` for `public`/`open`, `.private` for `private`/`fileprivate`, else `.internal`.
    static func visibility(of modifiers: DeclModifierListSyntax) -> DeclarationVisibility {
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
        let structure = SwiftTypeStructure.structure(of: node, isExtended: overview.extendedTypes.contains(name))
        let (startLine, endLine) = extent(of: node)
        return CollectedType(
            name: name, memberCount: node.memberBlock.members.count, startLine: startLine, endLine: endLine,
            cohesionGroups: CohesionGraph.groupCount(structure.methods),
            shape: SwiftCohesion.shape(of: node.memberBlock, isClass: node.is(ClassDeclSyntax.self)),
            structure: structure, design: SwiftTypeDesign.design(of: node, name: name, converter: converter)
        )
    }

    /// Finds a type declaration's first and last lines.
    ///
    /// - Parameter node: The type declaration.
    /// - Returns: The 1-indexed lines its declaration starts and its member block ends on.
    private func extent(of node: some DeclGroupSyntax) -> (Int, Int) {
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia).line
        return (start, converter.location(for: node.memberBlock.endPositionBeforeTrailingTrivia).line)
    }
}

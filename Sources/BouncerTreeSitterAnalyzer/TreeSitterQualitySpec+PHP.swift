/// PHP grammar node names the PHP specs share.
enum PHPNode {
    static let comment = "comment"
    static let ifStatement = "if_statement"
    static let binaryExpression = "binary_expression"
    static let conditionalExpression = "conditional_expression"
    static let methodDeclaration = "method_declaration"
    static let tryStatement = "try_statement"
    static let catchClause = "catch_clause"
    static let throwExpression = "throw_expression"
    static let compoundStatement = "compound_statement"
    static let caseStatement = "case_statement"
    static let elseIfClause = "else_if_clause"
    static let argument = "argument"
    /// Named functions, closures, and arrow functions.
    static let functions = closures.union(["function_definition", methodDeclaration])
    /// Closures (`function () use ($x) { … }`) and arrow functions (`fn ($x) => …`).
    static let closures: Set<String> = ["anonymous_function", "arrow_function"]
    /// `&&`, `||`, and their low-precedence spellings `and` and `or`.
    static let logicalOperators: Set<String> = ["&&", "||", "and", "or"]
    static let loops: Set<String> = ["for_statement", "foreach_statement", "while_statement", "do_statement"]
    static let switches: Set<String> = ["switch_statement", "match_expression"]
    /// A `switch`'s `case`s and a `match`'s arms, without their defaults.
    static let cases: Set<String> = [caseStatement, "match_conditional_expression"]
    static let defaultCases: Set<String> = ["default_statement", "match_default_expression"]
    /// The other decision points: `if` and `elseif`, cases and arms, `catch`, and the ternary.
    static let decisions = cases.union([ifStatement, elseIfClause, catchClause, conditionalExpression])
    /// The statements that branch or repeat.
    static let branches = loops.union(switches).union([ifStatement])
    /// Markup outside `<?php … ?>`, which isn't code.
    static let markup: Set<String> = ["text", "text_interpolation"]
    /// String literals: single-quoted, double-quoted (which interpolate), heredocs, and nowdocs.
    static let strings: Set<String> = ["string", "encapsed_string", "heredoc", "nowdoc"]
}

/// PHP's node types for the function-shape, cohesion, flow, and size rules.
///
/// Constructor property promotion (`private int $a`) and a variadic (`...$rest`) are parameters. The design-smell
/// facts, call-chain rules, and recursion check read a call's callee field, which PHP's method calls
/// (`member_call_expression`) don't have, so they aren't mapped.
extension TreeSitterQualitySpec {
    /// PHP's quality node types.
    static let php = TreeSitterQualitySpec(
        complexity: phpComplexity, parameters: phpParameters, statements: phpStatements, numbers: phpNumbers,
        markers: [], cohesion: phpCohesion, initializerNames: ["__construct"], conventions: phpConventions,
        shapes: .php, flow: .php
    )

    /// Branches, loops, and `catch` nest; `else` and `elseif` score one flat, as does each new logical run.
    private static let phpComplexity = ComplexitySpec(
        nestingNodeTypes: PHPNode.branches.union([PHPNode.catchClause]),
        elseNodeTypes: ["else_clause", PHPNode.elseIfClause], elseIfParentTypes: ["else_clause"], alternativeField: nil,
        ternaryNodeType: PHPNode.conditionalExpression, logicalNodeType: PHPNode.binaryExpression,
        logicalOperators: PHPNode.logicalOperators, closureNodeTypes: [], returnNodeType: "return_statement"
    )

    /// Plain, promoted, and variadic parameters; a `bool` one, or one defaulting to `true`/`false`, is a flag.
    private static let phpParameters = ParameterSpec(
        ignoredNodeTypes: [PHPNode.comment], receiverNames: [], groupedNameNodeType: nil,
        booleanTypeField: "type", booleanTypeText: "bool", defaultFields: ["default_value"],
        booleanLiteralNodeTypes: ["boolean"], booleanTypeAliases: ["?bool"]
    )

    /// Blocks and jumps, with a `throw` looked through its `expression_statement`; markup after a jump isn't code.
    private static let phpStatements = StatementSpec(
        catchNodeType: PHPNode.catchClause, noOpNodeTypes: [],
        blockNodeTypes: [PHPNode.compoundStatement, "colon_block", PHPNode.caseStatement, "default_statement"],
        jumpNodeTypes: [
            "return_statement", PHPNode.throwExpression, "break_statement", "continue_statement", "exit_statement"
        ],
        hoistedNodeTypes: PHPNode.markup.union(
            [PHPNode.comment, "function_definition", "class_declaration", "interface_declaration", "empty_statement"]
        ),
        wrapperNodeTypes: ["expression_statement"]
    )

    /// Number literals, and what names them: constants, properties, defaults, assignments, enum cases, `case`
    /// labels, `match` conditions, and keyed array entries (`['timeout' => 30]`).
    private static let phpNumbers = NumberSpec(
        literalNodeTypes: ["integer", "float"], allowed: ["0", "1", "2", "0.0", "1.0"],
        namingParents: [
            "const_element", "property_element", "simple_parameter", "property_promotion_parameter",
            "assignment_expression", "augmented_assignment_expression", "enum_case", PHPNode.caseStatement,
            "match_condition_list", "array_element_initializer", "declare_directive"
        ],
        transparentParents: [
            "parenthesized_expression", "unary_op_expression", PHPNode.binaryExpression, "arguments", PHPNode.argument,
            "function_call_expression", "member_call_expression", "scoped_call_expression",
            "object_creation_expression", "array_creation_expression", "cast_expression"
        ]
    )

    /// Methods and `$this->x` access; a property declaration lists its `$x` fields as elements.
    private static let phpCohesion: CohesionSpec = {
        var spec = CohesionSpec(
            methodNodeTypes: [PHPNode.methodDeclaration], fieldNameFields: ["property_declaration": "name"],
            memberAccessNodeType: "member_access_expression", objectField: "object", propertyField: "name",
            receiverText: "$this", staticKeyword: "static_modifier"
        )
        (spec.fieldElementNodeType, spec.fieldSigil) = ("property_element", "$")
        return spec
    }()

    /// `else` after a jump, `global` state, `instanceof`, tests, and plain string literals.
    private static let phpConventions = ConventionSpec(
        ifNodeType: PHPNode.ifStatement, rootNodeTypes: ["program"], globalStatementNodeTypes: ["global_declaration"],
        typeChecks: [FieldMatch(nodeType: PHPNode.binaryExpression, field: "operator", texts: ["instanceof"])],
        tests: phpTests,
        stringNodeTypes: ["string", "encapsed_string"], stringContentTypes: ["string_content"],
        interpolationTypes: [
            "variable_name", "member_access_expression", "nullsafe_member_access_expression", "subscript_expression",
            "member_call_expression", "dynamic_variable_name", "scoped_property_access_expression"
        ]
    )

    /// Tests, only in test files (see `PHPSyntax.testPathPattern`): a PHPUnit `test…` method, one marked
    /// `#[Test]` or `/** @test */`, or a Pest `it`/`test` callback. PHPUnit's `assert…` calls,
    /// `addToAssertionCount`, `expectException…`, `expectOutput…`, and `expectNotToPerformAssertions`, and Pest's
    /// `expect(…)` are its assertions.
    private static let phpTests: TestSpec = {
        var spec = TestSpec(
            callbackCallees: ["it", "test"], namePattern: "^test",
            assertionPattern: #"(->|::)\s*(assert\w*|addToAssertionCount|expect(Exception|Output)\w*"#
                + #"|expectNotToPerformAssertions)\s*\(|\bexpect\s*\("#,
            attributePattern: #"^#\[\s*(\\?PHPUnit\\Framework\\Attributes\\)?Test\b|^/\*\*[\s\S]*@test\b"#,
            attributeNodeTypes: [PHPNode.comment]
        )
        (spec.attributeField, spec.argumentNodeType) = ("attributes", PHPNode.argument)
        spec.pathPattern = PHPSyntax.testPathPattern
        return spec
    }()
}

extension FlowSpec {
    /// PHP's flow node types. PHPDoc's `@param` tags aren't checked for completeness.
    static let php: FlowSpec = {
        var spec = FlowSpec(
            elifNodeType: PHPNode.elseIfClause, loopNodeTypes: PHPNode.loops, switchNodeTypes: PHPNode.switches,
            caseNodeTypes: PHPNode.cases, defaultCaseNodeTypes: PHPNode.defaultCases,
            tryNodeTypes: [PHPNode.tryStatement], handlerNodeTypes: [PHPNode.catchClause],
            breakTargetNodeTypes: ["switch_statement"],
            baseCaseNodeTypes: PHPNode.branches.union(
                [PHPNode.conditionalExpression, PHPNode.tryStatement, PHPNode.throwExpression]
            ),
            selfReceiver: "$this", atomicOperandTypes: PHPNode.strings
        )
        (spec.ifNodeType, spec.consequenceField) = (PHPNode.ifStatement, "body")
        spec.caseContainerNodeTypes = ["switch_block", "match_block"]
        spec.classDecorationTypes = ["base_clause", "class_interface_clause", "attribute_list", "abstract_modifier"]
        return spec
    }()
}

extension ShapeSpec {
    /// PHP's shape node types: classes, interfaces, traits, and enums as types; closures; and logical chains.
    static let php = ShapeSpec(
        typeNodeTypes: Dictionary(uniqueKeysWithValues: TreeSitterLanguageSpec.phpTypeNodeTypes.map { ($0, "name") }),
        rootNodeTypes: ["program"], closureNodeTypes: PHPNode.closures,
        logical: LogicalSpec(
            nodeType: PHPNode.binaryExpression, operators: PHPNode.logicalOperators,
            parenthesizedNodeType: "parenthesized_expression", negationNodeType: "unary_op_expression",
            negationOperandField: PHPNode.argument
        )
    )
}

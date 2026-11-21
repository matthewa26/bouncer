/// Rust grammar node and field names the Rust specs share.
enum RustNode {
    static let ifExpression = "if_expression"
    static let matchExpression = "match_expression"
    static let binaryExpression = "binary_expression"
    static let letDeclaration = "let_declaration"
    static let stringLiteral = "string_literal"
    static let patternField = "pattern"
    /// `&&` and `||`.
    static let logicalOperators: Set<String> = ["&&", "||"]
    /// Line and block comments, doc comments included.
    static let comments: Set<String> = ["line_comment", "block_comment"]
    /// Loops with a condition or an iterator, which cyclomatic complexity counts; a bare `loop` has neither.
    static let conditionalLoops: Set<String> = ["while_expression", "for_expression"]
    /// Every loop, `loop` included.
    static let loops = conditionalLoops.union(["loop_expression"])
    /// The expressions that branch or repeat.
    static let branches = loops.union([ifExpression, matchExpression])
}

/// Rust's node types for the function-shape, flow, and size rules.
///
/// Rust has no ternary (an `if` is already an expression), no `catch`, and no classes, so `nested-ternary`,
/// `empty-catch`, and LCOM4 don't apply; nor do the design-smell facts, which need a type's methods beside its
/// fields, while Rust keeps them in separate `impl` blocks. `self` is a `self_parameter`, which isn't counted.
extension TreeSitterQualitySpec {
    /// Rust's quality node types.
    static let rust = TreeSitterQualitySpec(
        complexity: rustComplexity, parameters: rustParameters, statements: rustStatements, numbers: rustNumbers,
        markers: [], cohesion: nil, initializerNames: ["new", "default"], conventions: rustConventions,
        shapes: .rust, flow: .rust
    )

    /// Branches and loops nest; `else` and each new `&&`/`||` run score one; closures are nested functions.
    private static let rustComplexity = ComplexitySpec(
        nestingNodeTypes: RustNode.branches, elseNodeTypes: ["else_clause"], elseIfParentTypes: ["else_clause"],
        alternativeField: nil, ternaryNodeType: nil, logicalNodeType: RustNode.binaryExpression,
        logicalOperators: RustNode.logicalOperators, closureNodeTypes: ["closure_expression"],
        returnNodeType: "return_expression"
    )

    /// Parameters, without `self`, attributes, comments, or a C-variadic `...`; a `bool` one is a flag.
    private static let rustParameters = ParameterSpec(
        ignoredNodeTypes: RustNode.comments.union(["self_parameter", "attribute_item", "variadic_parameter"]),
        receiverNames: [], groupedNameNodeType: nil, booleanTypeField: "type", booleanTypeText: "bool",
        defaultFields: [], booleanLiteralNodeTypes: []
    )

    /// Blocks and jumps, with a statement's `expression_statement` wrapper looked through.
    private static let rustStatements = StatementSpec(
        catchNodeType: nil, noOpNodeTypes: [], blockNodeTypes: ["block", "expression_statement"],
        jumpNodeTypes: ["return_expression", "break_expression", "continue_expression"],
        hoistedNodeTypes: RustNode.comments.union(rustItems), wrapperNodeTypes: ["expression_statement"]
    )

    /// Items that may follow a `return` in a block without being unreachable, since they're declarations.
    private static let rustItems: Set<String> = [
        "function_item", "struct_item", "enum_item", "union_item", "trait_item", "impl_item", "use_declaration",
        "const_item", "static_item", "type_item", "mod_item", "macro_definition", "attribute_item"
    ]

    /// `else` after a jump, method-call chains, tests, and the names the naming rules check: `let` bindings and
    /// function parameters, but not closure parameters, where Rust's one-letter `|a, b| a.cmp(b)` is idiomatic.
    private static let rustConventions = ConventionSpec(
        ifNodeType: RustNode.ifExpression, rootNodeTypes: ["source_file"],
        chain: ChainSpec(
            callNodeType: "call_expression", calleeField: "function", memberNodeType: "field_expression",
            objectField: "value", propertyField: "field"
        ),
        tests: rustTests,
        nameFields: [RustNode.letDeclaration: RustNode.patternField, "parameter": RustNode.patternField],
        stringNodeTypes: [RustNode.stringLiteral], stringContentTypes: ["string_content"]
    )

    /// Tests: a function with a `#[test]`-style attribute (`#[test]`, `#[tokio::test]`, `#[rstest]`, …). Its
    /// assertions are the `assert` macros, or `#[should_panic]`, which fails the test unless it panics; `.unwrap()`
    /// and `.expect()` only crash, so they don't count.
    private static let rustTests = TestSpec(
        callbackCallees: [], namePattern: nil,
        assertionPattern: #"\b(debug_)?assert(_eq|_ne)?!|\bassert_matches!|\bprop_assert\w*!|#\[\s*should_panic\b"#,
        attributePattern: #"^#\[\s*((\w+::)*test|rstest|test_case|quickcheck)\b"#,
        attributeNodeTypes: RustSyntax.preambleNodeTypes
    )

    /// Number literals, and what names them: `let`, `const`, and `static` bindings, struct fields, enum
    /// discriminants, `match` patterns, array lengths, and macro arguments (`assert_eq!(n, 3)`), whose
    /// tokens tree-sitter leaves unparsed.
    private static let rustNumbers = NumberSpec(
        literalNodeTypes: ["integer_literal", "float_literal"], allowed: ["0", "1", "2", "0.0", "1.0"],
        namingParents: [
            RustNode.letDeclaration, "const_item", "static_item", "field_initializer", "enum_variant", "match_pattern",
            "assignment_expression", "array_type", "token_tree", "attribute", "const_parameter"
        ],
        transparentParents: [
            "parenthesized_expression", "unary_expression", RustNode.binaryExpression, "arguments", "call_expression",
            "array_expression", "tuple_expression", "type_cast_expression", "range_expression", "range_pattern",
            "negative_literal", "tuple_pattern", "or_pattern"
        ]
    )
}

extension FlowSpec {
    /// Rust's flow node types. Rustdoc has no per-parameter doc convention, so doc completeness isn't checked.
    static let rust: FlowSpec = {
        var spec = FlowSpec(
            loopNodeTypes: RustNode.loops, switchNodeTypes: [RustNode.matchExpression], caseNodeTypes: ["match_arm"],
            defaultCaseNodeTypes: [], tryNodeTypes: [], handlerNodeTypes: [], breakTargetNodeTypes: [],
            baseCaseNodeTypes: RustNode.branches.union(["try_expression"]), selfReceiver: "self",
            atomicOperandTypes: [RustNode.stringLiteral, "raw_string_literal", "char_literal"]
        )
        spec.ifNodeType = RustNode.ifExpression
        spec.jumps = LoopJumpSpec(breakNodeTypes: ["break_expression"], continueNodeTypes: ["continue_expression"],
                                  loopLabelNodeType: "label")
        (spec.labelNodeTypes, spec.caseContainerNodeTypes, spec.classDecorationTypes) = (
            ["label"], ["match_block"], ["type_parameters"]
        )
        return spec
    }()
}

extension ShapeSpec {
    /// Rust's shape node types: structs, enums, unions, and traits as types; closures; `&&`/`||` chains;
    /// generic type parameters (not lifetimes); and `let` bindings as locals.
    static let rust: ShapeSpec = {
        var spec = ShapeSpec(rootNodeTypes: ["source_file"], closureNodeTypes: ["closure_expression"], names: rustNames)
        spec.typeNodeTypes = Dictionary(
            uniqueKeysWithValues: TreeSitterLanguageSpec.rustTypeNodeTypes.map { ($0, "name") }
        )
        spec.logical = LogicalSpec(
            nodeType: RustNode.binaryExpression, operators: RustNode.logicalOperators,
            parenthesizedNodeType: "parenthesized_expression", negationNodeType: "unary_expression",
            negationOperandField: "operand"
        )
        spec.generics = GenericSpec(
            listNodeType: "type_parameters", parameterNodeType: "type_parameter", groupedNameNodeType: nil
        )
        spec.locals = LocalSpec(declarationNodeTypes: [RustNode.letDeclaration: RustNode.patternField],
                                listNodeTypes: ["tuple_pattern"])
        return spec
    }()

    /// The bindings that name things, and the types their literals imply.
    private static let rustNames = NameSpec(
        sources: [
            NameSource(nodeType: RustNode.letDeclaration, nameField: RustNode.patternField, typeField: "type",
                       valueField: "value"),
            NameSource(nodeType: "parameter", nameField: RustNode.patternField, typeField: "type", isParameter: true),
            NameSource(nodeType: "field_declaration", nameField: "name", typeField: "type")
        ],
        nameNodeTypes: ["identifier", "field_identifier"],
        literalTypes: [
            RustNode.stringLiteral: "&str", "raw_string_literal": "&str", "integer_literal": "i32",
            "float_literal": "f64", "boolean_literal": "bool", "char_literal": "char"
        ],
        constructorFields: ["struct_expression": "name"]
    )
}

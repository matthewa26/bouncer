/// Objective-C's node types for the function-shape, cohesion, flow, and size rules.
///
/// Statements and expressions are C's; Objective-C adds `@try`/`@catch`/`@finally` (`try_statement`,
/// `catch_clause`), `@throw` (`throw_statement`), blocks (`block_literal`, measured as closures), and
/// `self.x` property access (`field_expression`), which LCOM4 reads as a method touching field `x`.
extension TreeSitterQualitySpec {
    /// Objective-C's quality node types. The design-smell facts (coupling, feature envy) aren't mapped.
    static let objc = TreeSitterQualitySpec(
        complexity: ComplexitySpec(
            nestingNodeTypes: objcBranches.union(["catch_clause"]),
            elseNodeTypes: ["else_clause"], elseIfParentTypes: ["else_clause"], alternativeField: nil,
            ternaryNodeType: "conditional_expression", logicalNodeType: "binary_expression",
            logicalOperators: ["&&", "||"], closureNodeTypes: ["block_literal"], returnNodeType: "return_statement"
        ),
        parameters: ParameterSpec(
            ignoredNodeTypes: ["comment", "variadic_parameter"], receiverNames: ["void"], groupedNameNodeType: nil,
            booleanTypeField: "type", booleanTypeText: "BOOL", defaultFields: [], booleanLiteralNodeTypes: [],
            booleanTypeAliases: ["bool", "_Bool"], typeChildNodeType: "method_type"
        ),
        statements: StatementSpec(
            catchNodeType: "catch_clause", noOpNodeTypes: [],
            blockNodeTypes: ["compound_statement", "case_statement"],
            jumpNodeTypes: [
                "return_statement", "throw_statement", "break_statement", "continue_statement", "goto_statement"
            ],
            hoistedNodeTypes: ["comment", "labeled_statement", "case_statement"]
        ),
        numbers: objcNumbers,
        markers: [],
        cohesion: CohesionSpec(
            methodNodeTypes: ["method_definition"], fieldNameFields: [:],
            memberAccessNodeType: "field_expression", objectField: "argument", propertyField: "field",
            receiverText: "self", staticKeyword: "+"
        ),
        initializerNames: ["init", "dealloc"],
        conventions: objcConventions,
        shapes: .objc,
        flow: .objc
    )

    /// Loops: `for` (C and `for … in`), `while`, and `do … while`.
    static let objcLoops: Set<String> = ["for_statement", "while_statement", "do_statement"]

    /// Statements that branch or repeat: the loops, `if`, and `switch`.
    static let objcBranches = objcLoops.union(["if_statement", "switch_statement"])

    /// Number literals, and the declarations, assignments, `case` labels, and enumerators that name them.
    private static let objcNumbers = NumberSpec(
        literalNodeTypes: ["number_literal"], allowed: ["0", "1", "2", "0.0", "1.0", "0.0f", "1.0f"],
        namingParents: [
            "init_declarator", "assignment_expression", "case_statement", "enumerator", "initializer_pair",
            "bitfield_clause", "property_declaration"
        ],
        transparentParents: [
            "parenthesized_expression", "unary_expression", "binary_expression", "argument_list", "call_expression",
            "message_expression", "at_expression", "array_literal", "initializer_list", "cast_expression"
        ]
    )

    /// What counts as an assertion in an Objective-C test: XCTest's assertion macros, an XCTest expectation (which
    /// fails the test when it isn't fulfilled), OCMock's `OCMVerify`, Expecta's `expect(…)`, and, as for Swift, a
    /// message to a `verify…`, `assert…`, or `expect…` helper on `self`.
    private static let objcAssertions =
        #"\bXCT(Assert|Fail|Unwrap)\w*\s*\(|\b(expectationWithDescription|expectationForPredicate|"#
        + #"expectationForNotification|waitForExpectations\w*)\b|\bOCMVerify\w*\s*\(|\bexpect\s*\(|"#
        + #"\[\s*self\s+(verify|assert|expect)\w*"#

    /// `else` after a jump, C calls and member chains, XCTest tests, and the names the naming rules check.
    private static let objcConventions = ConventionSpec(
        ifNodeType: "if_statement", rootNodeTypes: ["translation_unit"],
        chain: ChainSpec(
            callNodeType: "call_expression", calleeField: "function", memberNodeType: "field_expression",
            objectField: "argument", propertyField: "field"
        ),
        tests: TestSpec(callbackCallees: [], namePattern: "^test", assertionPattern: objcAssertions),
        nameFields: [
            "declaration": "declarator", "init_declarator": "declarator", "pointer_declarator": "declarator",
            "parameter_declaration": "declarator"
        ],
        loopNodeTypes: ["for_statement"],
        stringNodeTypes: ["string_literal"], stringContentTypes: ["string_content"]
    )
}

extension FlowSpec {
    /// Objective-C's flow node types. Its HeaderDoc/Doxygen doc tags aren't checked for completeness.
    static let objc = FlowSpec(
        loopNodeTypes: TreeSitterQualitySpec.objcLoops,
        switchNodeTypes: ["switch_statement"], caseNodeTypes: ["case_statement"], defaultCaseNodeTypes: [],
        tryNodeTypes: ["try_statement"], handlerNodeTypes: ["catch_clause"],
        breakTargetNodeTypes: ["switch_statement"], labeledNodeType: "labeled_statement",
        labelNodeTypes: ["statement_identifier"],
        baseCaseNodeTypes: TreeSitterQualitySpec.objcBranches.union(
            ["conditional_expression", "try_statement", "throw_statement"]
        ),
        selfReceiver: nil, atomicOperandTypes: ["string_literal", "char_literal", "concatenated_string"],
        classDecorationTypes: ["protocol_reference_list", "parameterized_arguments"]
    )
}

extension ShapeSpec {
    /// Objective-C's shape node types: `&&`/`||` chains, blocks as closures, and declared locals.
    static let objc = ShapeSpec(
        rootNodeTypes: ["translation_unit"],
        closureNodeTypes: ["block_literal"],
        logical: LogicalSpec(
            nodeType: "binary_expression", operators: ["&&", "||"], parenthesizedNodeType: "parenthesized_expression",
            negationNodeType: "unary_expression", negationOperandField: "argument"
        ),
        locals: LocalSpec(declarationNodeTypes: objcDeclarators)
    )

    /// The declarators that bind a name, each through its `declarator` field: `int c;`, `int c = 0;`, and the
    /// `*s` of `NSString *s = …`, which nests one level deeper.
    static let objcDeclarators: [String: String?] = [
        "declaration": "declarator", "init_declarator": "declarator", "pointer_declarator": "declarator"
    ]
}

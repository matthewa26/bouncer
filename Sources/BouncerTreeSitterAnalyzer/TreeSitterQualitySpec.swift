import BouncerRules

/// The node types behind the function-shape, cohesion, and single-location rules for one language.
///
/// `TreeSitterQualityCollector` is written once against this description, so supporting another
/// tree-sitter language means filling one of these in with its grammar's node names.
struct TreeSitterQualitySpec: Sendable {
    let complexity: ComplexitySpec
    let parameters: ParameterSpec
    let statements: StatementSpec
    let numbers: NumberSpec
    let markers: [NodeMarker]
    /// How to measure LCOM4, or `nil` for a language without classes.
    let cohesion: CohesionSpec?
    /// Method names that initialize an instance, which skip flag-parameter counting and LCOM4.
    let initializerNames: Set<String>
    /// Node types for the convention rules (`else` after exit, global state, call chains, and so on).
    var conventions = ConventionSpec()
    /// Node types for the size rules and the type-aware naming rules.
    var shapes = ShapeSpec()
    /// Node types for NPath, `if` pyramids, loop jumps, recursion, Halstead, and doc completeness.
    var flow: FlowSpec?
    /// Node types for the design-smell facts: coupling, feature envy, temporary field, and the like.
    var design: DesignSpec?
}

/// A node type whose named field (or, with no field, the node itself) has one of the given texts.
struct FieldMatch: Sendable {
    let nodeType: String
    let field: String?
    let texts: Set<String>
}

/// Node types for the convention rules. Each part left at its default turns its rule off.
struct ConventionSpec: Sendable {
    /// `if` nodes whose `consequence` field ends in a jump while an `alternative` field follows.
    var ifNodeType: String?
    /// Declarations that create mutable globals, keyed by node type; a non-nil value is the keyword
    /// the declaration must start with, such as `let` (to skip `const`).
    var mutableGlobalNodes: [String: String?] = [:]
    /// Parent node types that make a declaration top-level, such as `program`.
    var rootNodeTypes: Set<String> = []
    /// Wrappers between a top-level declaration and the root, such as `export_statement`.
    var rootWrapperNodeTypes: Set<String> = []
    /// Node types that mark mutable global state wherever they appear, such as Python's `global`.
    var globalStatementNodeTypes: Set<String> = []
    /// Calls and member access, for measuring call chains.
    var chain: ChainSpec?
    /// Runtime type checks, such as `x instanceof T` or `isinstance(x, T)`.
    var typeChecks: [FieldMatch] = []
    /// How to recognize tests and their assertions.
    var tests: TestSpec?
    /// Declarations whose names the naming rules check, mapped to the field holding the name.
    var nameFields: [String: String] = [:]
    /// Parameter lists whose bare identifier children are parameter names.
    var parameterListTypes: Set<String> = []
    /// Loops whose declared variables (`for (let i …)`) are exempt from the naming rules.
    var loopNodeTypes: Set<String> = []
    /// String literal node types, the child types holding their text, and children that mean interpolation.
    var stringNodeTypes: Set<String> = []
    var stringContentTypes: Set<String> = []
    var interpolationTypes: Set<String> = []
}

/// Call and member-access node types, for following a chain like `a.b().c()` back through its receivers.
struct ChainSpec: Sendable {
    let callNodeType: String
    let calleeField: String
    let memberNodeType: String
    let objectField: String
    /// The member access's field holding the member's name, such as `property` in `a.property`.
    let propertyField: String
    /// Whether an uppercase member names a type, as in `models.User()`, rather than an exported member (Go).
    var uppercaseIsType = true
}

/// How to recognize a test and whether it asserts anything.
struct TestSpec: Sendable {
    /// Calls whose function argument is a test body, such as `it` and `test`.
    let callbackCallees: Set<String>
    /// A pattern a test function's name matches, such as `^test`.
    let namePattern: String?
    /// A pattern matching an assertion anywhere in a test's text.
    let assertionPattern: String
}

/// What scores cognitive complexity, deepens nesting, and counts as a `return`.
struct ComplexitySpec: Sendable {
    /// Structures that score one plus their nesting level and deepen nesting: `if`, loops, `switch`, `catch`.
    let nestingNodeTypes: Set<String>
    /// Clauses that score one flat: `else`, and Python's `elif`.
    let elseNodeTypes: Set<String>
    /// Parents that make a nested `if` an `else if`, which scores nothing itself and doesn't deepen nesting.
    let elseIfParentTypes: Set<String>
    /// For grammars with no `else` node (Go), the field on an `if` whose presence scores the `else` one.
    let alternativeField: String?
    let ternaryNodeType: String?
    let logicalNodeType: String
    let logicalOperators: Set<String>
    /// Function expressions beyond the language's declared function types, such as Go's `func` literals.
    let closureNodeTypes: Set<String>
    let returnNodeType: String
}

/// How to read a parameter list: which entries are parameters, and which are boolean flags.
struct ParameterSpec: Sendable {
    /// Entries in a parameter list that aren't parameters, such as comments and `*` separators.
    let ignoredNodeTypes: Set<String>
    /// Leading receiver parameters that aren't counted, such as Python's `self` and `cls`.
    let receiverNames: Set<String>
    /// For grammars that group names (Go's `a, b int`), the node type of each name in a group.
    let groupedNameNodeType: String?
    let booleanTypeField: String
    let booleanTypeText: String
    let defaultFields: [String]
    let booleanLiteralNodeTypes: Set<String>
    /// Other spellings of the boolean type, such as C's `bool` beside Objective-C's `BOOL`.
    var booleanTypeAliases: Set<String> = []
    /// For entries with no `booleanTypeField`, the child node holding the type, such as Objective-C's `(BOOL)`.
    var typeChildNodeType: String?
}

/// Blocks, jumps, and `catch` clauses, for the unreachable-code and empty-catch rules.
struct StatementSpec: Sendable {
    let catchNodeType: String?
    /// Statements that don't count as handling an error, such as Python's `pass`.
    let noOpNodeTypes: Set<String>
    let blockNodeTypes: Set<String>
    let jumpNodeTypes: Set<String>
    /// Statements that may follow a jump without being unreachable, such as hoisted functions.
    let hoistedNodeTypes: Set<String>
}

/// Number literals, and which surrounding constructs give a number a name.
struct NumberSpec: Sendable {
    let literalNodeTypes: Set<String>
    let allowed: Set<String>
    let namingParents: Set<String>
    let transparentParents: Set<String>
}

/// A node type that always marks a smell, optionally only when its text matches exactly.
struct NodeMarker: Sendable {
    let nodeType: String
    let text: String?
    let kind: MarkerKind
}

/// The class-member node types LCOM4 needs: methods, fields that hold functions, and `this.x` access.
struct CohesionSpec: Sendable {
    let methodNodeTypes: Set<String>
    /// Field node types mapped to their name field; a field whose value is a function counts as a method.
    let fieldNameFields: [String: String]
    let memberAccessNodeType: String
    let objectField: String
    let propertyField: String
    let receiverText: String
    let staticKeyword: String?
}

extension TreeSitterQualitySpec {
    /// TypeScript's and JavaScript's quality node types; TypeScript's grammar keeps JavaScript's names.
    static let javascript = TreeSitterQualitySpec(
        complexity: ComplexitySpec(
            nestingNodeTypes: [
                "if_statement", "for_statement", "for_in_statement", "while_statement", "do_statement",
                "switch_statement", "catch_clause"
            ],
            elseNodeTypes: ["else_clause"], elseIfParentTypes: ["else_clause"], alternativeField: nil,
            ternaryNodeType: "ternary_expression", logicalNodeType: "binary_expression",
            logicalOperators: ["&&", "||", "??"], closureNodeTypes: [], returnNodeType: "return_statement"
        ),
        parameters: ParameterSpec(
            ignoredNodeTypes: ["comment"], receiverNames: [], groupedNameNodeType: nil,
            booleanTypeField: "type", booleanTypeText: ": boolean", defaultFields: ["value", "right"],
            booleanLiteralNodeTypes: ["true", "false"]
        ),
        statements: StatementSpec(
            catchNodeType: "catch_clause", noOpNodeTypes: [],
            blockNodeTypes: ["statement_block", "switch_case", "switch_default"],
            jumpNodeTypes: ["return_statement", "throw_statement", "break_statement", "continue_statement"],
            hoistedNodeTypes: ["function_declaration", "generator_function_declaration", "comment", "empty_statement"]
        ),
        numbers: NumberSpec(
            literalNodeTypes: ["number"], allowed: ["0", "1", "2"],
            namingParents: [
                "variable_declarator", "pair", "public_field_definition", "field_definition", "enum_assignment",
                "assignment_pattern", "required_parameter", "optional_parameter", "assignment_expression",
                "switch_case", "literal_type"
            ],
            transparentParents: [
                "parenthesized_expression", "unary_expression", "binary_expression", "arguments", "call_expression",
                "new_expression", "array"
            ]
        ),
        markers: [
            NodeMarker(nodeType: "non_null_expression", text: nil, kind: .nonNullAssertion),
            NodeMarker(nodeType: "predefined_type", text: "any", kind: .explicitAny)
        ],
        cohesion: CohesionSpec(
            methodNodeTypes: ["method_definition"],
            fieldNameFields: ["public_field_definition": "name", "field_definition": "property"],
            memberAccessNodeType: "member_expression", objectField: "object", propertyField: "property",
            receiverText: "this", staticKeyword: "static"
        ),
        initializerNames: ["constructor"],
        conventions: javascriptConventions,
        shapes: .javascript,
        flow: .javascript,
        design: .javascript
    )

    private static let javascriptConventions = ConventionSpec(
        ifNodeType: "if_statement",
        mutableGlobalNodes: ["lexical_declaration": "let", "variable_declaration": nil],
        rootNodeTypes: ["program"], rootWrapperNodeTypes: ["export_statement"],
        chain: ChainSpec(
            callNodeType: "call_expression", calleeField: "function", memberNodeType: "member_expression",
            objectField: "object", propertyField: "property"
        ),
        typeChecks: [FieldMatch(nodeType: "binary_expression", field: "operator", texts: ["instanceof"])],
        tests: TestSpec(
            callbackCallees: ["it", "test"], namePattern: nil,
            assertionPattern: #"\b(expect|assert)\w*\s*\(|\.should\b"#
        ),
        nameFields: ["variable_declarator": "name", "required_parameter": "pattern", "optional_parameter": "pattern"],
        parameterListTypes: ["formal_parameters"], loopNodeTypes: ["for_statement", "for_in_statement"],
        stringNodeTypes: ["string", "template_string"], stringContentTypes: ["string_fragment"],
        interpolationTypes: ["template_substitution"]
    )

    /// Python's quality node types. Decorated methods (`@staticmethod`, `@property`, …) are left out of LCOM4.
    static let python = TreeSitterQualitySpec(
        complexity: ComplexitySpec(
            nestingNodeTypes: ["if_statement", "for_statement", "while_statement", "except_clause", "match_statement"],
            elseNodeTypes: ["elif_clause", "else_clause"], elseIfParentTypes: [], alternativeField: nil,
            ternaryNodeType: "conditional_expression", logicalNodeType: "boolean_operator",
            logicalOperators: ["and", "or"], closureNodeTypes: ["lambda"], returnNodeType: "return_statement"
        ),
        parameters: ParameterSpec(
            ignoredNodeTypes: ["comment", "keyword_separator", "positional_separator"], receiverNames: ["self", "cls"],
            groupedNameNodeType: nil, booleanTypeField: "type", booleanTypeText: "bool", defaultFields: ["value"],
            booleanLiteralNodeTypes: ["true", "false"]
        ),
        statements: StatementSpec(
            catchNodeType: "except_clause", noOpNodeTypes: ["pass_statement"], blockNodeTypes: ["block"],
            jumpNodeTypes: ["return_statement", "raise_statement", "break_statement", "continue_statement"],
            hoistedNodeTypes: ["comment"]
        ),
        numbers: NumberSpec(
            literalNodeTypes: ["integer", "float"], allowed: ["0", "1", "2", "0.0", "1.0"],
            namingParents: [
                "assignment", "augmented_assignment", "keyword_argument", "default_parameter",
                "typed_default_parameter", "pair", "case_pattern"
            ],
            transparentParents: [
                "parenthesized_expression", "unary_operator", "binary_operator", "argument_list", "call", "list",
                "tuple"
            ]
        ),
        markers: [],
        cohesion: CohesionSpec(
            methodNodeTypes: ["function_definition"], fieldNameFields: [:],
            memberAccessNodeType: "attribute", objectField: "object", propertyField: "attribute",
            receiverText: "self", staticKeyword: nil
        ),
        initializerNames: ["__init__"],
        conventions: ConventionSpec(
            ifNodeType: "if_statement", globalStatementNodeTypes: ["global_statement"],
            chain: ChainSpec(
                callNodeType: "call", calleeField: "function", memberNodeType: "attribute", objectField: "object",
                propertyField: "attribute"
            ),
            typeChecks: [FieldMatch(nodeType: "call", field: "function", texts: ["isinstance", "type"])],
            tests: TestSpec(
                callbackCallees: [], namePattern: "^test",
                assertionPattern: #"\bassert\b|\.assert\w*\(|pytest\.raises"#
            )
        ),
        shapes: .python,
        flow: .python,
        design: .python
    )

    /// Go's quality node types. Go has no classes, ternaries, or `catch`, so those rules don't apply.
    static let go = TreeSitterQualitySpec(
        complexity: ComplexitySpec(
            nestingNodeTypes: [
                "if_statement", "for_statement", "expression_switch_statement", "type_switch_statement",
                "select_statement"
            ],
            elseNodeTypes: [], elseIfParentTypes: ["if_statement"], alternativeField: "alternative",
            ternaryNodeType: nil, logicalNodeType: "binary_expression", logicalOperators: ["&&", "||"],
            closureNodeTypes: ["func_literal"], returnNodeType: "return_statement"
        ),
        parameters: ParameterSpec(
            ignoredNodeTypes: ["comment"], receiverNames: [], groupedNameNodeType: "identifier",
            booleanTypeField: "type", booleanTypeText: "bool", defaultFields: [], booleanLiteralNodeTypes: []
        ),
        statements: StatementSpec(
            catchNodeType: nil, noOpNodeTypes: [], blockNodeTypes: ["statement_list"],
            jumpNodeTypes: ["return_statement", "break_statement", "continue_statement", "goto_statement"],
            hoistedNodeTypes: ["comment"]
        ),
        numbers: NumberSpec(
            literalNodeTypes: ["int_literal", "float_literal", "imaginary_literal"], allowed: ["0", "1", "2"],
            namingParents: [
                "const_spec", "var_spec", "short_var_declaration", "assignment_statement", "keyed_element",
                "expression_case"
            ],
            transparentParents: [
                "parenthesized_expression", "unary_expression", "binary_expression", "argument_list",
                "call_expression", "expression_list", "literal_element", "literal_value", "composite_literal"
            ]
        ),
        markers: [],
        cohesion: nil,
        initializerNames: [],
        conventions: ConventionSpec(
            ifNodeType: "if_statement", mutableGlobalNodes: ["var_declaration": nil], rootNodeTypes: ["source_file"],
            chain: ChainSpec(
                callNodeType: "call_expression", calleeField: "function", memberNodeType: "selector_expression",
                objectField: "operand", propertyField: "field", uppercaseIsType: false
            ),
            typeChecks: [FieldMatch(nodeType: "type_assertion_expression", field: nil, texts: [])],
            tests: TestSpec(
                callbackCallees: [], namePattern: "^Test[A-Z_]",
                assertionPattern: #"\bt\.(Error|Errorf|Fatal|Fatalf|Fail|FailNow)\(|\b(assert|require)\.\w+\("#
            )
        ),
        shapes: .go,
        flow: .go,
        design: .go
    )
}

import BouncerRules

/// The node types behind NPath, `if` pyramids, loop jumps, recursion, Halstead counts, and the
/// doc-completeness facts for one language.
struct FlowSpec: Sendable {
    /// `if` statements, read through their `condition`, `consequence`, and (repeatable) `alternative` fields.
    var ifNodeType = "if_statement"
    /// The field holding an `if`'s (or `elif`'s) branch, which PHP calls `body`.
    var consequenceField = "consequence"
    /// An `alternative` that is another condition and branch, as Python's `elif`; any other alternative is an `else`.
    var elifNodeType: String?
    let loopNodeTypes: Set<String>
    let switchNodeTypes: Set<String>
    let caseNodeTypes: Set<String>
    let defaultCaseNodeTypes: Set<String>
    let tryNodeTypes: Set<String>
    /// The clauses of a `try` that handle an error; each is an alternative path.
    let handlerNodeTypes: Set<String>
    /// Statements that are an unlabeled `break`'s target besides loops, such as `switch`.
    let breakTargetNodeTypes: Set<String>
    /// The labeled-statement wrapper and the node types of a label inside a jump.
    var labeledNodeType: String?
    var labelNodeTypes: Set<String> = []
    /// The jumps that leave or restart a loop, and where a loop keeps its label.
    var jumps = LoopJumpSpec()
    /// Wrappers between a `switch` and its cases, such as `switch_body` or Rust's `match_block`.
    var caseContainerNodeTypes: Set<String> = ["switch_body", "block"]
    /// Nodes that can stop a recursion besides logical operators: branches, loops, throws, optional chains.
    let baseCaseNodeTypes: Set<String>
    /// The receiver a method calls itself through, such as `this`; `nil` skips methods' recursion check.
    let selfReceiver: String?
    /// Literals counted as one Halstead operand without looking inside, such as strings.
    let atomicOperandTypes: Set<String>
    /// Children of a class declaration that make a near-empty class deliberate: a superclass, decorator,
    /// or type parameters.
    var classDecorationTypes: Set<String> = []
    /// How to read parameters and doc comments, or `nil` to skip the doc-completeness rules.
    var documentation: DocumentationSpec?
}

/// The jumps that leave or restart a loop, and a label written on the loop itself.
struct LoopJumpSpec: Sendable {
    var breakNodeTypes: Set<String> = ["break_statement"]
    var continueNodeTypes: Set<String> = ["continue_statement"]
    /// A label written as the loop's own child rather than a wrapper, as in Rust's `'outer: loop { … }`.
    var loopLabelNodeType: String?
}

/// The doc convention and the parameter and statement node types the doc-completeness facts read.
struct DocumentationSpec: Sendable {
    let style: DocStyle
    /// Parameter-list entries mapped to the field holding their name: `""` means the entry is the name, and
    /// `"*"` means its first identifier child is.
    let namedParameters: [String: String]
    /// Parameter-list entries whose identifier child is a variadic name, such as Python's `*args`.
    let variadicParameters: Set<String>
    let throwNodeType: String
    /// Return types (after `:` or `->`) that mean no value.
    let voidReturnTypes: Set<String>
    /// Decorators that make a method a property, whose value a docstring describes without a `Returns:`.
    let propertyDecorators: [String]
}

extension FlowSpec {
    /// TypeScript's and JavaScript's flow node types.
    static let javascript = FlowSpec(
        loopNodeTypes: ["for_statement", "for_in_statement", "while_statement", "do_statement"],
        switchNodeTypes: ["switch_statement"], caseNodeTypes: ["switch_case"], defaultCaseNodeTypes: ["switch_default"],
        tryNodeTypes: ["try_statement"], handlerNodeTypes: ["catch_clause"],
        breakTargetNodeTypes: ["switch_statement"], labeledNodeType: "labeled_statement",
        labelNodeTypes: ["statement_identifier"],
        baseCaseNodeTypes: [
            "if_statement", "for_statement", "for_in_statement", "while_statement", "do_statement", "switch_statement",
            "ternary_expression", "try_statement", "throw_statement", "optional_chain"
        ],
        selfReceiver: "this", atomicOperandTypes: ["string", "template_string", "regex"],
        classDecorationTypes: ["class_heritage", "decorator", "type_parameters"],
        documentation: DocumentationSpec(
            style: .jsdoc,
            namedParameters: [
                "identifier": "", "required_parameter": "pattern", "optional_parameter": "pattern",
                "assignment_pattern": "left", "rest_pattern": "*"
            ],
            variadicParameters: [],
            throwNodeType: "throw_statement", voidReturnTypes: ["void", "Promise<void>", "never", "undefined"],
            propertyDecorators: []
        )
    )

    /// Python's flow node types.
    static let python = FlowSpec(
        elifNodeType: "elif_clause", loopNodeTypes: ["for_statement", "while_statement"],
        switchNodeTypes: ["match_statement"], caseNodeTypes: ["case_clause"], defaultCaseNodeTypes: [],
        tryNodeTypes: ["try_statement"], handlerNodeTypes: ["except_clause"], breakTargetNodeTypes: [],
        baseCaseNodeTypes: [
            "if_statement", "for_statement", "while_statement", "match_statement", "conditional_expression",
            "try_statement", "raise_statement", "list_comprehension", "set_comprehension", "dictionary_comprehension",
            "generator_expression"
        ],
        selfReceiver: "self", atomicOperandTypes: ["string", "concatenated_string"],
        classDecorationTypes: ["type_parameter"],
        documentation: DocumentationSpec(
            style: .python,
            namedParameters: [
                "identifier": "", "typed_parameter": "*", "default_parameter": "name", "typed_default_parameter": "name"
            ],
            variadicParameters: ["list_splat_pattern", "dictionary_splat_pattern"],
            throwNodeType: "raise_statement", voidReturnTypes: ["None"],
            propertyDecorators: ["property", "cached_property", "setter", "getter", "deleter"]
        )
    )

    /// Go's flow node types. Go has no doc-comment parameter convention, so the doc rules skip it.
    static let go = FlowSpec(
        loopNodeTypes: ["for_statement"],
        switchNodeTypes: ["expression_switch_statement", "type_switch_statement", "select_statement"],
        caseNodeTypes: ["expression_case", "type_case", "communication_case"], defaultCaseNodeTypes: ["default_case"],
        tryNodeTypes: [], handlerNodeTypes: [],
        breakTargetNodeTypes: ["expression_switch_statement", "type_switch_statement", "select_statement"],
        labeledNodeType: "labeled_statement", labelNodeTypes: ["label_name"],
        baseCaseNodeTypes: [
            "if_statement", "for_statement", "expression_switch_statement", "type_switch_statement", "select_statement",
            "go_statement", "defer_statement"
        ],
        selfReceiver: nil,
        atomicOperandTypes: ["interpreted_string_literal", "raw_string_literal", "rune_literal"]
    )
}

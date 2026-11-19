/// The node types behind the size rules (`large-type`, `long-closure`, `long-boolean-expression`,
/// `too-many-generic-parameters`, `too-many-locals`) and the type-aware naming rules.
///
/// Each part left at its default turns its rules off for the language.
struct ShapeSpec: Sendable {
    /// Type declarations, mapped to the field holding their name.
    var typeNodeTypes: [String: String] = [:]
    /// For grammars whose type declaration wraps any type (Go's `type_spec`), the `type` field's node
    /// types that make it a measured type, such as `struct_type`.
    var typeBodyNodeTypes: Set<String>?
    /// The file's root node types, such as `program`.
    var rootNodeTypes: Set<String> = []
    /// Wrappers that export what they hold, such as `export_statement`.
    var exportWrapperNodeTypes: Set<String> = []
    /// Wrappers that sit between a top-level declaration and the root without changing it, such as decorators.
    var transparentWrapperNodeTypes: Set<String> = []
    /// Exported non-type declarations that mean a file isn't only about its one type.
    var exportedOtherNodeTypes: Set<String> = []
    var closureNodeTypes: Set<String> = []
    /// Calls whose closure argument is a test-suite block (`describe`, `it`) or a module wrapper (`define`).
    var suiteCallees: Set<String> = []
    /// Whether an immediately invoked function, `(function () { … })()`, is a module wrapper to skip.
    var skipsImmediatelyInvoked = false
    var logical: LogicalSpec?
    var generics: GenericSpec?
    var names = NameSpec()
    var locals = LocalSpec()
}

/// How `&&`/`||` chains are built, for counting their operands.
struct LogicalSpec: Sendable {
    let nodeType: String
    let operators: Set<String>
    let parenthesizedNodeType: String
    /// A negation node, such as `!x` or `not x`, and the field holding its operand.
    let negationNodeType: String
    let negationOperandField: String
}

/// A generic parameter list and the nodes that each declare one or more parameters.
struct GenericSpec: Sendable {
    let listNodeType: String
    let parameterNodeType: String
    /// For grammars that group names (Go's `[K, V any]`), the node type of each name in a group.
    let groupedNameNodeType: String?
}

/// A declaration that introduces variable, property, or parameter names.
struct NameSource: Sendable {
    let nodeType: String
    /// The field holding the name, or `nil` when the names are the node's direct name-typed children.
    let nameField: String?
    var typeField: String?
    var valueField: String?
    var isParameter = false
}

/// The declarations that name things, and how to read a type off an initial value.
struct NameSpec: Sendable {
    var sources: [NameSource] = []
    var nameNodeTypes: Set<String> = ["identifier"]
    /// Lists that hold several names or values, such as Go's `a, b := 1, 2`.
    var listNodeTypes: Set<String> = []
    /// Names that are a method's receiver, not a parameter, such as Python's `self`.
    var receiverNames: Set<String> = []
    /// Literal node types mapped to the type they imply, such as `true` to `boolean`.
    var literalTypes: [String: String] = [:]
    /// Constructor-like calls mapped to the field naming the type they build, such as `new_expression`.
    var constructorFields: [String: String] = [:]
    /// Calls whose first argument is the type they build, such as Go's `make`.
    var allocatorCallees: Set<String> = []
    /// Whether a later assignment to a name redeclares nothing, so only its first one counts, as in Python.
    var keepsFirstAssignmentOnly = false
}

/// The declarations that introduce local variables, for `too-many-locals`.
struct LocalSpec: Sendable {
    /// Declaration node types mapped to the field holding the declared name or pattern, or `nil`
    /// when the names are the node's direct identifier children.
    var declarationNodeTypes: [String: String?] = [:]
    /// Patterns whose identifier children each declare a name, such as Python's `a, b = …`.
    var listNodeTypes: Set<String> = []
    /// Whether any other pattern, such as a destructuring `{ a, b }`, counts as one declaration.
    var countsOtherPatternsAsOne = false
}

extension ShapeSpec {
    /// TypeScript's and JavaScript's shape node types.
    static let javascript = ShapeSpec(
        typeNodeTypes: [
            "class_declaration": "name", "abstract_class_declaration": "name", "interface_declaration": "name",
            "enum_declaration": "name"
        ],
        rootNodeTypes: ["program"], exportWrapperNodeTypes: ["export_statement"],
        exportedOtherNodeTypes: [
            "function_declaration", "generator_function_declaration", "lexical_declaration", "variable_declaration"
        ],
        closureNodeTypes: ["arrow_function", "function_expression"],
        suiteCallees: [
            "describe", "it", "test", "context", "suite", "beforeEach", "afterEach", "beforeAll", "afterAll",
            "before", "after", "define"
        ],
        skipsImmediatelyInvoked: true,
        logical: LogicalSpec(
            nodeType: "binary_expression", operators: ["&&", "||"], parenthesizedNodeType: "parenthesized_expression",
            negationNodeType: "unary_expression", negationOperandField: "argument"
        ),
        generics: GenericSpec(
            listNodeType: "type_parameters", parameterNodeType: "type_parameter", groupedNameNodeType: nil
        ),
        names: javascriptNames,
        locals: LocalSpec(declarationNodeTypes: ["variable_declarator": "name"], countsOtherPatternsAsOne: true)
    )

    private static let javascriptNames = NameSpec(
        sources: [
            NameSource(nodeType: "variable_declarator", nameField: "name", typeField: "type", valueField: "value"),
            NameSource(nodeType: "public_field_definition", nameField: "name", typeField: "type", valueField: "value"),
            NameSource(nodeType: "field_definition", nameField: "property", valueField: "value"),
            NameSource(
                nodeType: "required_parameter", nameField: "pattern", typeField: "type", valueField: "value",
                isParameter: true
            ),
            NameSource(
                nodeType: "optional_parameter", nameField: "pattern", typeField: "type", valueField: "value",
                isParameter: true
            ),
            NameSource(nodeType: "formal_parameters", nameField: nil, isParameter: true),
            NameSource(nodeType: "assignment_pattern", nameField: "left", valueField: "right", isParameter: true)
        ],
        nameNodeTypes: ["identifier", "property_identifier"],
        literalTypes: [
            "string": "string", "template_string": "string", "number": "number", "true": "boolean",
            "false": "boolean", "array": "Array"
        ],
        constructorFields: ["new_expression": "constructor"]
    )

    /// Python's shape node types. Python's generics are `TypeVar`s rather than declared parameter
    /// lists, so `too-many-generic-parameters` doesn't apply.
    static let python = ShapeSpec(
        typeNodeTypes: ["class_definition": "name"],
        rootNodeTypes: ["module"], transparentWrapperNodeTypes: ["decorated_definition"],
        closureNodeTypes: ["lambda"],
        logical: LogicalSpec(
            nodeType: "boolean_operator", operators: ["and", "or"], parenthesizedNodeType: "parenthesized_expression",
            negationNodeType: "not_operator", negationOperandField: "argument"
        ),
        names: pythonNames,
        locals: LocalSpec(
            declarationNodeTypes: ["assignment": "left"], listNodeTypes: ["pattern_list", "tuple_pattern"]
        )
    )

    private static let pythonNames = NameSpec(
        sources: [
            NameSource(nodeType: "assignment", nameField: "left", typeField: "type", valueField: "right"),
            NameSource(nodeType: "parameters", nameField: nil, isParameter: true),
            NameSource(nodeType: "typed_parameter", nameField: nil, typeField: "type", isParameter: true),
            NameSource(nodeType: "default_parameter", nameField: "name", valueField: "value", isParameter: true),
            NameSource(
                nodeType: "typed_default_parameter", nameField: "name", typeField: "type", valueField: "value",
                isParameter: true
            )
        ],
        listNodeTypes: ["pattern_list", "tuple_pattern", "expression_list"],
        receiverNames: ["self", "cls"],
        literalTypes: [
            "string": "str", "integer": "int", "float": "float", "true": "bool", "false": "bool", "list": "list",
            "list_comprehension": "list", "dictionary": "dict", "dictionary_comprehension": "dict", "set": "set",
            "set_comprehension": "set"
        ],
        constructorFields: ["call": "function"],
        keepsFirstAssignmentOnly: true
    )

    /// Go's shape node types. Only struct and interface type declarations count as types.
    static let go = ShapeSpec(
        typeNodeTypes: ["type_spec": "name"], typeBodyNodeTypes: ["struct_type", "interface_type"],
        rootNodeTypes: ["source_file"],
        closureNodeTypes: ["func_literal"], suiteCallees: ["Run"],
        logical: LogicalSpec(
            nodeType: "binary_expression", operators: ["&&", "||"], parenthesizedNodeType: "parenthesized_expression",
            negationNodeType: "unary_expression", negationOperandField: "operand"
        ),
        generics: GenericSpec(
            listNodeType: "type_parameter_list", parameterNodeType: "type_parameter_declaration",
            groupedNameNodeType: "identifier"
        ),
        names: goNames,
        locals: LocalSpec(
            declarationNodeTypes: ["short_var_declaration": "left", "var_spec": nil], listNodeTypes: ["expression_list"]
        )
    )

    private static let goNames = NameSpec(
        sources: [
            NameSource(nodeType: "var_spec", nameField: nil, typeField: "type", valueField: "value"),
            NameSource(nodeType: "short_var_declaration", nameField: "left", valueField: "right"),
            NameSource(nodeType: "parameter_declaration", nameField: nil, typeField: "type", isParameter: true),
            NameSource(nodeType: "field_declaration", nameField: nil, typeField: "type")
        ],
        nameNodeTypes: ["identifier", "field_identifier"],
        listNodeTypes: ["expression_list"],
        literalTypes: [
            "interpreted_string_literal": "string", "raw_string_literal": "string", "int_literal": "int",
            "float_literal": "float64", "true": "bool", "false": "bool"
        ],
        constructorFields: ["composite_literal": "type", "call_expression": "function"],
        allocatorCallees: ["make", "new"]
    )
}

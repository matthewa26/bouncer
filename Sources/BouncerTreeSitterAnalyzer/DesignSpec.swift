/// The node types behind the design-smell facts for one language: assignments, `if` conditions, type
/// references, locals, and typed parameters, for CBO, RFC, ATFD, feature envy, temporary field,
/// command–query separation, tell-don't-ask, and primitive obsession.
struct DesignSpec: Sendable {
    /// Plain assignments (`a = b`), whose `left` and `right` fields hold the two sides.
    let assignmentNodeTypes: Set<String>
    /// Assignments that read the old value: compound assignments (`left` field) and `++`/`--` (`argument`).
    let compoundAssignmentNodeTypes: Set<String>
    /// The `if` statement, with its `condition` and `consequence` fields.
    let ifNodeType: String
    /// Nodes whose text is a type name, such as TypeScript's `type_identifier`.
    var typeNameNodeTypes: Set<String> = []
    /// Nodes whose identifiers all name types, such as Python's `type` annotations and TS/JS heritage clauses.
    let typeContainerNodeTypes: Set<String>
    /// The class node's field listing its superclasses, whose identifiers name types (Python).
    var superclassField: String?
    /// Constructor calls mapped to the field holding the constructed type, such as `new_expression`'s `constructor`.
    let constructorFields: [String: String]
    /// Generic parameter declarations, whose `name` field isn't a coupled type.
    var genericParameterNodeType: String?
    /// Declarations that bind locals, mapped to the field holding the bound name or pattern.
    let localBindings: [String: String]
    /// Parameter entries that a caller may leave out: defaulted, optional, or variadic.
    let optionalParameterNodeTypes: Set<String>
    /// Returned expressions that don't give the caller a value, such as `this`, `self`, and `None`.
    let valuelessReturns: Set<String>
    /// Declared return types that give the caller no value, compared without spaces or a leading `:`.
    let voidReturnTypes: Set<String>
    /// The keyword or node marking a field read-only, a method an override, and a field private.
    var readonlyKeyword: String?
    var overrideNodeType: String?
    var privateModifierText: String?
    /// Decorators that make a Python method belong to the class rather than an instance.
    var typeLevelDecorators: Set<String> = []
    /// Function expressions whose parameters count as their enclosing function's locals, such as arrow functions.
    var anonymousFunctionNodeTypes: Set<String> = []
}

extension DesignSpec {
    /// TypeScript's and JavaScript's design node types.
    static let javascript = DesignSpec(
        assignmentNodeTypes: ["assignment_expression"],
        compoundAssignmentNodeTypes: ["augmented_assignment_expression", "update_expression"],
        ifNodeType: "if_statement", typeNameNodeTypes: ["type_identifier"],
        typeContainerNodeTypes: ["extends_clause", "implements_clause"],
        constructorFields: ["new_expression": "constructor"], genericParameterNodeType: "type_parameter",
        localBindings: ["variable_declarator": "name", "for_in_statement": "left", "catch_clause": "parameter"],
        optionalParameterNodeTypes: ["optional_parameter", "rest_pattern", "assignment_pattern"],
        valuelessReturns: ["this", "undefined"],
        voidReturnTypes: ["void", "Promise<void>", "this", "never", "undefined"],
        readonlyKeyword: "readonly", overrideNodeType: "override_modifier", privateModifierText: "private",
        anonymousFunctionNodeTypes: ["arrow_function", "function_expression"]
    )

    /// Python's design node types.
    static let python = DesignSpec(
        assignmentNodeTypes: ["assignment"], compoundAssignmentNodeTypes: ["augmented_assignment"],
        ifNodeType: "if_statement", typeContainerNodeTypes: ["type"], superclassField: "superclasses",
        constructorFields: ["call": "function"],
        localBindings: [
            "assignment": "left", "for_statement": "left", "for_in_clause": "left", "as_pattern": "alias"
        ],
        optionalParameterNodeTypes: [
            "default_parameter", "typed_default_parameter", "list_splat_pattern", "dictionary_splat_pattern"
        ],
        valuelessReturns: ["self", "None", "cls"], voidReturnTypes: ["None", "NoReturn"],
        typeLevelDecorators: ["staticmethod", "classmethod"], anonymousFunctionNodeTypes: ["lambda"]
    )

    /// Go's design node types, for `tell-dont-ask` and `primitive-obsession`; Go has no classes.
    static let go = DesignSpec(
        assignmentNodeTypes: ["assignment_statement"], compoundAssignmentNodeTypes: ["inc_statement", "dec_statement"],
        ifNodeType: "if_statement", typeContainerNodeTypes: [], constructorFields: [:],
        localBindings: ["short_var_declaration": "left", "var_spec": "name", "range_clause": "left"],
        optionalParameterNodeTypes: ["variadic_parameter_declaration"], valuelessReturns: [], voidReturnTypes: [],
        anonymousFunctionNodeTypes: ["func_literal"]
    )
}

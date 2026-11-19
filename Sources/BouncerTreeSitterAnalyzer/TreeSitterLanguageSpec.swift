import SwiftTreeSitter
import CTreeSitterPython
import TreeSitterGo
import CTreeSitterTypeScript
import CTreeSitterTSX
import CTreeSitterJavaScript
import BouncerCore
import BouncerRules

/// How a language marks a declaration as documented.
enum DocumentationStyle: Sendable {
    /// A string literal as the first statement in the body, as in Python.
    case docstring
    /// A comment directly above with no blank line gap, as in Go.
    case precedingComment
    /// A `/** */` comment directly above the declaration or its enclosing wrapper, as in TypeScript.
    case jsdoc
}

/// How a language's naming convention signals a declaration's access level.
enum VisibilityConvention: Sendable {
    /// No leading underscore is public; one leading underscore is internal; two is private, as in Python.
    case leadingUnderscore
    /// An initial uppercase letter is public (exported); anything else is internal, as in Go.
    case leadingCase
    /// An `export` wrapper or public class member is public; `private`/`#name` is private, as in TypeScript.
    case exportKeyword
}

/// A call expression that loads a module, such as CommonJS `require("x")`.
struct ImportCall: Sendable {
    let nodeType: String
    let functionNames: Set<String>
}

/// The tree-sitter node types and conventions one language's analyzer needs.
///
/// This is the tree-sitter analog of `LanguageProfile`: adding a language
/// here, with its grammar's real node type names, is what it takes to give
/// that language exact-AST rules instead of heuristic ones.
public struct TreeSitterLanguageSpec: Sendable {
    var language: SwiftTreeSitter.Language
    var coreLanguage: BouncerCore.Language
    let functionNodeTypes: Set<String>
    let classNodeTypes: Set<String>
    let importNodeTypes: Set<String>
    let decisionNodeTypes: Set<String>
    let logicalOperatorNodeType: String?
    let switchNodeTypes: Set<String>
    let switchBranchNodeTypes: Set<String>
    let functionNamePattern: String
    let typeNamePattern: String?
    let documentationStyle: DocumentationStyle
    let visibilityConvention: VisibilityConvention
    /// Alternate grammars keyed by lowercased file extension, such as TSX for `.tsx`.
    var grammarOverrides: [String: SwiftTreeSitter.Language] = [:]
    /// A module-loading call counted as an import, alongside `importNodeTypes`.
    var importCall: ImportCall?
    /// Nodes that wrap a declaration, walked outward to find its doc comment and `export`.
    var declarationWrapperNodeTypes: Set<String> = []
    /// Parent node types that name an otherwise anonymous function, mapped to the naming field.
    var nameSourceParents: [String: String] = [:]
    /// The node types behind the function metrics and marker rules, or `nil` to skip them.
    var quality: TreeSitterQualitySpec?
    /// Reads imports and exports for the project pass, or `nil` for none.
    var moduleFacts: ModuleFactsExtractor?

    /// Picks the grammar for a file, honoring any per-extension override.
    ///
    /// - Parameter fileExtension: The file's extension.
    /// - Returns: The grammar to parse the file with.
    func grammar(forExtension fileExtension: String) -> SwiftTreeSitter.Language {
        grammarOverrides[fileExtension.lowercased()] ?? language
    }
}

extension TreeSitterLanguageSpec {
    /// The Python grammar's node types and conventions.
    public static let python = TreeSitterLanguageSpec(
        language: SwiftTreeSitter.Language(language: tree_sitter_python()),
        coreLanguage: .python,
        functionNodeTypes: ["function_definition"],
        classNodeTypes: ["class_definition"],
        importNodeTypes: ["import_statement", "import_from_statement"],
        decisionNodeTypes: [
            "if_statement", "elif_clause", "for_statement", "while_statement",
            "except_clause", "boolean_operator", "case_clause"
        ],
        logicalOperatorNodeType: nil,
        switchNodeTypes: ["match_statement"],
        switchBranchNodeTypes: ["case_clause"],
        functionNamePattern: "^[a-z_][a-z0-9_]*$",
        typeNamePattern: "^[A-Z][A-Za-z0-9_]*$",
        documentationStyle: .docstring,
        visibilityConvention: .leadingUnderscore,
        quality: .python,
        moduleFacts: PythonModuleFacts()
    )

    /// The Go grammar's node types and conventions.
    public static let go = TreeSitterLanguageSpec(
        language: SwiftTreeSitter.Language(language: tree_sitter_go()),
        coreLanguage: .go,
        functionNodeTypes: ["function_declaration", "method_declaration"],
        classNodeTypes: [],
        importNodeTypes: ["import_spec"],
        decisionNodeTypes: ["if_statement", "for_statement", "expression_case", "type_case"],
        logicalOperatorNodeType: "binary_expression",
        switchNodeTypes: ["expression_switch_statement", "type_switch_statement"],
        switchBranchNodeTypes: ["expression_case", "type_case"],
        functionNamePattern: "^[A-Za-z][A-Za-z0-9]*$",
        typeNamePattern: nil,
        documentationStyle: .precedingComment,
        visibilityConvention: .leadingCase,
        quality: .go,
        moduleFacts: GoModuleFacts()
    )

    /// The JavaScript grammar's node types and conventions; the grammar parses JSX natively.
    public static let javascript = TreeSitterLanguageSpec(
        language: SwiftTreeSitter.Language(language: tree_sitter_javascript()), coreLanguage: .javascript,
        functionNodeTypes: javascriptFunctionNodeTypes, classNodeTypes: javascriptClassNodeTypes,
        importNodeTypes: ["import_statement"], decisionNodeTypes: javascriptDecisionNodeTypes,
        logicalOperatorNodeType: "binary_expression", switchNodeTypes: ["switch_statement"],
        switchBranchNodeTypes: ["switch_case"], functionNamePattern: "^[_$]*[A-Za-z][A-Za-z0-9$]*$",
        typeNamePattern: "^[A-Z][A-Za-z0-9]*$", documentationStyle: .jsdoc, visibilityConvention: .exportKeyword,
        importCall: ImportCall(nodeType: "call_expression", functionNames: ["require"]),
        declarationWrapperNodeTypes: javascriptWrapperNodeTypes, nameSourceParents: javascriptNameSourceParents,
        quality: .javascript,
        moduleFacts: JavaScriptModuleFacts()
    )

    /// The TypeScript grammar's node types and conventions, with TSX for `.tsx` files.
    ///
    /// TypeScript's grammar extends JavaScript's and keeps its node names, so this is the
    /// JavaScript spec pointed at a different grammar.
    public static let typescript: TreeSitterLanguageSpec = {
        var spec = javascript
        spec.language = SwiftTreeSitter.Language(language: tree_sitter_typescript())
        spec.coreLanguage = .typescript
        spec.grammarOverrides = ["tsx": SwiftTreeSitter.Language(language: tree_sitter_tsx())]
        return spec
    }()

    private static let javascriptClassNodeTypes: Set<String> = [
        "class_declaration", "abstract_class_declaration", "class"
    ]

    private static let javascriptFunctionNodeTypes: Set<String> = [
        "function_declaration", "generator_function_declaration", "function_expression",
        "arrow_function", "method_definition"
    ]

    private static let javascriptDecisionNodeTypes: Set<String> = [
        "if_statement", "for_statement", "for_in_statement", "while_statement", "do_statement",
        "switch_case", "catch_clause", "ternary_expression"
    ]

    private static let javascriptWrapperNodeTypes: Set<String> = [
        "variable_declarator", "lexical_declaration", "variable_declaration", "export_statement",
        "public_field_definition", "field_definition", "pair"
    ]

    private static let javascriptNameSourceParents: [String: String] = [
        "variable_declarator": "name", "public_field_definition": "name", "field_definition": "property",
        "pair": "key", "assignment_expression": "left"
    ]
}

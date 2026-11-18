import SwiftTreeSitter
import CTreeSitterPython
import TreeSitterGo
import BouncerCore

/// How a language marks a declaration as documented.
enum DocumentationStyle: Sendable {
    /// A string literal as the first statement in the body, as in Python.
    case docstring
    /// A comment directly above with no blank line gap, as in Go.
    case precedingComment
}

/// How a language's naming convention signals a declaration's access level.
enum VisibilityConvention: Sendable {
    /// No leading underscore is public; one leading underscore is internal; two is private, as in Python.
    case leadingUnderscore
    /// An initial uppercase letter is public (exported); anything else is internal, as in Go.
    case leadingCase
}

/// The tree-sitter node types and conventions one language's analyzer needs.
///
/// This is the tree-sitter analog of `LanguageProfile`: adding a language
/// here, with its grammar's real node type names, is what it takes to give
/// that language exact-AST rules instead of heuristic ones.
public struct TreeSitterLanguageSpec: Sendable {
    let language: SwiftTreeSitter.Language
    let coreLanguage: BouncerCore.Language
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
        visibilityConvention: .leadingUnderscore
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
        visibilityConvention: .leadingCase
    )
}

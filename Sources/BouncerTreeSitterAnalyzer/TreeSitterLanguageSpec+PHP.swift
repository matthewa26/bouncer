import SwiftTreeSitter
import CTreeSitterPHP

/// PHP's grammar node types, for `.php` and `.phtml` files.
///
/// The grammar is upstream's `php` one, which parses PHP mixed with HTML: the markup outside `<?php … ?>` is a
/// `text` node, or a `text_interpolation` (`?>…<?php`) between statements, so a template parses cleanly and holds
/// no function unless it declares one. Functions are `function_definition`s and `method_declaration`s (an
/// abstract or interface method has no body and isn't measured), plus closures (`anonymous_function`) and arrow
/// functions (`arrow_function`), measured as nested functions that are anonymous, so a Pest test's callback is a
/// test of its own. Types are classes, interfaces, traits, and enums. Branches are `if_statement` (with its
/// `else_if_clause`s and an `else_clause`), the loops, `switch_statement`'s `case_statement`s,
/// `match_expression`'s `match_conditional_expression`s, `catch_clause`, and `conditional_expression` (`?:`
/// included); `&&`, `||`, `and`, and `or` are `binary_expression`s.
extension TreeSitterLanguageSpec {
    /// The PHP grammar's node types and conventions.
    public static let php = TreeSitterLanguageSpec(
        language: SwiftTreeSitter.Language(language: tree_sitter_php()),
        coreLanguage: .php,
        functionNodeTypes: PHPNode.functions,
        classNodeTypes: phpTypeNodeTypes,
        importNodeTypes: phpImportNodeTypes,
        decisionNodeTypes: PHPNode.loops.union(PHPNode.decisions),
        logicalOperatorNodeType: PHPNode.binaryExpression,
        switchNodeTypes: PHPNode.switches,
        switchBranchNodeTypes: PHPNode.cases,
        // camelCase, with a magic method's `__` (`__construct`) or a snake_case test (`test_it_works`) allowed.
        functionNamePattern: "^((__)?[a-z][A-Za-z0-9]*|test_[a-z0-9_]+)$",
        typeNamePattern: "^[A-Z][A-Za-z0-9]*$",
        documentationStyle: .jsdoc,
        visibilityConvention: .accessModifier,
        quality: .php,
        moduleFacts: PHPModuleFacts(),
        nonMemberNodeTypes: [PHPNode.comment],
        smells: PHPSmells()
    )

    /// Classes, interfaces, traits, and enums.
    static let phpTypeNodeTypes: Set<String> = [
        "class_declaration", "interface_declaration", "trait_declaration", "enum_declaration"
    ]

    /// `use` declarations (one per statement, grouped or not) and the `require` and `include` family.
    private static let phpImportNodeTypes: Set<String> = [
        "namespace_use_declaration", "require_expression", "require_once_expression", "include_expression",
        "include_once_expression"
    ]
}

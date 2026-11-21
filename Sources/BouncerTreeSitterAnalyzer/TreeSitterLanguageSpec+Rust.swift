import SwiftTreeSitter
import CTreeSitterRust

/// Rust's grammar node types, for `.rs` files.
///
/// Functions are `function_item`s, free or inside an `impl` or `trait` block (a trait's default methods have
/// bodies; its bare signatures are `function_signature_item`s and aren't measured). Closures are
/// `closure_expression`s, measured as nested functions. Types are `struct_item`, `enum_item`, `union_item`, and
/// `trait_item`; an `impl_item` isn't a type of its own but adds its members to the same-named type when the file
/// declares it. Everything in a body is an expression: `if_expression`, `match_expression` (whose `match_arm`s are
/// its branches), `loop_expression`, `while_expression`, `for_expression`, and `return_expression`, with a
/// statement-position expression wrapped in `expression_statement`.
///
/// The `?` operator (`try_expression`) isn't a decision point: like a Swift `try`, it propagates an error without
/// adding a path the reader has to follow, and counting it would make idiomatic error handling look complex.
extension TreeSitterLanguageSpec {
    /// The Rust grammar's node types and conventions.
    public static let rust = TreeSitterLanguageSpec(
        language: SwiftTreeSitter.Language(language: tree_sitter_rust()),
        coreLanguage: .rust,
        functionNodeTypes: ["function_item"],
        classNodeTypes: rustTypeNodeTypes,
        importNodeTypes: ["use_declaration", "extern_crate_declaration"],
        decisionNodeTypes: RustNode.conditionalLoops.union([RustNode.ifExpression, "match_arm"]),
        logicalOperatorNodeType: "binary_expression",
        switchNodeTypes: [RustNode.matchExpression],
        switchBranchNodeTypes: ["match_arm"],
        // snake_case, with a raw identifier's `r#` prefix allowed (`r#type`).
        functionNamePattern: "^(r#)?_*[a-z][a-z0-9_]*$",
        typeNamePattern: "^(r#)?_?[A-Z][A-Za-z0-9]*$",
        documentationStyle: .rustDoc,
        visibilityConvention: .visibilityModifier,
        quality: .rust,
        moduleFacts: RustModuleFacts(),
        typeExtensionNodeTypes: ["impl_item": "type"],
        nonMemberNodeTypes: RustSyntax.preambleNodeTypes,
        smells: RustSmells()
    )

    /// Structs, enums, unions, and traits.
    static let rustTypeNodeTypes: Set<String> = ["struct_item", "enum_item", "union_item", "trait_item"]
}

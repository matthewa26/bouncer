import SwiftTreeSitter
import CTreeSitterObjC

/// Objective-C's grammar node types, for `.m`, `.mm`, and Objective-C `.h` files.
///
/// The grammar extends C's, so C functions, statements, and expressions keep C's node names, and
/// Objective-C adds `class_interface`, `class_implementation`, `protocol_declaration`, `method_definition`,
/// `block_literal`, `message_expression`, `try_statement`/`catch_clause`, and `@import`'s `module_import`.
extension TreeSitterLanguageSpec {
    /// The Objective-C grammar's node types and conventions; Objective-C++ (`.mm`) shares it.
    public static let objc = TreeSitterLanguageSpec(
        language: SwiftTreeSitter.Language(language: tree_sitter_objc()),
        coreLanguage: .objc,
        functionNodeTypes: ["function_definition", "method_definition"],
        classNodeTypes: objcTypeNodeTypes,
        importNodeTypes: ["preproc_include", "module_import"],
        decisionNodeTypes: TreeSitterQualitySpec.objcLoops.union(
            ["if_statement", "case_statement", "catch_clause", "conditional_expression"]
        ),
        logicalOperatorNodeType: "binary_expression",
        switchNodeTypes: ["switch_statement"],
        switchBranchNodeTypes: ["case_statement"],
        // Selectors may start with an acronym (`URLWithString:`) or a lowercase category prefix (`af_setImage:`).
        functionNamePattern: #"^(_?(?:[a-z][a-z0-9]*_)?(?:[a-z]|[A-Z]{2,})[A-Za-z0-9]*(:[A-Za-z0-9]*)*:"#
            + #"|_?[A-Za-z][A-Za-z0-9_]*)$"#,
        typeNamePattern: #"^_?[A-Z][A-Za-z0-9_]*(\([A-Za-z0-9_]*\))?$"#,
        documentationStyle: .cDocComment,
        visibilityConvention: .fileScope,
        declarationWrapperNodeTypes: ["implementation_definition"],
        quality: .objc,
        moduleFacts: ObjCModuleFacts(),
        cDeclarations: objcDeclarations
    )

    /// `@interface` (including categories and class extensions), `@implementation`, and `@protocol`.
    static let objcTypeNodeTypes: Set<String> = ["class_interface", "class_implementation", "protocol_declaration"]

    /// Objective-C's methods: implemented (`@implementation`) and declared (`@interface`, `@protocol`).
    private static let objcMethodNodeTypes: Set<String> = ["method_definition", "method_declaration"]

    /// Where Objective-C keeps the names, bodies, parameters, and members the shared rules read.
    ///
    /// More than one declaration in five failing to parse sends the file to the fallback analyzer: Objective-C++
    /// (`.mm`) breaks at nearly every C++ construct, while plain Objective-C rarely loses more than the odd
    /// macro-heavy declaration.
    static let objcDeclarations = CDeclarationSpec(
        selectorMethodNodeTypes: objcMethodNodeTypes, selectorParameterNodeType: "method_parameter",
        bodyNodeType: "compound_statement", typeNodeTypes: objcTypeNodeTypes, categoryField: "category",
        methodMemberNodeTypes: objcMethodNodeTypes,
        fieldMemberNodeTypes: ["property_declaration", "instance_variable"],
        memberWrapperNodeTypes: ["implementation_definition", "instance_variables"], fileScopeKeyword: "static",
        maxErrorShare: 0.2
    )
}

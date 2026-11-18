import BouncerCore

/// One function or method found in a tree-sitter parse tree.
struct TSCollectedFunction {
    let name: String
    let startLine: Int
    let endLine: Int
    let branchCount: Int
    let hasDocComment: Bool
    let visibility: DeclarationVisibility
}

/// One class found in a tree-sitter parse tree. Empty for languages without classes.
struct TSCollectedType {
    let name: String
    let memberCount: Int
    let startLine: Int
}

/// One switch/match statement found in a tree-sitter parse tree.
struct TSCollectedSwitch {
    let caseCount: Int
    let startLine: Int
}

/// Everything the tree-sitter AST rules need, gathered in a single tree walk.
struct TreeSitterDeclarationSummary {
    let functions: [TSCollectedFunction]
    let types: [TSCollectedType]
    let switches: [TSCollectedSwitch]
    let importCount: Int
}

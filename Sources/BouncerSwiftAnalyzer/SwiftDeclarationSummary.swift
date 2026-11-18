import BouncerCore

/// One function or method found in a Swift file's syntax tree.
struct CollectedFunction {
    let name: String
    let startLine: Int
    let endLine: Int
    let branchCount: Int
    let hasDocComment: Bool
    let visibility: DeclarationVisibility
}

/// One type declaration found in a Swift file's syntax tree.
struct CollectedType {
    let name: String
    let memberCount: Int
    let startLine: Int
    let endLine: Int
}

/// One switch expression found in a Swift file's syntax tree.
struct CollectedSwitch {
    let caseCount: Int
    let startLine: Int
}

/// Everything Bouncer's Swift AST rules need, gathered in a single tree walk.
struct SwiftDeclarationSummary {
    let functions: [CollectedFunction]
    let types: [CollectedType]
    let switches: [CollectedSwitch]
    let importCount: Int
    let forceUnwrapLines: [Int]
    let forceTryLines: [Int]
}

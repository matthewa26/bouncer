import BouncerRules

/// Everything the Swift AST rules need: the shared declaration summary plus Swift-only extras.
struct SwiftDeclarationSummary {
    let declarations: DeclarationSummary
    let forceUnwrapLines: [Int]
    let forceTryLines: [Int]
}

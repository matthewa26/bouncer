import SwiftSyntax

/// Which Swift declarations the dead-code rules leave alone, because something other than the file's
/// own code may use them.
extension SwiftDeadCodeCollector {
    /// The access-level keywords, any of which overrides a `private extension`'s default.
    static var accessKeywords: [TokenKind] {
        [.keyword(.private), .keyword(.fileprivate), .keyword(.internal), .keyword(.package),
         .keyword(.public), .keyword(.open)]
    }

    /// Attributes that hand a declaration, or every member of a type, to the runtime or compiler.
    private static let exemptAttributes: Set<String> = [
        "objc", "objcMembers", "IBAction", "IBOutlet", "IBInspectable", "IBDesignable", "IBSegueAction",
        "NSManaged", "main", "resultBuilder", "propertyWrapper", "dynamicMemberLookup", "dynamicCallable"
    ]

    /// Names the compiler calls or synthesizes against without a written reference.
    private static let implicitNames: Set<String> = [
        "CodingKeys", "wrappedValue", "projectedValue", "callAsFunction", "buildBlock", "buildPartialBlock",
        "buildExpression", "buildOptional", "buildEither", "buildArray", "buildLimitedAvailability",
        "buildFinalResult", "dynamicallyCall"
    ]

    /// Reports whether a declaration is used from outside the code, or opted out by a leading `_`.
    ///
    /// - Parameters:
    ///   - name: The declared name; operators and `_`-prefixed names are exempt.
    ///   - modifiers: Its modifiers; `override` and `dynamic` are exempt.
    ///   - attributes: Its attributes.
    /// - Returns: Whether the dead-code rules should skip it.
    static func isExempt(_ name: String, modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax) -> Bool {
        guard let first = name.first, first.isLetter, !implicitNames.contains(name) else { return true }
        let exemptModifiers: [TokenKind] = [.keyword(.override), .keyword(.dynamic)]
        return modifiers.contains { exemptModifiers.contains($0.name.tokenKind) } || hasExemptAttribute(attributes)
    }

    /// Reports whether attributes include one that hands the declaration to the runtime or compiler.
    ///
    /// - Parameter attributes: The attributes.
    /// - Returns: Whether any is exempt, including every underscored attribute such as `@_cdecl`.
    static func hasExemptAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let name = element.as(AttributeSyntax.self)?.attributeName.trimmedDescription else { return false }
            return exemptAttributes.contains(name) || name.hasPrefix("_")
        }
    }

    /// Reports whether modifiers include a plain `private` or `fileprivate`; `private(set)` doesn't count.
    ///
    /// - Parameter modifiers: The modifiers.
    /// - Returns: Whether the declaration is visible only within the file.
    static func isPrivateAccess(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains {
            $0.detail == nil && [.keyword(.private), .keyword(.fileprivate)].contains($0.name.tokenKind)
        }
    }

    /// Reports whether a body does nothing but fail, so its parameters can't be meaningfully used.
    ///
    /// - Parameter body: The function body.
    /// - Returns: Whether it's empty, a lone `throw`, or a lone `fatalError`-style call.
    static func isStub(_ body: CodeBlockSyntax) -> Bool {
        guard body.statements.count <= 1, let item = body.statements.first?.item else { return true }
        if item.is(ThrowStmtSyntax.self) { return true }
        let callee = item.as(FunctionCallExprSyntax.self)?.calledExpression.trimmedDescription
        return ["fatalError", "preconditionFailure", "assertionFailure"].contains(callee ?? "")
    }

    /// Reads the name an extension's members are grouped under: the last component, without generics.
    ///
    /// - Parameter type: The extended type, such as `Outer.Inner<T>`.
    /// - Returns: Its simple name, such as `Inner`.
    static func simpleName(of type: TypeSyntax) -> String {
        let last = type.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
        return String(last.prefix { $0 != "<" })
    }
}

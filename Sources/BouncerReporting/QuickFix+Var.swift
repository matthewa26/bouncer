import Foundation
import BouncerCore

/// Turns a `var` declaration into `let`, when the narrower block scope can't change what the code does.
enum VarDeclarationFix {
    /// A one-name `var` declaration with an initializer: indentation and `export`, then the name.
    private static let declaration = TextPattern(
        #"^(\s*(?:export\s+)?)var\s+([A-Za-z_$][\w$]*)\s*(?::[^=]+)?=(?!=)"#
    )

    /// Turns the reported line's `var` into `let`.
    ///
    /// A `var` without an initializer keeps its value across loop iterations, so it needs one. The name mustn't be
    /// declared with `var` again, used earlier in the same block (a `let` can't be read before its declaration),
    /// or used after the block ends (a `let` isn't visible there).
    ///
    /// - Parameter site: The finding's site.
    /// - Returns: The edit, or `nil` when the line isn't such a declaration or the scope change could matter.
    @Sendable static func fix(_ site: FixSite) -> QuickFix? {
        guard [.typescript, .javascript].contains(site.language), let code = site.code,
              let parts = declaration.captures(in: code.masked), !MaskedLine.hasTopLevelComma(code.masked),
              isScopeSafe(name: parts[2], at: site) else { return nil }
        let keyword = parts[1].count..<(parts[1].count + "var".count)
        return site.replacingLine(with: code.replacing(keyword, with: "let"))
    }

    /// Checks that block scoping the name can't break a use or a redeclaration of it.
    ///
    /// The block is the run of lines indented at least as deeply as the declaration around it.
    ///
    /// - Parameters:
    ///   - name: The declared name.
    ///   - site: The declaration's site.
    /// - Returns: Whether the name isn't used before the declaration in its block, after the block, or redeclared.
    private static func isScopeSafe(name: String, at site: FixSite) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let use = TextPattern(#"(?<![\w$.])"# + escaped + #"(?![\w$])"#)
        let redeclaration = TextPattern(#"\bvar\s+"# + escaped + #"(?![\w$])"#)
        let others = site.lines.indices.filter { $0 != site.index }.map { site.lines[$0] }
        return !linesOutsideScope(of: site).contains(where: use.matches)
            && !others.contains(where: redeclaration.matches)
    }

    /// The lines where a `let` in place of the declaration couldn't be used: those before it in its block, and
    /// every line after the block ends.
    ///
    /// - Parameter site: The declaration's site.
    /// - Returns: Those lines.
    private static func linesOutsideScope(of site: FixSite) -> [String] {
        let depth = FixSite.indent(of: site.text).count
        let isOutside = { (line: String) in !line.trimmed.isEmpty && FixSite.indent(of: line).count < depth }
        let earlier = site.lines[..<site.index].reversed().prefix { !isOutside($0) }
        return Array(earlier) + site.lines[(site.index + 1)...].drop { !isOutside($0) }
    }
}

import BouncerCore

/// Fixes that rewrite one token on the reported line: an operator, a keyword, or a type.
///
/// `insecure-http-url` has no fixer: whether a server answers on `https://` (and whether the URL is an
/// identifier, such as an XML namespace, rather than a link) takes a person's judgment.
enum RewriteFixes {
    /// The fixers, keyed by rule ID.
    static let fixers: [String: QuickFixes.Fixer] = [
        "js-loose-equality": looseEquality,
        "explicit-any": explicitAny,
        "python-bare-except": bareExcept,
        "skipped-test": focusedTest,
        "js-var": VarDeclarationFix.fix
    ]

    /// A loose `==` or `!=`, as `js-loose-equality` matches it.
    private static let looseOperator = TextPattern(#"(?<![=!<>])==(?!=)|(?<![=!])!=(?!=)"#)
    /// A `null` or `undefined` operand, which `==` deliberately matches both of.
    private static let nullish = TextPattern(#"\b(null|undefined)\b"#)
    /// An `any` type written in an annotation.
    private static let annotatedAny = TextPattern(#"(?<=:)\s*any\b"#)
    /// The word `any` anywhere in code.
    private static let anyWord = TextPattern(#"\bany\b"#)
    /// A bare `except:` clause and its indentation.
    private static let bareExceptClause = TextPattern(#"^(\s*)except\s*:"#)
    /// A focused test: `it.only(`, `test.only(`, `describe.only(`, `fit(`, or `fdescribe(`.
    private static let focused = TextPattern(
        #"(?<=\bit|\btest|\bdescribe)\.only(?=\()|(?<![.\w$])f(?=(?:it|describe)\()"#
    )
    /// A skipped test, which needs fixing rather than unskipping.
    private static let skipped = TextPattern(#"\.skip\(|(?<![.\w$])x(?:it|describe)\("#)

    /// Turns the line's one loose `==` or `!=` into `===` or `!==`.
    ///
    /// - Parameter site: The finding's site.
    /// - Returns: The edit, or `nil` unless the line is TypeScript or JavaScript with exactly one loose operator,
    ///   no `null` or `undefined`, and no `/` that could start a regular expression.
    @Sendable static func looseEquality(_ site: FixSite) -> QuickFix? {
        guard [.typescript, .javascript].contains(site.language), let code = site.code,
              !code.masked.contains("/"), !nullish.matches(code.masked) else { return nil }
        let operators = code.ranges(of: looseOperator)
        guard operators.count == 1, let range = operators.first else { return nil }
        return site.replacingLine(with: code.replacing(range, with: code.text(range) + "="))
    }

    /// Turns the line's one annotated `: any` into `: unknown`.
    ///
    /// - Parameter site: The finding's site.
    /// - Returns: The edit, or `nil` unless the line is TypeScript with exactly one `any`, written after a colon.
    @Sendable static func explicitAny(_ site: FixSite) -> QuickFix? {
        guard site.language == .typescript, let code = site.code, code.ranges(of: anyWord).count == 1,
              let annotation = code.ranges(of: annotatedAny).first else { return nil }
        let word = (annotation.upperBound - "any".count)..<annotation.upperBound
        return site.replacingLine(with: code.replacing(word, with: "unknown"))
    }

    /// Turns a bare `except:` into `except Exception:`, which no longer catches `SystemExit` or
    /// `KeyboardInterrupt`.
    ///
    /// - Parameter site: The finding's site.
    /// - Returns: The edit, or `nil` when the line isn't a Python bare `except:`.
    @Sendable static func bareExcept(_ site: FixSite) -> QuickFix? {
        guard site.language == .python, let clause = bareExceptClause.captures(in: site.text) else { return nil }
        let rest = site.text.dropFirst(clause[0].count)
        return site.replacingLine(with: clause[1] + "except Exception:" + rest)
    }

    /// Unfocuses a focused test: `it.only(` becomes `it(`, and `fit(` becomes `it(`.
    ///
    /// A skipped test is left alone, since it needs fixing or deleting, not just running.
    ///
    /// - Parameter site: The finding's site.
    /// - Returns: The edit, or `nil` unless the line is TypeScript or JavaScript focusing exactly one test and
    ///   skipping none.
    @Sendable static func focusedTest(_ site: FixSite) -> QuickFix? {
        guard [.typescript, .javascript].contains(site.language), let code = site.code,
              !skipped.matches(code.masked) else { return nil }
        let marks = code.ranges(of: focused)
        guard marks.count == 1, let mark = marks.first else { return nil }
        return site.replacingLine(with: code.replacing(mark, with: ""))
    }
}

import BouncerCore

/// A debug-output call a fixer can delete when it's a whole statement on its own line.
struct DebugCall: Sendable {
    /// The languages the rule reports it in.
    let languages: Set<Language>
    /// The functions or macros, as written before their `(`, such as `console.log` or `println!`.
    let callees: [String]
    /// Whether the statement must end in `;`.
    let needsSemicolon: Bool

    /// Checks whether a line is exactly one call to one of the callees, ending the statement.
    ///
    /// - Parameter code: The masked line.
    /// - Returns: Whether the line is `callee(…)`, with only `;` (or nothing, where allowed) after it.
    func isWholeStatement(_ code: MaskedLine) -> Bool {
        let lead = code.masked.prefix { $0 == " " || $0 == "\t" }.count
        let body = code.masked.dropFirst(lead)
        guard let callee = callees.first(where: { body.hasPrefix($0 + "(") }),
              let close = code.closingBracket(of: lead + callee.count) else { return false }
        let rest = code.code((close + 1)..<code.original.count).trimmed
        return rest == ";" || (rest.isEmpty && !needsSemicolon)
    }
}

/// Fixes for leftover debug output: delete the statement, or unwrap Rust's `dbg!(…)` around a value.
enum DebugOutputFixes {
    /// The deletable debug calls, keyed by rule ID.
    static let calls: [String: DebugCall] = [
        "js-console-log": DebugCall(
            languages: [.typescript, .javascript], callees: ["console.log"], needsSemicolon: false
        ),
        "python-debug-print": DebugCall(languages: [.python], callees: ["print"], needsSemicolon: false),
        "swift-debug-print": DebugCall(
            languages: [.swift], callees: ["print", "debugPrint", "dump", "NSLog"], needsSemicolon: false
        ),
        "php-debug-output": DebugCall(
            languages: [.php], callees: ["var_dump", "print_r", "dd", "dump"].flatMap { [$0, "\\" + $0] },
            needsSemicolon: true
        ),
        "go-debug-print": DebugCall(
            languages: [.go], callees: ["fmt.Println", "fmt.Printf", "fmt.Print"], needsSemicolon: false
        ),
        "java-system-out": DebugCall(
            languages: [.java], callees: ["out", "err"].flatMap { stream in
                ["println", "print", "printf"].map { "System.\(stream).\($0)" }
            }, needsSemicolon: true
        )
    ]

    /// Rust's print macros, deleted as whole statements.
    private static let rustStatements = DebugCall(
        languages: [.rust], callees: ["dbg!", "println!", "print!", "eprintln!", "eprint!"], needsSemicolon: true
    )

    /// The fixers, keyed by rule ID.
    static let fixers: [String: QuickFixes.Fixer] = calls.mapValues { call -> QuickFixes.Fixer in
        { site in removal(of: call, at: site) }
    }.merging(["rust-debug-print": rustDebugPrint]) { first, _ in first }

    /// Deletes a debug call that's a whole statement on the reported line.
    ///
    /// - Parameters:
    ///   - call: The rule's debug call.
    ///   - site: The finding's site.
    /// - Returns: The edit, or `nil` when the line is anything but that one statement
    ///   or deleting it could break the code around it.
    @Sendable static func removal(of call: DebugCall, at site: FixSite) -> QuickFix? {
        guard call.languages.contains(site.language), let code = site.code else { return nil }
        if call.callees == ["console.log"], ["debugger", "debugger;"].contains(code.masked.trimmed) {
            return site.removingLine()
        }
        guard call.isWholeStatement(code), site.language != .go || GoUsage.survivesRemoval(of: site, code: code)
        else { return nil }
        return site.removingLine()
    }

    /// Deletes a Rust print or `dbg!` statement, or unwraps a `dbg!(value)` used as a value.
    ///
    /// - Parameter site: The finding's site.
    /// - Returns: The edit, or `nil` when the line isn't one of those shapes.
    @Sendable static func rustDebugPrint(_ site: FixSite) -> QuickFix? {
        guard site.language == .rust, let code = site.code else { return nil }
        if rustStatements.isWholeStatement(code) { return site.removingLine() }
        return DbgUnwrap.fix(site, code: code)
    }
}

/// Unwraps Rust's `dbg!(value)` to `value` where the value can stand without the macro's parentheses.
enum DbgUnwrap {
    /// A `dbg!(` call's opening.
    private static let opening = TextPattern(#"(?<![\w!])dbg!\("#)
    /// Code before an expression slot: an opening bracket, a comma, an arrow, or `return`.
    private static let slotStart = TextPattern(#"(^|[({,]|=>|\breturn|[^=!<>]=)$"#)
    /// Code after an expression slot: a closing bracket, a comma, or a `;`.
    private static let slotEnd = TextPattern(#"^($|[;)},])"#)

    /// Replaces the line's one `dbg!(value)` with `value`.
    ///
    /// - Parameters:
    ///   - site: The finding's site.
    ///   - code: Its masked line.
    /// - Returns: The edit, or `nil` unless the line has exactly one `dbg!` with a single value, sitting where any
    ///   expression fits without parentheses.
    static func fix(_ site: FixSite, code: MaskedLine) -> QuickFix? {
        let calls = code.ranges(of: opening)
        guard calls.count == 1, let call = calls.first, let close = code.closingBracket(of: call.upperBound - 1)
        else { return nil }
        let inner = call.upperBound..<close
        guard !code.code(inner).trimmed.isEmpty, !MaskedLine.hasTopLevelComma(code.code(inner)),
              slotStart.matches(code.code(0..<call.lowerBound).trimmed),
              slotEnd.matches(code.code((close + 1)..<code.original.count).trimmed) else { return nil }
        return site.replacingLine(with: code.replacing(call.lowerBound..<(close + 1), with: code.text(inner).trimmed))
    }
}

/// Checks that deleting a Go print statement still compiles: Go rejects an unused import or local.
enum GoUsage {
    /// An identifier not preceded by a `.`, so a field or method name isn't counted.
    private static let identifier = TextPattern(#"(?<![\w.])[A-Za-z_]\w*"#)
    /// How often a local the call reads must appear elsewhere in its function: its declaration and another use.
    private static let minimumOtherMentions = 2
    /// Predeclared names that need no other use.
    private static let predeclared: Set = ["nil", "true", "false", "len", "cap", "string", "error"]

    /// Checks that `fmt` is used elsewhere in the file, and every name the call reads appears at least twice more
    /// in its function, as a declaration and another use.
    ///
    /// A name that only appears once more may be a local declared just to print, which Go would then reject as
    /// unused, so it gets no fix.
    ///
    /// - Parameters:
    ///   - site: The print statement's site.
    ///   - code: Its masked line.
    /// - Returns: Whether the file still compiles without the line.
    static func survivesRemoval(of site: FixSite, code: MaskedLine) -> Bool {
        let otherLines = site.lines.indices.filter { $0 != site.index }.map { site.lines[$0] }
        guard otherLines.contains(where: { $0.contains("fmt.") }), let function = enclosingFunction(of: site)
        else { return false }
        let names = Set(code.ranges(of: identifier).map(code.text)).subtracting(predeclared).subtracting(["fmt"])
        let others = function.filter { $0 != site.index }.map { site.lines[$0] }
        return names.allSatisfy { name in
            let use = TextPattern(#"(?<![\w.])"# + name + #"\b"#)
            return others.map { use.ranges(in: $0).count }.reduce(0, +) >= minimumOtherMentions
        }
    }

    /// The lines of the top-level function around the reported line, from its `func` line to its closing `}`.
    ///
    /// - Parameter site: The site.
    /// - Returns: The line indices, or `nil` when the line isn't inside a gofmt-formatted function.
    private static func enclosingFunction(of site: FixSite) -> ClosedRange<Int>? {
        guard let start = (0..<site.index).last(where: { site.lines[$0].hasPrefix("func ") }),
              let end = (site.index..<site.lines.count).first(where: { site.lines[$0].hasPrefix("}") })
        else { return nil }
        return start...end
    }
}

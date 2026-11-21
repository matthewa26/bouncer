import Foundation
import BouncerCore

/// Flags request input joined into a file path or opened as a file: `path.join(root, req.params.name)`,
/// `open(os.path.join(DIR, request.args["f"]))`, `os.Open(filepath.Join(dir, r.URL.Query().Get("f")))`.
///
/// It's text-based and approximate. A line is flagged when a path or file call (`path.join`/`resolve`,
/// `os.path.join`, `open(`, `send_file`, `sendFile`, `res.download`, `fs.*`, `filepath.Join`, `os.Open`/`ReadFile`/
/// `Create`/`Remove`, `http.ServeFile`, `new File(`, `Paths.get`, `Path.of`, `URL(fileURLWithPath:)`,
/// `appendingPathComponent`, `appending(path:)`) has, after it on the same line, either a request source (`req.params`,
/// `req.query`, `req.body`, `request.args`/`form`/`values`/`GET`/`POST`, `r.URL.Query()`, `FormValue(`,
/// `mux.Vars(`, `c.Param(`/`c.Query(`, `ctx.params`/`ctx.query`, `searchParams.get(`, `event.queryStringParameters`/
/// `pathParameters`) or a variable assigned from one in the 10 lines above and not reassigned since (including
/// destructuring and Go's `a, b :=`), or a parameter of a Flask-style route (`@app.route("/files/<name>")`) or
/// Spring `@RequestParam`/`@PathVariable` declared there. A line or assignment that passes the value through
/// `basename`, `filepath.Base`, `secure_filename`, `lastPathComponent`, `safe_join`, `parseInt`, `int(`, `Atoi`, or a
/// `sanitize…` call doesn't count. Test files are skipped.
public struct PathTraversalRule: Rule {
    public static let ruleID = "path-traversal"
    public let id = PathTraversalRule.ruleID
    private static let window = 10
    private static let sink = TextMatching.regex(
        #"\bpath\.(?:join|resolve)\(|\bos\.path\.join\(|(?<![.\w])open\(|\bsend_file\(|\bsendFile\(|\bres\.download\(|"#
            + #"\bfsp?\.(?:promises\.)?\w+\(|\b(?:filepath|path)\.Join\(|\bos\.(?:Open|OpenFile|ReadFile|WriteFile|"#
            + #"Create|Remove|RemoveAll)\(|\bioutil\.ReadFile\(|\bhttp\.ServeFile\(|\bnew\s+File(?:InputStream|Reader|"#
            + #"OutputStream|Writer)?\(|\bPaths\.get\(|\bPath\.of\(|\bURL\(fileURLWithPath:|"#
            + #"\.appendingPathComponent\(|\.appending\(path(?:Component)?:"#
    )
    static let source = TextMatching.regex(
        #"\breq(?:uest)?\.(?:params|query|body|files?)\b|\brequest\.(?:args|form|values|files|GET|POST|FILES|"#
            + #"query_params|path_params|match_info)\b|\b(?:r|req)\.URL\.Query\(\)|\.(?:Post)?FormValue\(|"#
            + #"\bmux\.Vars\(|\bchi\.URLParam\(|\bc\.(?:Param|Query|PostForm|DefaultQuery|FormFile)\(|"#
            + #"\bctx\.(?:params|query|request\.body)\b|\bsearchParams\.get\(|\bevent\.(?:queryStringParameters|"#
            + #"pathParameters)\b|\$_(?:GET|POST|REQUEST)\b|\b(?:request|req)\.getParameter\(|\breq\.parameters\.get\("#
    )
    static let sanitizer = TextMatching.regex(
        #"\bbasename\(|\bfilepath\.Base\(|\bpath\.Base\(|secure_filename\(|lastPathComponent|safe_join\(|"#
            + #"\bparseInt\(|\bNumber\(|(?<![.\w])int\(|\bAtoi\(|(?i:sanitiz)\w*\(|\buuid"#
    )

    /// Creates the rule.
    public init() {}

    /// Flags each path or file call fed request input.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per flagged line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, !TextMatching.isTestPath(file.path), RequestTaint.mayHoldRequestInput(file.contents)
        else { return [] }
        let message = "Request input is joined into a file path; reduce it to a base name, or check the resolved "
            + "path stays inside the intended directory."
        return SourceText.flagCodeLines(id, settings, file) { Self.joinsRequestInput(at: $0, in: file) ? message : nil }
    }

    /// Reports whether a line passes request input to a path or file call.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: Whether a sink on the line takes a request source or a tainted name.
    private static func joinsRequestInput(at index: Int, in file: SourceFile) -> Bool {
        let line = SourceText.code(of: file.lines[index])
        guard let start = line.range(of: sinkPrefix(line) ?? "")?.lowerBound,
              !TextMatching.matches(sanitizer, line) else { return false }
        let arguments = String(line[start...])
        if TextMatching.matches(source, arguments) { return true }
        let tainted = RequestTaint.names(before: index, in: file, window: window)
        return tainted.contains { mentions($0, in: arguments) }
    }

    /// Reports whether code mentions a variable on its own, not as a property of something else.
    ///
    /// - Parameters:
    ///   - name: The variable.
    ///   - code: The code to search.
    /// - Returns: Whether `name` appears as a whole identifier not preceded by `.`.
    private static func mentions(_ name: String, in code: String) -> Bool {
        let pattern = #"(?<![\w$.])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\w$])"#
        return TextMatching.matches(TextMatching.regex(pattern), code)
    }

    /// Finds the first path or file call on a line.
    ///
    /// - Parameter line: The line's code.
    /// - Returns: The call's text, or `nil` if the line has none.
    private static func sinkPrefix(_ line: String) -> String? {
        TextMatching.captures(sink, line).first?.first
    }
}

/// Finds the names that hold request input near a line, for `PathTraversalRule`.
enum RequestTaint {
    private static let assigned = TextMatching.regex(
        #"(?:\{([^}]*)\}|\b([A-Za-z_$][\w$]*(?:\s*,\s*[A-Za-z_$][\w$]*)*))\s*(?::=|=(?!=))"#
    )
    private static let routeParameter = TextMatching.regex(#"<(?:\w+:)?(\w+)>|/:(\w+)"#)
    private static let route = TextMatching.regex(#"(?m)^\s*@\w+(?:\.\w+)*\.(?:route|get|post|put|delete|patch)\("#)
    private static let springParameter = TextMatching.regex(
        #"@(?:RequestParam|PathVariable)(?:\([^)]*\))?\s+(?:final\s+)?[\w<>]+\s+(\w+)"#
    )

    /// Reports whether a file mentions request input anywhere, as a quick check before reading it line by line.
    ///
    /// - Parameter contents: The file's text.
    /// - Returns: Whether it has a request source, a route with parameters, or a Spring request parameter.
    static func mayHoldRequestInput(_ contents: String) -> Bool {
        TextMatching.matches(PathTraversalRule.source, contents) || TextMatching.matches(route, contents)
            || TextMatching.matches(springParameter, contents)
    }

    /// Collects the names assigned from request input (and not reassigned from anything else since), or declared as
    /// route parameters, in the lines above.
    ///
    /// - Parameters:
    ///   - index: The line being checked.
    ///   - file: The file it's in.
    ///   - window: How many lines above to look.
    /// - Returns: The tainted names.
    static func names(before index: Int, in file: SourceFile, window: Int) -> Set<String> {
        file.lines[max(0, index - window)..<index].reduce(into: Set<String>()) { tainted, raw in
            let line = SourceText.code(of: raw)
            let isClean = TextMatching.matches(PathTraversalRule.sanitizer, line)
                || !TextMatching.matches(PathTraversalRule.source, line)
            let assigned = assignedNames(line)
            if isClean { tainted.subtract(assigned) } else { tainted.formUnion(assigned) }
            if TextMatching.matches(route, raw) { tainted.formUnion(captured(routeParameter, raw)) }
            tainted.formUnion(captured(springParameter, raw))
        }
    }

    /// Reads the names a line assigns to, including destructured and comma-separated ones.
    ///
    /// - Parameter line: The line's code.
    /// - Returns: The assigned names.
    private static func assignedNames(_ line: String) -> [String] {
        let targets = TextMatching.captures(assigned, line).first.map { $0[1] + $0[2] } ?? ""
        return targets.split { ",: ".contains($0) }.map(String.init)
            .filter { $0.first.map { $0.isLetter || $0 == "_" } ?? false }
    }

    /// Collects every non-empty capture group of a pattern's matches.
    ///
    /// - Parameters:
    ///   - pattern: The pattern.
    ///   - line: The text to search.
    /// - Returns: The captured names.
    private static func captured(_ pattern: NSRegularExpression?, _ line: some StringProtocol) -> [String] {
        TextMatching.captures(pattern, line).flatMap { $0.dropFirst().filter { !$0.isEmpty } }
    }
}

import Foundation
import BouncerCore

/// Flags mutable state shared across a module with nothing in the file to guard it: no lock, queue, atomic, or actor.
///
/// It's a text-level approximation of a data-race check, and reads each language differently:
/// - Swift: a global `var`, or a `static var` in a type that isn't an `actor` or isolated to `@MainActor` (or
///   another global actor). A variable marked `@MainActor` or `@TaskLocal`, or opted out with an unsafe
///   `nonisolated` (which `swift-unchecked-sendable` already flags), is skipped, as are computed properties,
///   globals in `main.swift` and package manifests (top-level code that runs once), and files that use a lock,
///   `DispatchQueue`, `DispatchSemaphore`, `Mutex`, or `Atomic`.
/// - Go: a package-level `var` assigned inside a function other than `init`, `main`, or `TestMain`, in a file that
///   never uses `sync` or `atomic`.
/// - TypeScript/JavaScript: a module-level `let` reassigned inside a function, in a file that uses `async`, `await`,
///   `.then(`, or a timer. JavaScript can't race on memory, but a module variable written across an `await`
///   interleaves between concurrent calls the same way.
/// - Python: a `global` statement in a file that uses `threading`, `concurrent.futures`, or `asyncio` without a
///   `Lock`, `RLock`, `Semaphore`, or `Condition`.
///
/// The `languages` parameter picks the languages checked; by default Swift and Go, where shared state really is
/// reached from several threads. Test files are skipped.
public struct SharedMutableStateRule: Rule {
    public static let ruleID = "shared-mutable-state"
    public let id = SharedMutableStateRule.ruleID
    static let defaultLanguages = ["swift", "go"]

    /// Creates the rule.
    public init() {}

    /// Flags each unguarded piece of shared mutable state.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's resolved settings and `languages`.
    /// - Returns: One finding per variable (or `global` statement), on its declaration.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        let languages = settings.parameters.stringList("languages", default: Self.defaultLanguages)
        guard settings.enabled, let detector = SharedStateDetector.of(file.language),
              languages.contains(detector.name), !TextMatching.isTestPath(file.path) else { return [] }
        let code = SourceText.codeMask(of: file, profile: LanguageProfiles.profile(for: file.language))
        return detector.flag(file, code).map { SourceText.finding(id, settings, file, $0.line, $0.message) }
    }
}

/// One flagged variable: its 0-based line and the finding's message.
struct SharedStateFlag {
    let line: Int
    let message: String
}

/// A language's shared-state check, by the name the `languages` parameter uses.
struct SharedStateDetector {
    let name: String
    /// Reads a file and the mask of its code lines, and returns its flagged variables.
    let flag: @Sendable (SourceFile, [Bool]) -> [SharedStateFlag]

    /// Looks up a language's check.
    ///
    /// - Parameter language: The file's language.
    /// - Returns: The check, or `nil` for a language the rule doesn't read.
    static func of(_ language: Language) -> SharedStateDetector? {
        all[language]
    }

    private static let all: [Language: SharedStateDetector] = [
        .swift: SharedStateDetector(name: "swift", flag: SwiftSharedState.flag),
        .go: SharedStateDetector(name: "go", flag: GoSharedState.flag),
        .typescript: SharedStateDetector(name: "typescript", flag: ScriptSharedState.flag),
        .javascript: SharedStateDetector(name: "javascript", flag: ScriptSharedState.flag),
        .python: SharedStateDetector(name: "python", flag: PythonSharedState.flag)
    ]

    /// Tracks brace depth line by line, so a check knows which lines sit at the top level.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - code: Which lines hold code; braces on other lines are ignored.
    /// - Returns: Each line's brace depth at its start.
    static func depths(of file: SourceFile, code: [Bool]) -> [Int] {
        var depth = 0
        return file.lines.indices.map { index in
            let start = depth
            let braces = code[index] ? SourceText.braces(of: file.lines[index]) : []
            depth = max(0, braces.reduce(depth) { $1 == "{" ? $0 + 1 : $0 - 1 })
            return start
        }
    }
}

/// Swift globals and static variables outside an actor or global-actor isolation.
enum SwiftSharedState {
    /// A scope a brace opens: an isolated type (an actor, or a type marked `@MainActor` or another global actor),
    /// any other type, or anything else (a function, closure, or block).
    private enum Scope { case isolated, shared, other }

    private static let guarded = TextMatching.regex(
        #"\b(?:NS(?:Recursive)?Lock|NSCondition|os_unfair_lock\w*|OSAllocatedUnfairLock|Mutex|Atomic\w*|"#
            + #"ManagedAtomic|DispatchQueue|DispatchSemaphore|pthread_mutex\w*|withLock|\w+Lock)\b"#
    )
    private static let modifiers =
        #"(?:(?:public|private|fileprivate|internal|open|package)(?:\(set\))?\s+|final\s+)*"#
    private static let variable = TextMatching.regex(
        #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"# + modifiers + #"(static\s+)?"# + modifiers + #"var\s+([A-Za-z_]\w*)"#
    )
    private static let isolation = TextMatching.regex(#"@\w*Actor\b|@TaskLocal\b|\bnonisolated\(unsafe\)"#)
    private static let typeDeclaration = TextMatching.regex(#"\b(actor|class|struct|enum|extension|protocol)\s+\w"#)
    private static let attributeLine = TextMatching.regex(#"^\s*@\w+(?:\(.*\))?\s*$"#)

    /// Flags each unguarded global or static variable in a Swift file.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - code: Which lines hold code.
    /// - Returns: The flagged variables.
    static func flag(_ file: SourceFile, _ code: [Bool]) -> [SharedStateFlag] {
        guard !TextMatching.matches(guarded, file.contents) else { return [] }
        var scopes: [Scope] = [], flags: [SharedStateFlag] = []
        for index in file.lines.indices where code[index] {
            let line = SourceText.code(of: file.lines[index])
            if let flagged = unguarded(line, at: index, in: file, scopes: scopes) { flags.append(flagged) }
            enter(line, at: index, in: file, scopes: &scopes)
        }
        return flags
    }

    /// Reads a variable declared on a line, if it's unguarded shared state.
    ///
    /// - Parameters:
    ///   - line: The line's code.
    ///   - index: Its 0-based index.
    ///   - file: The file.
    ///   - scopes: The scopes open at the line's start.
    /// - Returns: The flag, or `nil` if the line declares no such variable.
    private static func unguarded(_ line: String, at index: Int, in file: SourceFile, scopes: [Scope])
        -> SharedStateFlag? {
        guard let captures = TextMatching.captures(variable, line).first else { return nil }
        let isStatic = !captures[1].isEmpty, name = captures[2]
        let shared = isStatic ? scopes.last == .shared : scopes.isEmpty && !isScript(file.path.lastPathComponent)
        guard shared, !isIsolated(at: index, in: file), !isComputed(line, after: name) else { return nil }
        let kind = isStatic ? "Static var" : "Global var"
        return SharedStateFlag(line: index, message: "\(kind) \(name) is shared mutable state with no lock, queue, or "
            + "actor in this file; make it a let, isolate it to an actor or @MainActor, or guard it with a lock.")
    }

    /// Reports whether a file runs top-level code once, as a script: `main.swift` or a package manifest.
    ///
    /// - Parameter name: The file's name.
    /// - Returns: Whether its globals are a script's locals.
    private static func isScript(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered == "main.swift" || lowered == "package.swift"
            || (lowered.hasPrefix("package@swift") && lowered.hasSuffix(".swift"))
    }

    /// Reports whether a declaration has an isolating attribute, on its line or on the attribute lines above it.
    ///
    /// - Parameters:
    ///   - index: The declaration's 0-based line.
    ///   - file: The file.
    /// - Returns: Whether `@MainActor`, another global actor, `@TaskLocal`, or an unsafe `nonisolated` applies.
    private static func isIsolated(at index: Int, in file: SourceFile) -> Bool {
        var line = index
        while line >= 0 {
            if TextMatching.matches(isolation, SourceText.code(of: file.lines[line])) { return true }
            line -= 1
            guard line >= 0, TextMatching.matches(attributeLine, file.lines[line]) else { return false }
        }
        return false
    }

    /// Reports whether a variable is computed: a `{` follows its name with no `=` before it.
    ///
    /// - Parameters:
    ///   - line: The declaration's code.
    ///   - name: The variable's name.
    /// - Returns: Whether it has a getter body rather than storage.
    private static func isComputed(_ line: String, after name: String) -> Bool {
        guard let range = line.range(of: name) else { return false }
        let rest = line[range.upperBound...]
        guard let brace = rest.firstIndex(of: "{") else { return false }
        return !rest[..<brace].contains("=")
    }

    /// Classifies the scope a line's first brace opens.
    ///
    /// - Parameters:
    ///   - line: The line's code.
    ///   - index: Its 0-based index.
    ///   - file: The file.
    /// - Returns: The scope's kind.
    private static func scope(of line: String, at index: Int, in file: SourceFile) -> Scope {
        guard let keyword = TextMatching.captures(typeDeclaration, line).first?[1], keyword != "protocol" else {
            return .other
        }
        return keyword == "actor" || isIsolated(at: index, in: file) ? .isolated : .shared
    }

    /// Opens and closes scopes for a line's braces: its first `{` opens the scope its declaration names, and any
    /// later one opens `.other`.
    ///
    /// - Parameters:
    ///   - line: The line's code.
    ///   - index: Its 0-based index.
    ///   - file: The file.
    ///   - scopes: The open scopes, updated.
    private static func enter(_ line: String, at index: Int, in file: SourceFile, scopes: inout [Scope]) {
        let braces = SourceText.braces(of: line)
        let opening = braces.contains("{") ? scope(of: line, at: index, in: file) : .other
        for (position, brace) in braces.enumerated() {
            if brace == "}" { _ = scopes.popLast(); continue }
            scopes.append(braces[..<position].contains("{") ? .other : opening)
        }
    }
}

/// Go package-level variables written from functions without `sync` or `atomic`.
enum GoSharedState {
    private static let guarded = TextMatching.regex(#"\bsync\.|\batomic\.|"sync(?:/atomic)?""#)
    private static let singleVar = TextMatching.regex(#"^var\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)"#)
    private static let blockMember = TextMatching.regex(#"^(?:\t| {1,4})([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\b"#)
    private static let function = TextMatching.regex(#"^func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)"#)
    private static let setupFunctions: Set = ["init", "main", "TestMain"]

    /// Flags each package-level variable that a function assigns, in a Go file with no `sync` or `atomic`.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - code: Which lines hold code.
    /// - Returns: The flagged variables, one per variable, on its declaration.
    static func flag(_ file: SourceFile, _ code: [Bool]) -> [SharedStateFlag] {
        guard !TextMatching.matches(guarded, file.contents) else { return [] }
        let functions = self.functions(in: file)
        return packageVariables(in: file, code: code).compactMap { variable in
            functions.first { assigns(variable.name, in: $0, file: file) }.map { function in
                SharedStateFlag(line: variable.line, message: "Package-level var \(variable.name) is assigned in "
                    + "\(function.name) with no sync or atomic use in this file; guard it with a mutex, use an "
                    + "atomic, or pass the state explicitly.")
            }
        }
    }

    /// Lists the package-level variables, from `var x …` lines and `var ( … )` blocks.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - code: Which lines hold code.
    /// - Returns: Each variable's name and 0-based declaration line.
    private static func packageVariables(in file: SourceFile, code: [Bool]) -> [(name: String, line: Int)] {
        var inBlock = false
        return file.lines.indices.filter { code[$0] }.flatMap { index -> [(name: String, line: Int)] in
            let line = SourceText.code(of: file.lines[index])
            if inBlock && line.hasPrefix(")") { inBlock = false }
            if line.hasPrefix("var (") || line.hasPrefix("var(") { inBlock = true; return [] }
            let names = TextMatching.captures(inBlock ? blockMember : singleVar, line).first?[1]
            return (names ?? "").split(separator: ",").map { ($0.trimmingCharacters(in: .whitespaces), index) }
        }
    }

    /// Lists the top-level functions other than setup ones, with their lines.
    ///
    /// - Parameter file: The file.
    /// - Returns: Each function's name and line range.
    private static func functions(in file: SourceFile) -> [(name: String, lines: ClosedRange<Int>)] {
        file.lines.indices.compactMap { index in
            guard let name = TextMatching.captures(function, file.lines[index]).first?[1],
                  !setupFunctions.contains(name) else { return nil }
            return (name, index...SourceText.blockEnd(from: index, in: file))
        }
    }

    /// Reports whether a function assigns a package-level variable without declaring its own of that name.
    ///
    /// - Parameters:
    ///   - name: The variable's name.
    ///   - function: The function's name and lines.
    ///   - file: The file.
    /// - Returns: Whether the function writes the package-level variable.
    private static func assigns(_ name: String, in function: (name: String, lines: ClosedRange<Int>),
                                file: SourceFile) -> Bool {
        let body = file.lines[function.lines].map { SourceText.code(of: $0) }.joined(separator: "\n")
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let shadow = #"\b"# + escaped + #"\s*(?:,\s*\w+\s*)*:=|\bvar\s+"# + escaped + #"\b|[(,]\s*"# + escaped
            + #"\s+[\w*\[.]"#
        guard !TextMatching.matches(TextMatching.regex(shadow), body) else { return false }
        let write = #"(?m)(?:^|[^\w.])"# + escaped + #"\s*(?:\[[^\]\n]*\]\s*)?(?:[-+*/%|&^]|<<|>>|&\^)?=(?!=)|"#
            + #"(?:^|[^\w.])"# + escaped + #"\s*(?:\+\+|--)"#
        return TextMatching.matches(TextMatching.regex(write), body)
    }
}

/// TypeScript and JavaScript module-level `let`s reassigned in functions of a file that runs code asynchronously.
enum ScriptSharedState {
    private static let asynchronous = TextMatching.regex(#"\bawait\b|\basync\b|\.then\(|\bset(?:Timeout|Interval)\("#)
    private static let moduleLet = TextMatching.regex(#"^\s*(?:export\s+)?let\s+([A-Za-z_$][\w$]*)"#)

    /// Flags each module-level `let` reassigned inside a function, in a file with asynchronous code.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - code: Which lines hold code.
    /// - Returns: The flagged variables, on their declarations.
    static func flag(_ file: SourceFile, _ code: [Bool]) -> [SharedStateFlag] {
        guard TextMatching.matches(asynchronous, file.contents) else { return [] }
        let view = ScriptView(file, code: code)
        return view.topLevel.compactMap { index in
            guard let name = TextMatching.captures(moduleLet, view.lines[index]).first?[1],
                  !view.parameters.contains(name), reassigns(name, in: view.nested) else { return nil }
            return SharedStateFlag(line: index, message: message(for: name))
        }
    }

    /// Words the finding for a module-level variable.
    ///
    /// - Parameter name: The variable's name.
    /// - Returns: The message.
    private static func message(for name: String) -> String {
        "Module-level let \(name) is reassigned inside functions of a file that runs code asynchronously; calls "
            + "interleave at each await, so keep the state per call or behind one owner."
    }

    /// Reports whether nested code reassigns a module-level variable, when no function declares a local of that
    /// name.
    ///
    /// - Parameters:
    ///   - name: The variable's name.
    ///   - nested: The file's code inside braces.
    /// - Returns: Whether some function writes the module-level variable.
    private static func reassigns(_ name: String, in nested: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let local = TextMatching.regex(#"\b(?:let|const|var)\s+"# + escaped + #"\b"#)
        guard !TextMatching.matches(local, nested) else { return false }
        let write = #"(?m)(?:^|[^\w$.])"# + escaped + #"\s*(?:[-+*/%|&^]|\|\||&&|\?\?|<<|>>>?|\*\*)?=(?![=>])|"#
            + #"(?:^|[^\w$.])"# + escaped + #"\s*(?:\+\+|--)|(?:\+\+|--)"# + escaped + #"\b"#
        return TextMatching.matches(TextMatching.regex(write), nested)
    }
}

extension ScriptSharedState {
    private static let parameterList = TextMatching.regex(
        #"(?:\bfunction\b\s*\*?\s*[\w$]*\s*|(?<![\w$])(?!(?:if|for|while|switch|with|return|catch)\b)[\w$]+\s*)"#
            + #"\(([^()]*)\)\s*(?::\s*[^{=;]+)?\{|\(([^()]*)\)\s*(?::\s*[^=;{]+)?=>|(?<![\w$.])([\w$]+)\s*=>"#
    )

    /// Lists the names every function in a file takes as parameters, from `function f(a, b)`, method
    /// `f(a: T) {`, and arrow `(a, b) =>` or `a =>` parameter lists.
    ///
    /// - Parameter code: The file's code.
    /// - Returns: The parameter names, without types or defaults.
    static func parameterNames(in code: String) -> Set<String> {
        let lists = TextMatching.captures(parameterList, code).flatMap { $0.dropFirst() }
        return Set(lists.flatMap { $0.split(separator: ",") }.compactMap { parameter in
            parameter.split(whereSeparator: { ":=?".contains($0) }).first
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        })
    }
}

/// A script file's code split by brace depth, for finding module-level variables and the functions that write them.
struct ScriptView {
    /// Each line's code, strings blanked and trailing comments cut.
    let lines: [String]
    /// The 0-based code lines at the top level.
    let topLevel: [Int]
    /// The code inside braces, joined by newlines.
    let nested: String
    /// Every name a function in the file takes as a parameter.
    let parameters: Set<String>

    /// Reads a file's code by depth.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - code: Which lines hold code.
    init(_ file: SourceFile, code: [Bool]) {
        let depths = SharedStateDetector.depths(of: file, code: code)
        let codeLines = file.lines.map { SourceText.code(of: $0) }
        lines = codeLines
        topLevel = codeLines.indices.filter { code[$0] && depths[$0] == 0 }
        nested = codeLines.indices.filter { code[$0] && depths[$0] > 0 }.map { codeLines[$0] }.joined(separator: "\n")
        parameters = ScriptSharedState.parameterNames(in: codeLines.joined(separator: "\n"))
    }
}

/// Python `global` statements in a file that runs threads or tasks without a lock.
enum PythonSharedState {
    private static let concurrent = TextMatching.regex(
        #"(?m)^\s*(?:import|from)\s+(?:threading|concurrent|asyncio|_thread|multiprocessing\.dummy)\b"#
    )
    private static let lock = TextMatching.regex(#"\b(?:R?Lock|(?:Bounded)?Semaphore|Condition)\s*\("#)
    private static let global = TextMatching.regex(#"^\s+global\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)"#)

    /// Flags each `global` statement in a function, in a file that uses threads or asyncio with no lock.
    ///
    /// - Parameters:
    ///   - file: The file.
    ///   - code: Which lines hold code.
    /// - Returns: The flagged statements.
    static func flag(_ file: SourceFile, _ code: [Bool]) -> [SharedStateFlag] {
        let unguarded = TextMatching.matches(concurrent, file.contents) && !TextMatching.matches(lock, file.contents)
        let statements = unguarded ? file.lines.indices.filter { code[$0] } : []
        return statements.compactMap { index in
            TextMatching.captures(global, file.lines[index]).first.map { names in
                SharedStateFlag(line: index, message: "global \(names[1]) is rebound in a file that runs threads or "
                    + "tasks with no Lock; guard the shared state with a lock or pass it explicitly.")
            }
        }
    }
}

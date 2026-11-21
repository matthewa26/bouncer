import BouncerCore

/// The bundled `LanguageProfile` for every heuristically-analyzed language.
///
/// This is the extensibility point the plan calls out: a new language, or a
/// new pattern rule for an existing one, is added here as data.
public enum LanguageProfiles {
    /// Looks up the bundled profile for a language.
    ///
    /// - Parameter language: The language to look up.
    /// - Returns: Its profile, or a minimal best-effort profile for `.other`.
    public static func profile(for language: Language) -> LanguageProfile {
        if case .other = language { return bestEffort }
        return byLanguage[language] ?? bestEffort
    }

    private static let bestEffort = LanguageProfile(lineCommentPrefixes: ["#", "//", "--"])

    private static let byLanguage: [Language: LanguageProfile] = [
        .swift: swift, .python: python, .zsh: shell, .bash: shell,
        .powershell: powershell, .typescript: javascriptLike, .javascript: javascriptLike,
        .cpp: cpp, .java: java, .go: go, .sql: sql, .c: c, .objc: objc,
        .rust: rust
    ]

    private static let python = LanguageProfile(
        lineCommentPrefixes: ["#"],
        functionStartPattern: #"^\s*def\s+\w+\s*\("#,
        switchStartPattern: #"^\s*match\s+.*:\s*$"#,
        switchBranchPattern: #"^\s*case\s+"#,
        importLinePattern: #"^\s*(import|from)\s+"#,
        namingRules: [
            NamingRule(
                declarationPattern: #"\bdef\s+([A-Za-z_]\w*)"#,
                expectedIdentifierPattern: #"^[a-z_][a-z0-9_]*$"#, kindLabel: "function"
            ),
            NamingRule(
                declarationPattern: #"\bclass\s+([A-Za-z_]\w*)"#,
                expectedIdentifierPattern: #"^[A-Z]\w*$"#, kindLabel: "class"
            )
        ],
        extraPatternRules: [
            PatternRuleSpec(
                id: "python-bare-except", pattern: #"^\s*except\s*:"#,
                message: "Bare except clause also catches SystemExit and KeyboardInterrupt."
            ),
            PatternRuleSpec(
                id: "python-mutable-default-arg", pattern: #"def\s+\w+\([^)]*=\s*(\[\]|\{\})"#,
                message: "Mutable default argument is shared across every call."
            ),
            PatternRuleSpec(
                id: "python-debug-print", pattern: #"^\s*print\("#,
                message: "Remove debug output, or use the logging module."
            ),
            PatternRuleSpec(
                id: "python-eval-exec", pattern: #"\b(eval|exec)\s*\("#,
                message: "eval/exec runs arbitrary code."
            ),
            PatternRuleSpec(
                id: "python-unsafe-deserialization",
                pattern: #"\b(pickle|marshal)\.loads?\(|\byaml\.load\((?![^)]*SafeLoader)"#
                    + #"|\byaml\.unsafe_load\(|\b(?:cPickle|dill)\.loads?\(|\bpickle\.Unpickler\(|"#
                    + #"\bjsonpickle\.decode\("#,
                message: "Deserializing untrusted data can run arbitrary code; use json or yaml.safe_load."
            ),
            PatternRuleSpec(
                id: "python-shell-injection", pattern: #"\bsubprocess\.\w+\([^)]*shell\s*=\s*True|\bos\.system\("#,
                message: "Running a shell command string risks injection; pass an argument list without shell=True."
            ),
            PatternRuleSpec(
                id: "skipped-test", pattern: #"@(unittest\.)?skip|pytest\.mark\.skip"#,
                message: "Skipped test; fix it or delete it."
            )
        ]
    )

    private static let shell = LanguageProfile(
        lineCommentPrefixes: ["#"],
        functionStartPattern: #"^\s*(function\s+\w+|\w+\s*\(\)\s*\{)"#,
        switchStartPattern: #"^\s*case\s+.*\s+in\s*$"#,
        switchBranchPattern: #"^\s*[A-Za-z0-9_*|."'$-]+\)\s*$"#,
        importLinePattern: #"^\s*(source\s|\.\s+\S)"#,
        namingRules: [
            NamingRule(
                declarationPattern: #"function\s+([A-Za-z_]\w*)"#,
                expectedIdentifierPattern: #"^[a-z_][a-z0-9_]*$"#, kindLabel: "function"
            )
        ],
        extraPatternRules: [
            PatternRuleSpec(
                id: "shell-unquoted-variable", pattern: #"\s\$[A-Za-z_]\w*\s"#,
                message: "Unquoted variable expansion can split on whitespace or glob; wrap it in quotes."
            ),
            PatternRuleSpec(
                id: "shell-eval-usage", pattern: #"\beval\b"#,
                message: "eval executes a constructed string as code; avoid it where possible."
            ),
            PatternRuleSpec(
                id: "shell-debug-trace", pattern: #"^\s*set\s+-[a-wyz]*x"#,
                message: "set -x debug tracing left on."
            )
        ]
    )

    private static let powershell = LanguageProfile(
        lineCommentPrefixes: ["#"],
        functionStartPattern: #"^\s*function\s+[\w-]+"#,
        switchStartPattern: #"^\s*switch\s*\("#,
        switchBranchPattern: #"^\s*['"{$0-9A-Za-z*_]+\s*\{"#,
        importLinePattern: #"^\s*(Import-Module|using\s+(module|namespace))"#,
        namingRules: [
            NamingRule(
                declarationPattern: #"function\s+([A-Za-z][A-Za-z0-9-]*)"#,
                expectedIdentifierPattern: #"^[A-Z][A-Za-z0-9]*-[A-Z][A-Za-z0-9]*$"#, kindLabel: "function"
            )
        ],
        extraPatternRules: [
            PatternRuleSpec(
                id: "powershell-invoke-expression", pattern: #"(?i)\b(iex|Invoke-Expression)\b"#,
                message: "Invoke-Expression executes a constructed string as code; avoid it where possible."
            ),
            PatternRuleSpec(
                id: "powershell-plaintext-password", pattern: #"-AsPlainText\b"#,
                message: "Avoid converting or storing plaintext passwords; use secure credential handling instead."
            ),
            PatternRuleSpec(
                id: "powershell-debug-leftover",
                pattern: #"(?i:\bSet-PSDebug\s+-Trace\s+[12]\b|\$DebugPreference\s*=\s*['"]?Continue\b|"#
                    + #"\bWait-Debugger\b|\bSet-PSBreakpoint\b)|\bWrite-Host\s+["']\s*\[?(?:DEBUG|DBG)\b"#,
                message: "Debugging left on (Set-PSDebug -Trace, $DebugPreference, a breakpoint, or a DEBUG message)."
            )
        ]
    )

    private static let javascriptLike = LanguageProfile(
        lineCommentPrefixes: ["//"],
        functionStartPattern: #"\bfunction\b.*\{\s*$|=>\s*\{\s*$"#,
        switchStartPattern: #"^\s*switch\s*\("#,
        switchBranchPattern: #"^\s*case\s+.*:"#,
        importLinePattern: #"^\s*import\s|require\("#,
        namingRules: [
            NamingRule(
                declarationPattern: #"\bfunction\s+([A-Za-z_$][\w$]*)"#,
                expectedIdentifierPattern: #"^[a-z_$][\w$]*$"#, kindLabel: "function"
            ),
            NamingRule(
                declarationPattern: #"\bclass\s+([A-Za-z_$][\w$]*)"#,
                expectedIdentifierPattern: #"^[A-Z][\w$]*$"#, kindLabel: "class"
            )
        ],
        extraPatternRules: [
            PatternRuleSpec(
                id: "js-console-log", pattern: #"console\.log\(|\bdebugger\b"#,
                message: "Remove console.log/debugger before committing."
            ),
            PatternRuleSpec(
                id: "js-loose-equality", pattern: #"(?<![=!])==(?!=)|(?<![=!])!=(?!=)"#,
                message: "Use === / !== instead of == / != to avoid type coercion."
            ),
            PatternRuleSpec(
                id: "ts-ignore-without-reason", pattern: #"@ts-(ignore|nocheck|expect-error)\s*(\*/)?\s*$"#,
                message: "Type-check suppression with no reason given; explain it, or fix the type error."
            ),
            PatternRuleSpec(
                id: "ts-double-cast", pattern: #"\bas\s+unknown\s+as\b"#,
                message: "Casting through unknown defeats type checking."
            ),
            PatternRuleSpec(
                id: "js-var", pattern: #"^\s*(export\s+)?var\s"#,
                message: "Use let or const instead of var."
            ),
            PatternRuleSpec(
                id: "js-eval", pattern: #"\beval\s*\(|\bnew\s+Function\s*\("#,
                message: "eval/new Function runs arbitrary code."
            ),
            PatternRuleSpec(
                id: "js-raw-html",
                pattern: #"\.(inner|outer)HTML\s*=|\bdangerouslySetInnerHTML\b|insertAdjacentHTML\s*\("#,
                message: "Raw HTML injection risks XSS; set textContent or sanitize first."
            ),
            PatternRuleSpec(
                id: "js-shell-injection", pattern: #"\bexec(Sync)?\s*\(\s*`[^`]*\$\{"#,
                message: "Shell command built from a template string risks injection; use execFile with arguments."
            ),
            PatternRuleSpec(
                id: "skipped-test",
                pattern: #"\b(it|test|describe)\.(skip|only)\(|\bx(it|describe)\(|\bf(it|describe)\("#,
                message: "Skipped or focused test; .only/.skip shouldn't be committed."
            )
        ]
    )

    private static let swift = LanguageProfile(
        lineCommentPrefixes: ["//"],
        extraPatternRules: [
            PatternRuleSpec(
                id: "swift-unchecked-sendable", pattern: #"@unchecked\s+Sendable|nonisolated\(unsafe\)"#,
                message: "Opts out of data-race checking; prove it's safe, or use an actor or lock."
            ),
            PatternRuleSpec(
                id: "swift-debug-print", pattern: #"^\s*(print|debugPrint|dump|NSLog)\("#,
                message: "Remove debug output, or use a logger."
            ),
            PatternRuleSpec(
                id: "swift-discarded-try", pattern: #"^\s*(_\s*=\s*)?try\?\s"#,
                message: "try? discards the error here; handle or log it."
            ),
            PatternRuleSpec(
                id: "swift-main-sync", pattern: #"\bDispatchQueue\.main\.sync\b"#,
                message: "DispatchQueue.main.sync deadlocks when called from the main thread."
            ),
            PatternRuleSpec(
                id: "swift-semaphore-wait", pattern: #"\b\w*[Ss]emaphore\w*\.wait\("#,
                message: "Blocking on a semaphore can deadlock async code; use async/await."
            ),
            PatternRuleSpec(
                id: "skipped-test", pattern: #"\bXCTSkip|\.disabled\("#,
                message: "Skipped test; fix it or delete it."
            )
        ]
    )

    private static let cpp = LanguageProfile(
        lineCommentPrefixes: ["//"],
        functionStartPattern: #"^(?!\s*(if|for|while|switch|catch)\b).*\)\s*(const)?\s*\{\s*$"#,
        switchStartPattern: #"^\s*switch\s*\("#,
        switchBranchPattern: #"^\s*case\s+.*:"#,
        importLinePattern: #"^\s*#include\s*[<"]"#,
        namingRules: [
            NamingRule(
                declarationPattern: #"\bclass\s+([A-Za-z_]\w*)"#,
                expectedIdentifierPattern: #"^[A-Z]\w*$"#, kindLabel: "class"
            )
        ],
        extraPatternRules: [
            PatternRuleSpec(
                id: "cpp-raw-new-delete", pattern: #"\bnew\s+\w|\bdelete\b"#,
                message: "Raw new/delete risks leaks and double-frees; prefer smart pointers (unique_ptr/shared_ptr)."
            ),
            PatternRuleSpec(
                id: "cpp-using-namespace-std", pattern: #"^\s*using\s+namespace\s+std\s*;"#,
                message: "Avoid 'using namespace std;' at file scope; it pollutes the global namespace."
            ),
            PatternRuleSpec(id: "cpp-debug-print", pattern: CDebugOutput.cppPattern, message: CDebugOutput.message)
        ]
    )

    private static let c = LanguageProfile(
        lineCommentPrefixes: ["//"],
        functionStartPattern: #"^(?!\s*(if|for|while|switch)\b).*\)\s*\{\s*$"#,
        switchStartPattern: #"^\s*switch\s*\("#,
        switchBranchPattern: #"^\s*case\s+.*:"#,
        importLinePattern: #"^\s*#include\s*[<"]"#,
        extraPatternRules: [
            PatternRuleSpec(
                id: "c-gets-usage", pattern: #"\bgets\s*\("#,
                message: "gets() cannot bound its input and is a classic buffer-overflow vector; use fgets() instead."
            ),
            PatternRuleSpec(
                id: "c-unsafe-string-function", pattern: #"\b(strcpy|strcat|sprintf)\s*\("#,
                message: "Unbounded string function; prefer the bounded variant (strncpy/strncat/snprintf)."
            ),
            PatternRuleSpec(id: "c-debug-print", pattern: CDebugOutput.cPattern, message: CDebugOutput.message)
        ]
    )

    /// Objective-C: C's patterns, since it's a strict superset of C, plus methods, `#import`, and `@import` for
    /// the heuristic fallback, and `NSLog` as debug output.
    private static let objc = LanguageProfile(
        lineCommentPrefixes: ["//"],
        functionStartPattern: #"^(?!\s*(if|for|while|switch|@catch|@try|@finally|@synchronized|@autoreleasepool)\b)"#
            + #".*\)\s*\{\s*$|^\s*[-+]\s*\(.*\{\s*$"#,
        switchStartPattern: c.switchStartPattern, switchBranchPattern: c.switchBranchPattern,
        importLinePattern: #"^\s*(#\s*(include|import)\s*[<"]|@import\s)"#,
        namingRules: [
            NamingRule(
                declarationPattern: #"^\s*@(?:interface|implementation)\s+([A-Za-z_]\w*)"#,
                expectedIdentifierPattern: #"^_?[A-Z]\w*$"#, kindLabel: "class"
            )
        ],
        extraPatternRules: c.extraPatternRules + [
            PatternRuleSpec(
                id: "objc-debug-log", pattern: #"\bNSLog\s*\("#,
                message: "NSLog writes to the system log in release builds; remove it, or use os_log or a logger."
            ),
            PatternRuleSpec(
                id: "skipped-test", pattern: #"\bXCTSkip(If|Unless)?\b"#, message: "Skipped test; fix it or delete it."
            )
        ]
    )

    private static let java = LanguageProfile(
        lineCommentPrefixes: ["//"],
        functionStartPattern: #"^(?!\s*(if|for|while|switch|catch)\b).*\)\s*(throws\s+[\w,\s]+)?\s*\{\s*$"#,
        switchStartPattern: #"^\s*switch\s*\("#,
        switchBranchPattern: #"^\s*case\s+.*:"#,
        importLinePattern: #"^\s*import\s+"#,
        namingRules: [
            NamingRule(
                declarationPattern: #"\bclass\s+(\w+)"#, expectedIdentifierPattern: #"^[A-Z]\w*$"#, kindLabel: "class"
            )
        ],
        extraPatternRules: [
            PatternRuleSpec(
                id: "java-generic-exception-catch", pattern: #"catch\s*\(\s*(Exception|Throwable)\b"#,
                message: "Catching Exception/Throwable is overly broad; catch specific exception types instead."
            ),
            PatternRuleSpec(
                id: "java-system-out", pattern: #"\bSystem\.(out|err)\.print"#,
                message: "Remove debug output, or use a logger."
            ),
            PatternRuleSpec(
                id: "java-print-stack-trace", pattern: #"\.printStackTrace\(\)"#,
                message: "printStackTrace() writes to stderr silently; use a logger instead."
            ),
            PatternRuleSpec(
                id: "skipped-test", pattern: #"@(Disabled|Ignore)\b"#,
                message: "Skipped test; fix it or delete it."
            )
        ]
    )

    private static let go = LanguageProfile(
        lineCommentPrefixes: ["//"],
        functionStartPattern: #"^\s*func\s+"#,
        switchStartPattern: #"^\s*switch\b"#,
        switchBranchPattern: #"^\s*case\s+.*:"#,
        importLinePattern: #"^\s*import\s+"#,
        namingRules: [
            NamingRule(
                declarationPattern: #"func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)\s*\("#,
                expectedIdentifierPattern: #"^[A-Za-z][A-Za-z0-9]*$"#, kindLabel: "function"
            )
        ],
        extraPatternRules: [
            PatternRuleSpec(
                id: "go-discarded-return-value", pattern: #"^\s*_\s*=\s*\w+\("#,
                message: "Discarding a return value with _ may silently ignore an error; check it explicitly."
            ),
            PatternRuleSpec(
                id: "go-debug-print", pattern: #"^\s*fmt\.Print(ln|f)?\("#,
                message: "Remove debug output, or use the log package."
            ),
            PatternRuleSpec(
                id: "go-panic-usage", pattern: #"\bpanic\("#,
                message: "panic() crashes the program; prefer returning an error unless this is truly unrecoverable."
            ),
            PatternRuleSpec(
                id: "go-shell-injection", pattern: #"\bexec\.Command(Context)?\([^)]*\"(sh|bash)\"\s*,\s*\"-c\""#,
                message: "Running a shell command string risks injection; call the program directly."
            ),
            PatternRuleSpec(
                id: "skipped-test", pattern: #"\bt\.Skip(f|Now)?\("#,
                message: "Skipped test; fix it or delete it."
            )
        ]
    )

    private static let sql = LanguageProfile(
        lineCommentPrefixes: ["--"],
        functionStartPattern: #"(?i)^\s*CREATE\s+(OR\s+REPLACE\s+)?(FUNCTION|PROCEDURE)\s+"#,
        switchStartPattern: #"(?i)^\s*CASE\b"#,
        switchBranchPattern: #"(?i)^\s*WHEN\b"#,
        extraPatternRules: [
            PatternRuleSpec(
                id: "sql-select-star", pattern: #"(?i)select\s+\*\s+from"#,
                message: "SELECT * is fragile against schema changes; list the needed columns explicitly."
            ),
            PatternRuleSpec(
                id: "sql-missing-where", pattern: #"(?i)^\s*(UPDATE|DELETE\s+FROM)(?:(?!\bWHERE\b).)*;\s*$"#,
                message: "UPDATE/DELETE without a WHERE clause affects every row; confirm this is intentional."
            )
        ]
    )
}

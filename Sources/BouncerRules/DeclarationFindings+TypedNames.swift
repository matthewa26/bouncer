import Foundation
import BouncerCore

/// Naming rules that read a name's length or its declared type: `long-identifier`,
/// `boolean-name-prefix`, and `type-in-name`.
extension DeclarationFindings {
    static let defaultBooleanPrefixes = [
        "is", "are", "has", "have", "had", "should", "can", "could", "will", "would", "did", "does", "do",
        "was", "were", "needs", "must", "may", "allows", "supports", "uses", "shows", "wants", "contains",
        "includes", "requires", "accepts", "enables", "prefers", "expects", "matches", "in", "at", "on"
    ]
    private static let testNamePattern = "^(test|Test|Benchmark|Example|Fuzz)"
    /// Verbs that make a name a yes/no question wherever they appear, as in `tokenIsMissing`.
    private static let questionVerbs: Set<String> = [
        "is", "are", "has", "have", "was", "were", "can", "should", "did", "does", "will", "needs", "must"
    ]
    /// The type words `type-in-name` checks by default. `String`/`Str` aren't among them: names like
    /// `lineNumberString` usually mean "the string form of" a non-string value, not a restated type.
    static let defaultTypeSuffixes = [
        "List", "Array", "Dict", "Dictionary", "Map", "Set", "Bool", "Boolean", "Int", "Integer", "Double", "Float"
    ]

    /// Runs every naming rule that reads a name's length or type.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including each rule's resolved settings.
    /// - Returns: The combined findings.
    static func typedNameFindings(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        longIdentifiers(summary, file: file, context: context)
            + booleanNamePrefixes(summary, file: file, context: context)
            + typesInNames(summary, file: file, context: context)
    }

    /// Flags every declared name longer than `maxLength`: variables, properties, parameters,
    /// functions (except tests, whose names describe behavior), and types.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's resolved settings.
    /// - Returns: One finding per over-long name, once per name and line.
    private static func longIdentifiers(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "long-identifier")
        guard settings.enabled else { return [] }
        let maxLength = settings.parameters.int("maxLength", default: 50)
        return identifierSites(summary).filter { $0.name.count > maxLength }.map {
            let message = "Name \"\($0.name)\" is \($0.name.count) characters, over the \(maxLength) limit."
            return finding("long-identifier", $0.line, message, settings.severity, file)
        }
    }

    /// Lists every declared name with its line, once per name and line: typed names, non-test function
    /// names, and type names.
    ///
    /// - Parameter summary: The declarations collected from the file's syntax tree.
    /// - Returns: The names, in that order.
    private static func identifierSites(_ summary: DeclarationSummary) -> [CollectedName] {
        let functions = summary.functions.filter {
            $0.name != CollectedFunction.anonymousName
                && $0.name.range(of: testNamePattern, options: .regularExpression) == nil
        }
        let sites = summary.shapes.typedNames + functions.map { CollectedName(name: $0.name, line: $0.startLine) }
            + summary.shapes.types.map { CollectedName(name: $0.name, line: $0.startLine) }
        var seen = Set<String>()
        return sites.filter { seen.insert("\($0.line) \($0.name)").inserted }
    }

    /// Flags boolean variables and properties (and, with `includeParameters`, parameters) whose names
    /// don't start with a yes/no prefix; off unless configured, and skipped for Go, whose style differs.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's `prefixes` and `includeParameters` parameters.
    /// - Returns: One finding per badly named boolean.
    private static func booleanNamePrefixes(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        guard let settings = context.ruleSettings["boolean-name-prefix"], settings.enabled, file.language != .go
        else { return [] }
        let prefixes = settings.parameters.stringList("prefixes", default: defaultBooleanPrefixes)
        let includeParameters = settings.parameters.bool("includeParameters", default: false)
        let checked = summary.shapes.typedNames.filter { includeParameters || !$0.isParameter }
        return checked.filter { isUnquestioningBoolean($0, prefixes: prefixes) }.map {
            let message = "Boolean \"\($0.name)\" doesn't read as a yes/no question; start it with is, has, or should."
            return finding("boolean-name-prefix", $0.line, message, settings.severity, file)
        }
    }

    /// Reports whether a name is a boolean's that doesn't read as a yes/no question.
    ///
    /// - Parameters:
    ///   - name: The typed name.
    ///   - prefixes: The allowed prefixes.
    /// - Returns: Whether it's typed boolean and badly named.
    private static func isUnquestioningBoolean(_ name: CollectedName, prefixes: [String]) -> Bool {
        TypeWords.categories(of: name.typeName) == [.boolean] && !reads(asQuestion: name.name, prefixes: prefixes)
    }

    /// Reports whether a boolean's name reads as a yes/no question: its first word is one of the
    /// prefixes or a third-person verb (`startsWithNewline`), or a later word is a verb like `is`
    /// (`tokenIsMissing`). Constants (`ALL_CAPS`) and `ok` are left alone.
    ///
    /// - Parameters:
    ///   - name: The boolean's name.
    ///   - prefixes: The allowed prefixes.
    /// - Returns: Whether the name is acceptable.
    private static func reads(asQuestion name: String, prefixes: [String]) -> Bool {
        let words = TypeWords.words(of: name)
        guard let first = words.first, name != "ok", name.contains(where: \.isLowercase) else { return true }
        let isThirdPerson = first.count > 3 && first.hasSuffix("s") && !first.hasSuffix("ss")
        return prefixes.map { $0.lowercased() }.contains(first) || isThirdPerson
            || words.dropFirst().contains { questionVerbs.contains($0) }
    }

    /// Flags names whose last word restates their declared or literal type, such as `userList: [User]`;
    /// constants (`ALL_CAPS`) are left alone.
    ///
    /// - Parameters:
    ///   - summary: The declarations collected from the file's syntax tree.
    ///   - file: The file being analyzed.
    ///   - context: Repo-wide state, including this rule's `suffixes` parameter.
    /// - Returns: One finding per name whose type-word suffix matches its type.
    private static func typesInNames(
        _ summary: DeclarationSummary, file: SourceFile, context: AnalysisContext
    ) -> [Finding] {
        let settings = context.settings(for: "type-in-name")
        guard settings.enabled else { return [] }
        let allowed = settings.parameters.stringList("suffixes", default: defaultTypeSuffixes)
        return summary.shapes.typedNames.compactMap { name in
            guard let word = restatedTypeWord(of: name, allowed: allowed) else { return nil }
            let message = "Name \"\(name.name)\" restates its type with \"\(word)\"; name what it holds instead."
            return finding("type-in-name", name.line, message, settings.severity, file)
        }
    }

    /// Finds the type word a name ends in when it matches the name's type, as `List` in `userList: [User]`.
    ///
    /// - Parameters:
    ///   - name: The typed name.
    ///   - allowed: The type words to check, in any case.
    /// - Returns: The suffix as written, or `nil` if the name doesn't restate its type or is a constant.
    private static func restatedTypeWord(of name: CollectedName, allowed: [String]) -> String? {
        guard name.name.contains(where: \.isLowercase), let suffix = TypeWords.typeSuffix(of: name.name),
              allowed.contains(where: { $0.caseInsensitiveCompare(suffix.word) == .orderedSame }) else { return nil }
        return TypeWords.categories(of: name.typeName).contains(suffix.category) ? suffix.word : nil
    }
}

import Foundation
import BouncerCore

/// Flags a TypeScript `enum` that a union of string literals could replace: a plain (not `const` or `declare`) enum
/// whose members are all string literals, or all implicitly numbered.
///
/// Opt-in, since it's a style preference: a union such as `type Mode = 'read' | 'write'` erases at compile time,
/// needs no import to use a value, and narrows like any other literal type, while an enum emits a runtime object.
/// An enum with an explicit numeric or computed member (often bit flags), one merged with a `namespace` of the same
/// name (enum methods), and one iterated with `Object.keys`/`values`/`entries` (which needs the runtime object) is
/// left alone, as are declaration (`.d.ts`) files, which describe an existing API.
public struct PreferUnionTypeRule: Rule {
    public static let ruleID = "ts-prefer-union-type"
    public let id = PreferUnionTypeRule.ruleID
    private static let enumStart = TextMatching.regex(
        #"^\s*(?:export\s+)?(?:default\s+)?enum\s+([A-Za-z_$][\w$]*)\s*\{"#
    )
    private static let member = TextMatching.regex(
        #"^\s*(?:[A-Za-z_$][\w$]*|'[^']*'|"[^"]*")\s*(?:=\s*(?:'[^'\\]*'|"[^"\\]*"|`[^`$\\]*`))?\s*$"#
    )
    private static let stringMember = TextMatching.regex(#"=\s*['"`]"#)

    /// Creates the rule.
    public init() {}

    /// Flags each enum that a string-literal union could replace.
    ///
    /// Runs only when `.bouncer` enables it explicitly.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's settings.
    /// - Returns: One finding per such enum, on its `enum` line.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        guard let settings = SourceText.optInSettings(id, context), file.language == .typescript,
              !file.path.lastPathComponent.hasSuffix(".d.ts") else { return [] }
        return SourceText.flagCodeLines(id, settings, file) { index in
            Self.replaceableEnum(at: index, in: file).map { name in
                "Enum \(name) only names constants; a union of string literals (type \(name) = 'a' | 'b') "
                    + "erases at compile time and needs no import to use."
            }
        }
    }

    /// Reads the enum a line declares, if a string-literal union could replace it.
    ///
    /// - Parameters:
    ///   - index: The line's 0-based index.
    ///   - file: The file it's in.
    /// - Returns: The enum's name, or `nil` if the line declares no such enum.
    private static func replaceableEnum(at index: Int, in file: SourceFile) -> String? {
        let code = SourceText.code(of: file.lines[index])
        guard let name = TextMatching.captures(enumStart, code).first?[1] else { return nil }
        let end = SourceText.blockEnd(from: index, in: file)
        let members = Self.members(of: file.lines[index...end].joined(separator: "\n"))
        guard let members, namesConstants(members) else { return nil }
        return needsRuntimeObject(name, in: file.contents) ? nil : name
    }

    /// Reports whether an enum's members only name constants: all bare (implicitly numbered), or all initialized
    /// with string literals.
    ///
    /// - Parameter members: The members' source text.
    /// - Returns: Whether a string-literal union could list them.
    private static func namesConstants(_ members: [String]) -> Bool {
        guard !members.isEmpty, members.allSatisfy({ TextMatching.matches(member, $0) }) else { return false }
        let strings = members.filter { TextMatching.matches(stringMember, $0) }.count
        return strings == 0 || strings == members.count
    }

    /// Splits an enum's text into its members.
    ///
    /// - Parameter text: The enum, from its `enum` keyword through its closing brace.
    /// - Returns: The members' source text, with comments removed, or `nil` if the braces can't be found.
    private static func members(of text: String) -> [String]? {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else {
            return nil
        }
        let body = text[text.index(after: open)..<close].split(separator: "\n").map { line in
            line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? String(line)
        }.joined(separator: "\n")
        let withoutBlocks = body.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        return withoutBlocks.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Reports whether the file needs the enum as a runtime object: a `namespace` merged into it, or
    /// iteration over its keys or values.
    ///
    /// - Parameters:
    ///   - name: The enum's name.
    ///   - contents: The file's text.
    /// - Returns: Whether a union couldn't replace it as is.
    private static func needsRuntimeObject(_ name: String, in contents: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\bnamespace\s+"# + escaped + #"\b|\bObject\.(?:keys|values|entries)\(\s*"# + escaped + #"\b"#
            + #"|\bin\s+"# + escaped + #"\s*\)"#
        return TextMatching.matches(TextMatching.regex(pattern), contents)
    }
}

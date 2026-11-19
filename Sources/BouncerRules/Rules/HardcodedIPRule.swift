import Foundation
import BouncerCore

/// Flags an IPv4 address written into a string literal, such as `"10.0.4.12"` or `"https://52.1.2.3:8443/api"`.
///
/// Only quoted strings on code lines count, so comments and prose are left alone, and test, fixture, and mock files
/// are skipped. Addresses that are fixed by convention rather than deployment are skipped too: `0.x`, loopback
/// (`127.x`), link-local and cloud metadata (`169.254.x`), multicast, broadcast, and netmasks (`224.x` and up), and
/// the documentation ranges (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`). A line mentioning `version` is skipped, as
/// are dotted numbers with leading zeros, since both are usually version strings. Private ranges (`10.x`,
/// `172.16-31.x`, `192.168.x`) are still flagged: they're hardcoded deployment details all the same. IPv6 isn't
/// checked, since `::`-shaped text is too common in code to match reliably.
public struct HardcodedIPRule: Rule {
    public static let ruleID = "hardcoded-ip"
    public let id = HardcodedIPRule.ruleID
    private let profile: LanguageProfile
    private static let stringLiteral = TextMatching.regex(#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`"#)
    private static let address = TextMatching.regex(#"(?<![\w.:-])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\w.])"#)
    private static let documentationPrefixes = ["192.0.2.", "198.51.100.", "203.0.113.", "169.254."]
    private static let maxOctet = 255
    /// `127.x` is loopback; `0.x` ("this network", and `0.0.0.0` for any address) is skipped too.
    private static let loopbackFirstOctet = 127
    /// Where multicast begins; everything from here up (multicast, reserved, broadcast, netmasks) is skipped.
    private static let multicastStart = 224

    /// Creates the rule for one language.
    ///
    /// - Parameter profile: The language's profile, for its comment syntax.
    public init(profile: LanguageProfile) {
        self.profile = profile
    }

    /// Flags each code line with a hardcoded IPv4 address in a string literal.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - context: Repo-wide state, including this rule's `allow` parameter (address prefixes to accept).
    /// - Returns: One finding per flagged line, naming its first address.
    public func evaluate(file: SourceFile, context: AnalysisContext) -> [Finding] {
        let settings = context.settings(for: id)
        guard settings.enabled, !TextMatching.isTestPath(file.path),
              let syntax = CommentSyntax(language: file.language, profile: profile) else { return [] }
        let allowed = settings.parameters.stringList("allow", default: [])
        return Self.codeLines(of: file, syntax: syntax).compactMap { index in
            Self.address(in: file.lines[index], allowing: allowed).map { finding($0, at: index, in: file, settings) }
        }
    }

    /// Builds the finding for a hardcoded address.
    ///
    /// - Parameters:
    ///   - ip: The address.
    ///   - index: Its line's 0-based index.
    ///   - file: The file it's in.
    ///   - settings: This rule's settings, for the severity.
    /// - Returns: The finding.
    private func finding(_ ip: String, at index: Int, in file: SourceFile, _ settings: RuleSettings) -> Finding {
        let message = "Hardcoded IP address \(ip); read it from configuration, or use a hostname."
        return Finding(ruleID: id, severity: settings.severity, filePath: file.path, line: index + 1, message: message)
    }

    /// Lists a file's code lines, leaving out blank and comment-only ones.
    ///
    /// - Parameters:
    ///   - file: The file to scan.
    ///   - syntax: Its comment syntax.
    /// - Returns: The 0-based indices of its code lines.
    private static func codeLines(of file: SourceFile, syntax: CommentSyntax) -> [Int] {
        CommentScanner.scan(file, syntax: syntax).enumerated().compactMap { index, kind in
            if case .code = kind { return index }
            return nil
        }
    }

    /// Finds the first address worth flagging inside a line's string literals.
    ///
    /// - Parameters:
    ///   - line: The code line.
    ///   - allowed: Address prefixes the configuration accepts.
    /// - Returns: The address, or `nil` if the line has none.
    static func address(in line: Substring, allowing allowed: [String]) -> String? {
        guard line.contains("."), line.range(of: "version", options: .caseInsensitive) == nil else { return nil }
        let strings = TextMatching.captures(stringLiteral, line).map { $0[0] }
        let candidates = strings.flatMap { literal in
            TextMatching.captures(address, literal).filter { !isVersionPath($0[0], in: literal) }
        }
        let flagged = candidates.first { match in
            isDeploymentAddress(match) && !allowed.contains { match[0].hasPrefix($0) }
        }
        return flagged?[0]
    }

    /// Reports whether an address's octets make it a real, deployment-specific address.
    ///
    /// - Parameter match: The whole match followed by its four octets.
    /// - Returns: Whether every octet is in range without leading zeros, and the address isn't a conventional one.
    private static func isDeploymentAddress(_ match: [String]) -> Bool {
        let octetText = match.dropFirst()
        guard octetText.allSatisfy({ $0.count == 1 || !$0.hasPrefix("0") }) else { return false }
        let octets = octetText.compactMap { Int($0) }
        guard octets.count == octetText.count, octets.allSatisfy({ $0 <= maxOctet }), let first = octets.first,
              first != 0, first != loopbackFirstOctet, first < multicastStart else { return false }
        return !documentationPrefixes.contains { match[0].hasPrefix($0) }
    }

    /// Reports whether an address follows a single `/`, as in `Chrome/1.2.3.4`, which is a product version, not a URL.
    ///
    /// - Parameters:
    ///   - address: The matched address.
    ///   - literal: The string literal it was found in.
    /// - Returns: Whether the address is a path component after a lone slash.
    private static func isVersionPath(_ address: String, in literal: String) -> Bool {
        guard let range = literal.range(of: address), range.lowerBound > literal.startIndex else { return false }
        let before = literal[..<range.lowerBound]
        return before.hasSuffix("/") && !before.hasSuffix("//")
    }
}

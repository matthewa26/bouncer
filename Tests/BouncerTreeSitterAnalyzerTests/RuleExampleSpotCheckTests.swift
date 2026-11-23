import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

/// Checks that the rule examples article's `before` code really trips its rule, and the `after` code doesn't,
/// for a spread of rules across the parse-tree languages.
final class RuleExampleSpotCheckTests: XCTestCase {
    private let specs: [String: (spec: TreeSitterLanguageSpec, path: String)] = [
        "typescript": (.typescript, "src/example.ts"), "javascript": (.javascript, "src/example.js"),
        "python": (.python, "app/example.py"), "go": (.go, "pkg/example.go"), "rust": (.rust, "src/example.rs"),
        "php": (.php, "src/Example.php"), "objc": (.objc, "Sources/Example.m")
    ]

    private let checkedRules = [
        "js-loose-equality", "js-var", "explicit-any", "nested-ternary", "magic-number", "else-after-return",
        "unsorted-imports", "duplicate-import", "trailing-whitespace", "consecutive-blank-lines", "insecure-http-url",
        "generic-error-message", "test-sleep", "file-name-mismatch", "python-bare-except", "python-debug-print",
        "resource-leak", "test-real-clock", "go-debug-print", "go-unwrapped-error", "rust-unwrap", "rust-debug-print",
        "php-debug-output", "php-loose-comparison", "objc-debug-log"
    ]

    private func reports(_ ruleID: String, in code: String, language: String) throws -> Bool {
        let (spec, defaultPath) = try XCTUnwrap(specs[language], "No parser for \(language)")
        let path = RuleExampleFixture.path(in: code) ?? defaultPath
        let url = URL(fileURLWithPath: "/repo/\(path)")
        let file = SourceFile(path: url, language: Language.from(fileExtension: url.pathExtension), contents: code)
        let context = AnalysisContext(
            repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: RuleExampleFixture.settings(enabling: ruleID)
        )
        return try TreeSitterAnalyzer(spec: spec).analyze(file: file, context: context).contains { $0.ruleID == ruleID }
    }

    func testExamplesTripTheirRuleOnlyBeforeTheFix() throws {
        let examples = try RuleExampleFixture.all()
        for ruleID in checkedRules {
            let example = try XCTUnwrap(examples[ruleID], "No example for \(ruleID)")
            XCTAssertTrue(try reports(ruleID, in: example.before, language: example.language), "\(ruleID) before")
            XCTAssertFalse(try reports(ruleID, in: example.after, language: example.language), "\(ruleID) after")
        }
    }
}

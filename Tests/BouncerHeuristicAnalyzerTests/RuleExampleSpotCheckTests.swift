import XCTest
import Foundation
import BouncerCore
@testable import BouncerHeuristicAnalyzer

/// Checks that the rule examples article's `before` code really trips its rule, and the `after` code doesn't,
/// for the heuristically analyzed languages and manifests.
final class RuleExampleSpotCheckTests: XCTestCase {
    private let paths: [String: String] = [
        "java": "src/Example.java", "c": "src/example.c", "cpp": "src/example.cpp", "bash": "scripts/example.sh",
        "powershell": "scripts/Example.ps1", "sql": "db/example.sql", "json": "package.json",
        "yaml": ".github/workflows/ci.yml"
    ]

    private let checkedRules = [
        "java-system-out", "java-generic-exception-catch", "unsafe-deserialization", "c-gets-usage",
        "cpp-raw-new-delete", "shell-unquoted-variable", "pipe-to-shell", "powershell-invoke-expression",
        "sql-select-star", "sql-missing-where", "unpinned-dependency", "unpinned-ci-action"
    ]

    private func reports(_ ruleID: String, in code: String, language: String) throws -> Bool {
        let url = URL(fileURLWithPath: "/repo/\(try XCTUnwrap(paths[language], "No path for \(language)"))")
        let detected = Language.from(fileExtension: url.pathExtension, contents: code)
        let file = SourceFile(path: url, language: detected, contents: code)
        let context = AnalysisContext(
            repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: RuleExampleFixture.settings(enabling: ruleID)
        )
        return try HeuristicAnalyzer(language: detected).analyze(file: file, context: context)
            .contains { $0.ruleID == ruleID }
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

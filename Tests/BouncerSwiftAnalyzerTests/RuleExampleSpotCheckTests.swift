import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

/// Checks that the rule examples article's Swift `before` code really trips its rule, and the `after` code
/// doesn't.
final class RuleExampleSpotCheckTests: XCTestCase {
    private let checkedRules = [
        "force-unwrap", "force-try", "force-cast", "data-class", "shared-mutable-state", "missing-documentation",
        "swift-debug-print", "swift-shell-injection", "unused-private-symbol"
    ]

    private func reports(_ ruleID: String, in code: String) throws -> Bool {
        let path = RuleExampleFixture.path(in: code) ?? "Sources/App/Example.swift"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(path)"), language: .swift, contents: code)
        let context = AnalysisContext(
            repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: RuleExampleFixture.settings(enabling: ruleID)
        )
        return try SwiftSyntaxAnalyzer().analyze(file: file, context: context).contains { $0.ruleID == ruleID }
    }

    func testExamplesTripTheirRuleOnlyBeforeTheFix() throws {
        let examples = try RuleExampleFixture.all()
        for ruleID in checkedRules {
            let example = try XCTUnwrap(examples[ruleID], "No example for \(ruleID)")
            XCTAssertEqual(example.language, "swift", ruleID)
            XCTAssertTrue(try reports(ruleID, in: example.before), "\(ruleID) before")
            XCTAssertFalse(try reports(ruleID, in: example.after), "\(ruleID) after")
        }
    }
}

import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class DeadCodeFindingsTests: XCTestCase {
    private let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.ts"), language: .typescript, contents: "")
    private let summary = DeclarationSummary(
        functions: [], types: [], switches: [], importCount: 0,
        unusedDeclarations: [
            UnusedDeclaration(kind: .parameter, name: "p", line: 3, detail: "f"),
            UnusedDeclaration(kind: .importBinding, name: "x", line: 1, detail: "import"),
            UnusedDeclaration(kind: .privateSymbol, name: "g", line: 2, detail: "Unexported function")
        ]
    )

    private func findings(_ settings: [String: RuleSettings]) -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        return DeclarationFindings.deadCodeFindings(summary, file: file, context: context)
    }

    func testPrivateSymbolAndImportRulesRunByDefaultButParameterRuleIsOptIn() {
        XCTAssertEqual(findings([:]).map(\.ruleID), ["unused-private-symbol", "unused-import"])
        XCTAssertEqual(findings([:]).map(\.message), [
            "Unexported function \"g\" is never used in this file.", "Import \"x\" is never used in this file."
        ])
    }

    func testHonorsEachRulesEnabledFlagAndSeverity() {
        let settings = [
            "unused-import": RuleSettings(enabled: false, severity: .warning, parameters: .empty),
            "unused-parameter": RuleSettings(enabled: true, severity: .error, parameters: .empty)
        ]
        let found = findings(settings)
        XCTAssertEqual(found.map(\.ruleID), ["unused-private-symbol", "unused-parameter"])
        XCTAssertEqual(found.last?.severity, .error)
        XCTAssertEqual(found.last?.message, "Parameter \"p\" of \"f\" is never used in its body.")
    }
}

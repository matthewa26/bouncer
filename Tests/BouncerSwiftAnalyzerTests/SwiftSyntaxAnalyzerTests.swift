import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftSyntaxAnalyzerTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    func testFlagsAForceUnwrap() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: "let x: Int? = 1\nprint(x!)\n")
        let findings = try SwiftSyntaxAnalyzer().analyze(file: file, context: context)
        XCTAssertTrue(findings.contains { $0.ruleID == "force-unwrap" && $0.line == 2 })
    }

    func testFlagsAPublicFunctionWithNoDocComment() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: "public func doThing() {\n    print(1)\n}\n")
        let findings = try SwiftSyntaxAnalyzer().analyze(file: file, context: context)
        XCTAssertTrue(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testDoesNotFlagADocumentedFunction() throws {
        let contents = "/// Does the thing.\npublic func doThing() {\n    print(1)\n}\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: contents)
        let findings = try SwiftSyntaxAnalyzer().analyze(file: file, context: context)
        XCTAssertFalse(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testDoesNotFlagAnUndocumentedInternalFunctionByDefault() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: "func doThing() {\n    print(1)\n}\n")
        let findings = try SwiftSyntaxAnalyzer().analyze(file: file, context: context)
        XCTAssertFalse(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testFlagsAnUndocumentedInternalFunctionWithScopeAll() throws {
        let allScope = RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: ["scope": .string("all")]))
        let allScopeContext = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: ["missing-documentation": allScope])
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: "func doThing() {\n    print(1)\n}\n")
        let findings = try SwiftSyntaxAnalyzer().analyze(file: file, context: allScopeContext)
        XCTAssertTrue(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testFlagsAHighComplexityFunction() throws {
        let strictSettings = RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: ["max": .int(1)]))
        let strictContext = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: ["cyclomatic-complexity": strictSettings])
        let contents = "func f(x: Int) {\n    if x > 0 {\n        if x > 1 {\n            print(x)\n        }\n    }\n}\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: contents)
        let findings = try SwiftSyntaxAnalyzer().analyze(file: file, context: strictContext)
        XCTAssertTrue(findings.contains { $0.ruleID == "cyclomatic-complexity" })
    }
}

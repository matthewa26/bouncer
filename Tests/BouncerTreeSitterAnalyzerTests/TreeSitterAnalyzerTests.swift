import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class TreeSitterAnalyzerTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    func testPythonFlagsAFunctionWithNoDocstring() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: "def do_thing():\n    pass\n")
        let findings = try TreeSitterAnalyzer(spec: .python).analyze(file: file, context: context)
        XCTAssertTrue(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testPythonDoesNotFlagAFunctionWithADocstring() throws {
        let contents = "def do_thing():\n    \"\"\"Does the thing.\"\"\"\n    pass\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: contents)
        let findings = try TreeSitterAnalyzer(spec: .python).analyze(file: file, context: context)
        XCTAssertFalse(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testPythonDoesNotFlagAnUnderscorePrefixedFunctionByDefault() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: "def _helper():\n    pass\n")
        let findings = try TreeSitterAnalyzer(spec: .python).analyze(file: file, context: context)
        XCTAssertFalse(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testGoDoesNotFlagAnUnexportedFunctionByDefault() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.go"), language: .go, contents: "package main\n\nfunc doThing() {\n}\n")
        let findings = try TreeSitterAnalyzer(spec: .go).analyze(file: file, context: context)
        XCTAssertFalse(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testPythonFlagsABadlyNamedClass() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: "class thing:\n    pass\n")
        let findings = try TreeSitterAnalyzer(spec: .python).analyze(file: file, context: context)
        XCTAssertTrue(findings.contains { $0.ruleID == "naming-convention" })
    }

    func testPythonFlagsAnOverBranchedMatchStatement() throws {
        let strictSettings = RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: ["maxBranches": .int(2)]))
        let strictContext = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: ["switch-on-type-smell": strictSettings])
        let contents = "def f(x):\n    match x:\n        case 1:\n            pass\n        case 2:\n            pass\n        case 3:\n            pass\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: contents)
        let findings = try TreeSitterAnalyzer(spec: .python).analyze(file: file, context: strictContext)
        XCTAssertTrue(findings.contains { $0.ruleID == "switch-on-type-smell" })
    }

    func testGoFlagsAFunctionWithNoPrecedingComment() throws {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.go"), language: .go, contents: "package main\n\nfunc DoThing() {\n}\n")
        let findings = try TreeSitterAnalyzer(spec: .go).analyze(file: file, context: context)
        XCTAssertTrue(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testGoDoesNotFlagAFunctionWithAnAdjacentComment() throws {
        let contents = "package main\n\n// DoThing does the thing.\nfunc DoThing() {\n}\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.go"), language: .go, contents: contents)
        let findings = try TreeSitterAnalyzer(spec: .go).analyze(file: file, context: context)
        XCTAssertFalse(findings.contains { $0.ruleID == "missing-documentation" })
    }

    func testGoFlagsHighCyclomaticComplexity() throws {
        let strictSettings = RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: ["max": .int(1)]))
        let strictContext = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: ["cyclomatic-complexity": strictSettings])
        let contents = "package main\n\nfunc f(x int) {\n    if x > 0 {\n        if x > 1 {\n            println(x)\n        }\n    }\n}\n"
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.go"), language: .go, contents: contents)
        let findings = try TreeSitterAnalyzer(spec: .go).analyze(file: file, context: strictContext)
        XCTAssertTrue(findings.contains { $0.ruleID == "cyclomatic-complexity" })
    }
}

import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class LanguageProfilesExtraRulesTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    private func findings(_ contents: String, path: String, language: Language) -> [Finding] {
        let profile = LanguageProfiles.profile(for: language)
        let rules = CustomRuleFactory.makeRules(from: profile.extraPatternRules)
        let file = SourceFile(path: URL(fileURLWithPath: path), language: language, contents: contents)
        return rules.flatMap { $0.evaluate(file: file, context: context) }
    }

    func testFlagsPowerShellInvokeExpressionAndPlaintextPassword() {
        let contents = "Invoke-Expression \"Get-Process\"\n$c = ConvertTo-SecureString \"x\" -AsPlainText\n"
        let ids = findings(contents, path: "/repo/a.ps1", language: .powershell).map(\.ruleID)
        XCTAssertTrue(ids.contains("powershell-invoke-expression"))
        XCTAssertTrue(ids.contains("powershell-plaintext-password"))
    }

    func testFlagsDebugPrintsInPythonGoAndJava() {
        XCTAssertEqual(findings("print(x)\n", path: "/repo/a.py", language: .python).map(\.ruleID), ["python-debug-print"])
        XCTAssertEqual(findings("\tfmt.Println(x)\n", path: "/repo/a.go", language: .go).map(\.ruleID), ["go-debug-print"])
        let java = findings("System.out.println(x);\n", path: "/repo/A.java", language: .java).map(\.ruleID)
        XCTAssertEqual(java, ["java-system-out"])
    }

    func testFlagsNSLogAndCsUnsafeCallsInObjectiveC() {
        let contents = "  NSLog(@\"x\");\n  strcpy(dst, src);\n  [logger log:@\"NSLog is fine in a string\"];\n"
        let ids = findings(contents, path: "/repo/a.m", language: .objc).map(\.ruleID)
        XCTAssertEqual(ids.filter { $0 == "objc-debug-log" }.count, 1)
        XCTAssertTrue(ids.contains("c-unsafe-string-function"))
    }

    func testLeavesAPythonProgramsOwnOutput() {
        let guarded = "def main():\n    print(\"done\")\n\nif __name__ == \"__main__\":\n    main()\n"
        XCTAssertEqual(findings(guarded, path: "/repo/scripts/gate.py", language: .python).map(\.ruleID), [])
        let shebang = "#!/usr/bin/env python3\nprint(\"done\")\n"
        XCTAssertEqual(findings(shebang, path: "/repo/scripts/gate", language: .python).map(\.ruleID), [])
        let module = "def load():\n    print(\"done\")\n# if __name__ == \"__main__\":\n"
        XCTAssertEqual(findings(module, path: "/repo/a.py", language: .python).map(\.ruleID), ["python-debug-print"])
    }

    func testFlagsGoDiscardedReturnValuesOfPackageAndMethodCalls() {
        let contents = "_ = os.Remove(path)\n\t_ = f.Close()\n_ = cleanup()\nerr := os.Remove(path)\n"
        let lines = findings(contents, path: "/repo/a.go", language: .go)
            .filter { $0.ruleID == "go-discarded-return-value" }.map(\.line)
        XCTAssertEqual(lines, [1, 2, 3])
    }

    func testRefusesASpecWhoseExemptionDoesNotCompile() {
        XCTAssertNil(PatternRule(spec: PatternRuleSpec(id: "x", pattern: "a", message: "m", exemptFilePattern: "(")))
    }

    func testFlagsCppRawNewAndUsingNamespaceStd() {
        let contents = "using namespace std;\nint* p = new int(5);\n"
        let ids = findings(contents, path: "/repo/a.cpp", language: .cpp).map(\.ruleID)
        XCTAssertTrue(ids.contains("cpp-using-namespace-std"))
        XCTAssertTrue(ids.contains("cpp-raw-new-delete"))
    }

    func testFlagsCUnsafeFunctions() {
        let contents = "gets(buf);\nstrcpy(buf, \"hi\");\n"
        let ids = findings(contents, path: "/repo/a.c", language: .c).map(\.ruleID)
        XCTAssertTrue(ids.contains("c-gets-usage"))
        XCTAssertTrue(ids.contains("c-unsafe-string-function"))
    }

    func testFlagsJavaGenericCatchAndPrintStackTrace() {
        let contents = "catch (Exception e) {\n    e.printStackTrace();\n}\n"
        let ids = findings(contents, path: "/repo/a.java", language: .java).map(\.ruleID)
        XCTAssertTrue(ids.contains("java-generic-exception-catch"))
        XCTAssertTrue(ids.contains("java-print-stack-trace"))
    }

    func testFlagsGoDiscardedReturnValueAndPanic() {
        let contents = "_ = doThing()\npanic(\"oops\")\n"
        let ids = findings(contents, path: "/repo/a.go", language: .go).map(\.ruleID)
        XCTAssertTrue(ids.contains("go-discarded-return-value"))
        XCTAssertTrue(ids.contains("go-panic-usage"))
    }

    func testFlagsSqlSelectStarAndMissingWhere() {
        let contents = "SELECT * FROM users;\nDELETE FROM users;\n"
        let ids = findings(contents, path: "/repo/a.sql", language: .sql).map(\.ruleID)
        XCTAssertTrue(ids.contains("sql-select-star"))
        XCTAssertTrue(ids.contains("sql-missing-where"))
    }

    func testDoesNotFlagSqlStatementsThatHaveAWhereClause() {
        let contents = "DELETE FROM users WHERE id = 5;\nUPDATE users SET active = 0 WHERE x = 1;\n"
        let ids = findings(contents, path: "/repo/a.sql", language: .sql).map(\.ruleID)
        XCTAssertFalse(ids.contains("sql-missing-where"))
    }
}

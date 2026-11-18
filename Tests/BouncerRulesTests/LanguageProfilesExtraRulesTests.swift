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

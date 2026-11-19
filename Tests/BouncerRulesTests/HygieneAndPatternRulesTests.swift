import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class HygieneAndPatternRulesTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    private func ids(_ contents: String, _ language: Language, path: String = "/repo/a") -> [String] {
        let file = SourceFile(path: URL(fileURLWithPath: path), language: language, contents: contents)
        return TextRules.make(profile: LanguageProfiles.profile(for: language))
            .flatMap { $0.evaluate(file: file, context: context) }.map(\.ruleID)
    }

    func testFlagsAMissingFinalNewlineButNotAnEmptyFile() {
        XCTAssertTrue(ids("let a = 1", .swift).contains("missing-final-newline"))
        XCTAssertFalse(ids("let a = 1\n", .swift).contains("missing-final-newline"))
        XCTAssertFalse(ids("", .swift).contains("missing-final-newline"))
    }

    func testFlagsCrlfOncePerFile() {
        XCTAssertEqual(ids("a\r\nb\r\n", .swift).filter { $0 == "crlf-line-endings" }.count, 1)
    }

    func testFlagsMixedIndentationButNotConsistentTabs() {
        XCTAssertTrue(ids("a\n\tb\n    c\n", .swift).contains("mixed-indentation"))
        XCTAssertFalse(ids("package main\n\tb\n\tc\n", .go).contains("mixed-indentation"))
    }

    func testFlagsEachRunOfTooManyBlankLines() {
        let found = ids("a\n\n\n\nb\n\n\nc\n", .swift).filter { $0 == "consecutive-blank-lines" }
        XCTAssertEqual(found.count, 1)
    }

    func testFlagsWeakCryptoDisabledTlsHttpAndSqlBuildingInAnyLanguage() {
        let contents = """
            const h = crypto.createHash("md5");
            const agent = new https.Agent({ rejectUnauthorized: false });
            fetch("http://api.example.org/users");
            db.query("SELECT * FROM users WHERE id = " + id);
            """
        let found = Set(ids(contents + "\n", .typescript))
        XCTAssertTrue(found.isSuperset(of: ["weak-crypto", "disabled-tls-verification", "insecure-http-url", "sql-string-building"]))
    }

    func testAllowsLocalHttpAndXmlNamespaces() {
        let contents = "a = \"http://localhost:3000\"\nb = \"http://www.w3.org/2000/svg\"\nc = \"http://dev.test/x\"\n"
        XCTAssertFalse(ids(contents, .typescript).contains("insecure-http-url"))
    }

    func testFlagsPythonEvalPickleAndShellTrue() {
        let contents = "eval(x)\npickle.loads(b)\nyaml.load(s)\nyaml.load(s, Loader=yaml.SafeLoader)\nsubprocess.run(c, shell=True)\n"
        let found = ids(contents, .python)
        XCTAssertEqual(found.filter { $0 == "python-unsafe-deserialization" }.count, 2)
        XCTAssertTrue(found.contains("python-eval-exec"))
        XCTAssertTrue(found.contains("python-shell-injection"))
    }

    func testFlagsSkippedAndFocusedTestsAcrossLanguages() {
        XCTAssertTrue(ids("it.only(\"x\", () => {});\n", .typescript).contains("skipped-test"))
        XCTAssertTrue(ids("@pytest.mark.skip\n", .python).contains("skipped-test"))
        XCTAssertTrue(ids("\tt.Skip(\"later\")\n", .go).contains("skipped-test"))
        XCTAssertTrue(ids("@Disabled\n", .java).contains("skipped-test"))
        XCTAssertTrue(ids("throw XCTSkip(\"x\")\n", .swift).contains("skipped-test"))
    }

    func testFlagsSwiftDeadlockPatternsAndShellTracing() {
        let swift = ids("DispatchQueue.main.sync { }\nsemaphore.wait()\n", .swift)
        XCTAssertTrue(swift.contains("swift-main-sync") && swift.contains("swift-semaphore-wait"))
        XCTAssertTrue(ids("set -eux\n", .bash).contains("shell-debug-trace"))
    }

    func testFlagsShellCommandsBuiltFromVariables() {
        XCTAssertTrue(ids("execSync(`rm -rf ${dir}`);\n", .javascript).contains("js-shell-injection"))
        XCTAssertTrue(ids("exec.Command(\"sh\", \"-c\", cmd)\n", .go).contains("go-shell-injection"))
    }
}

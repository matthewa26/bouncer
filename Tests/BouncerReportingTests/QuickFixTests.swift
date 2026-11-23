import XCTest
import BouncerCore
@testable import BouncerReporting

/// Builds a finding and asks for its fix.
///
/// - Parameters:
///   - ruleID: The finding's rule.
///   - line: Its 1-based line.
///   - lines: The file's lines.
///   - file: The file's name, which sets its language.
///   - message: The finding's message.
/// - Returns: The fix, if any.
func quickFix(
    _ ruleID: String, at line: Int, in lines: [String], file: String = "src/a.ts", message: String = ""
) -> QuickFix? {
    let finding = Finding(
        ruleID: ruleID, severity: .warning, filePath: URL(fileURLWithPath: "/repo/\(file)"), line: line, message: message
    )
    return QuickFixes.fix(for: finding, lines: lines)
}

final class QuickFixTests: XCTestCase {
    // MARK: Robustness

    func testNoFixerCrashesOnEmptyFilesOrLinesOutsideTheFile() {
        let files: [[String]] = [[], [""], ["let a = 1  "], ["(", ")", "\"", "dbg!(", "console.log(", "  ", "\t"]]
        for ruleID in QuickFixes.fixableRuleIDs {
            for lines in files {
                for line in [Int.min, -1, 0, lines.count + 1, Int.max] {
                    XCTAssertNil(quickFix(ruleID, at: line, in: lines, message: "More than 2 consecutive blank lines."))
                }
            }
        }
    }

    func testNoFixerCrashesOnOddLines() {
        let lines = ["(", ")", "\"", "'", "`", "dbg!(", "dbg!()", "console.log(", "  ", "\t", "==", "var", "import",
                     "except", "http://", "\\", "/*", "#", "})", "print(\"\\\")"]
        for ruleID in QuickFixes.fixableRuleIDs {
            for file in ["a.ts", "a.py", "a.swift", "a.go", "a.rs", "a.php", "A.java"] {
                for line in 1...lines.count {
                    _ = quickFix(ruleID, at: line, in: lines, file: file, message: "already imported on line 1")
                }
            }
        }
    }

    func testRulesWithoutAFixerGetNone() {
        XCTAssertNil(quickFix("long-function", at: 1, in: ["function f() {}"]))
        XCTAssertNil(quickFix("missing-final-newline", at: 1, in: ["let a = 1"]))
        XCTAssertNil(quickFix("crlf-line-endings", at: 1, in: ["let a = 1\r", ""]))
    }

    // MARK: trailing-whitespace

    func testTrailingWhitespaceIsStripped() {
        XCTAssertEqual(quickFix("trailing-whitespace", at: 2, in: ["a", "let total = 1; \t ", "b"]),
                       QuickFix(startLine: 2, removed: ["let total = 1; \t "], added: ["let total = 1;"]))
        XCTAssertEqual(quickFix("trailing-whitespace", at: 1, in: ["    "]),
                       QuickFix(startLine: 1, removed: ["    "], added: [""]))
    }

    func testTrailingWhitespaceSkipsALineThatNoLongerHasAny() {
        XCTAssertNil(quickFix("trailing-whitespace", at: 1, in: ["let total = 1;"]))
        XCTAssertNil(quickFix("trailing-whitespace", at: 1, in: ["let total = 1; \r"]))
    }

    // MARK: consecutive-blank-lines

    private let blankMessage = "More than 2 consecutive blank lines."

    func testConsecutiveBlankLinesKeepsTheLimit() {
        let lines = ["a", "", " ", "", "\t", "b"]
        XCTAssertEqual(quickFix("consecutive-blank-lines", at: 2, in: lines, message: blankMessage),
                       QuickFix(startLine: 4, removed: ["", "\t"], added: []))
    }

    func testConsecutiveBlankLinesNeedsTheStartOfALongRun() {
        let lines = ["a", "", "", "", "b"]
        XCTAssertNil(quickFix("consecutive-blank-lines", at: 3, in: lines, message: blankMessage), "Mid-run")
        XCTAssertNil(quickFix("consecutive-blank-lines", at: 1, in: lines, message: blankMessage), "Not blank")
        XCTAssertNil(quickFix("consecutive-blank-lines", at: 2, in: ["a", "", "", "b"], message: blankMessage))
        XCTAssertNil(quickFix("consecutive-blank-lines", at: 2, in: lines, message: "Too many blank lines."))
        XCTAssertEqual(quickFix("consecutive-blank-lines", at: 1, in: ["", "", "", "b"], message: blankMessage)?
            .removed, [""])
    }

    // MARK: duplicate-import

    private let duplicateMessage = "'x' is already imported on line 1; remove or merge this import."

    func testDuplicateImportRemovesAnIdenticalLine() {
        let lines = ["import { a } from \"x\";", "import { b } from \"y\";", "import { a } from \"x\";"]
        XCTAssertEqual(quickFix("duplicate-import", at: 3, in: lines, message: duplicateMessage),
                       QuickFix(startLine: 3, removed: ["import { a } from \"x\";"], added: []))
        XCTAssertEqual(quickFix("duplicate-import", at: 2, in: ["import os", "  import os"], file: "a.py",
                                message: "'os' is already imported on line 1; remove or merge this import.")?.startLine, 2)
    }

    func testDuplicateImportLeavesImportsThatNeedMerging() {
        let different = ["import { a } from \"x\";", "import { c } from \"x\";"]
        XCTAssertNil(quickFix("duplicate-import", at: 2, in: different, message: duplicateMessage))
        let multiLine = ["import {", "  a,", "} from \"x\";", "import {", "  a,", "} from \"x\";"]
        XCTAssertNil(quickFix("duplicate-import", at: 4, in: multiLine, message: duplicateMessage))
        XCTAssertNil(quickFix("duplicate-import", at: 1, in: ["import os"], file: "a.py", message: duplicateMessage))
        let outOfRange = "'x' is already imported on line 9; remove or merge this import."
        XCTAssertNil(quickFix("duplicate-import", at: 2, in: ["import a", "import a"], message: outOfRange))
        XCTAssertNil(quickFix("duplicate-import", at: 2, in: ["import a", "import a"], message: "Duplicate."))
    }

    // MARK: unsorted-imports

    func testUnsortedImportsSortsTypeScriptByGroupThenName() {
        let lines = ["import { z } from \"zod\";", "import express from \"express\";", "import { db } from \"./db\";",
                     "", "export const app = express();"]
        XCTAssertEqual(quickFix("unsorted-imports", at: 2, in: lines), QuickFix(
            startLine: 1, removed: Array(lines[0...2]),
            added: ["import express from \"express\";", "import { z } from \"zod\";", "import { db } from \"./db\";"]
        ))
    }

    func testUnsortedImportsSortsSwiftIgnoringAttributes() {
        let lines = ["// Header", "import UIKit", "@testable import App", "import Foundation", "", "final class A {}"]
        XCTAssertEqual(quickFix("unsorted-imports", at: 3, in: lines, file: "a.swift")?.added,
                       ["@testable import App", "import Foundation", "import UIKit"])
    }

    func testUnsortedImportsSortsPythonTheIsortWay() {
        let lines = ["from os import path", "import sys", "import json", "", "x = 1"]
        XCTAssertEqual(quickFix("unsorted-imports", at: 2, in: lines, file: "a.py")?.added,
                       ["import json", "import sys", "from os import path"])
    }

    func testUnsortedImportsLeavesBlocksItCantSortWhole() {
        let multiLine = ["import {", "  a,", "} from \"a\";", "import { z } from \"zod\";", "import b from \"b\";"]
        XCTAssertNil(quickFix("unsorted-imports", at: 5, in: multiLine), "The block continues a multi-line import")
        let sideEffect = ["import \"./polyfill\";", "import { z } from \"zod\";", "import b from \"b\";"]
        XCTAssertNil(quickFix("unsorted-imports", at: 3, in: sideEffect))
        XCTAssertNil(quickFix("unsorted-imports", at: 1, in: ["import a from \"a\";", "import b from \"b\";"]))
        XCTAssertNil(quickFix("unsorted-imports", at: 1, in: ["const a = 1;"]))
        XCTAssertNil(quickFix("unsorted-imports", at: 2, in: ["import \"b\"", "import \"a\""], file: "a.go"))
    }

    // MARK: js-loose-equality

    func testLooseEqualityBecomesStrict() {
        XCTAssertEqual(quickFix("js-loose-equality", at: 1, in: ["if (status == 200) {"])?.added, ["if (status === 200) {"])
        XCTAssertEqual(quickFix("js-loose-equality", at: 1, in: ["if (a != b) run(\"x == y\");"], file: "a.js")?.added,
                       ["if (a !== b) run(\"x == y\");"])
    }

    func testLooseEqualityLeavesAmbiguousLines() {
        XCTAssertNil(quickFix("js-loose-equality", at: 1, in: ["if (a == b && c != d) {"]), "Two operators")
        XCTAssertNil(quickFix("js-loose-equality", at: 1, in: ["if (value == null) {"]), "Matches undefined too")
        XCTAssertNil(quickFix("js-loose-equality", at: 1, in: ["if (value != undefined) {"]))
        XCTAssertNil(quickFix("js-loose-equality", at: 1, in: ["log(\"a == b\");"]), "Only inside a string")
        XCTAssertNil(quickFix("js-loose-equality", at: 1, in: ["if (a / 2 == b) {"]), "Could be a regex")
        XCTAssertNil(quickFix("js-loose-equality", at: 1, in: ["if (a === b) {"]), "Already strict")
        XCTAssertNil(quickFix("js-loose-equality", at: 1, in: ["if a == b:"], file: "a.py"))
        XCTAssertNil(quickFix("js-loose-equality", at: 1, in: ["const s = `a", "${b == c}`"]), "Open template")
    }

    // MARK: explicit-any

    func testExplicitAnyBecomesUnknown() {
        XCTAssertEqual(quickFix("explicit-any", at: 1, in: ["function parse(input: any) {"])?.added,
                       ["function parse(input: unknown) {"])
        XCTAssertEqual(quickFix("explicit-any", at: 1, in: ["let cache: any; // any value"])?.added,
                       ["let cache: unknown; // any value"])
    }

    func testExplicitAnyLeavesAmbiguousLines() {
        XCTAssertNil(quickFix("explicit-any", at: 1, in: ["function f(a: any, b: any) {"]), "Two")
        XCTAssertNil(quickFix("explicit-any", at: 1, in: ["const x = y as any;"]), "Not an annotation")
        XCTAssertNil(quickFix("explicit-any", at: 1, in: ["let x: string;"]), "Gone")
        XCTAssertNil(quickFix("explicit-any", at: 1, in: ["let x: any;"], file: "a.js"))
    }

    // MARK: python-bare-except

    func testBareExceptCatchesException() {
        XCTAssertEqual(quickFix("python-bare-except", at: 1, in: ["    except:  # noqa"], file: "a.py")?.added,
                       ["    except Exception:  # noqa"])
        XCTAssertNil(quickFix("python-bare-except", at: 1, in: ["    except ValueError:"], file: "a.py"))
        XCTAssertNil(quickFix("python-bare-except", at: 1, in: ["except:"], file: "a.ts"))
    }

    // MARK: insecure-http-url

    func testInsecureHTTPURLHasNoFix() {
        // Whether the server answers on https://, or the URL is an identifier, needs judgment.
        XCTAssertNil(quickFix("insecure-http-url", at: 1, in: ["const API = \"http://api.acme.io/v1\";"]))
        XCTAssertNil(quickFix("insecure-http-url", at: 1, in: ["  xmlns:cl=\"http://www.acme.io/ns\""], file: "a.xml"))
        XCTAssertNil(quickFix("insecure-http-url", at: 1, in: ["if (str_starts_with($p, 'http://')) {"], file: "a.php"))
    }

    // MARK: skipped-test

    func testFocusedTestIsUnfocused() {
        XCTAssertEqual(quickFix("skipped-test", at: 1, in: ["it.only(\"refunds\", () => {"], file: "a.test.ts")?.added,
                       ["it(\"refunds\", () => {"])
        XCTAssertEqual(quickFix("skipped-test", at: 1, in: ["  fdescribe(\"cart\", () => {"], file: "a.test.js")?
            .added, ["  describe(\"cart\", () => {"])
    }

    func testSkippedTestsAreLeftForAPerson() {
        XCTAssertNil(quickFix("skipped-test", at: 1, in: ["it.skip(\"refunds\", () => {"], file: "a.test.ts"))
        XCTAssertNil(quickFix("skipped-test", at: 1, in: ["xit(\"refunds\", () => {"], file: "a.test.ts"))
        XCTAssertNil(quickFix("skipped-test", at: 1, in: ["model.fit(data);"], file: "a.test.ts"), "Not a test")
        XCTAssertNil(quickFix("skipped-test", at: 1, in: ["it.only(\"a\", () => it.only(\"b\"))"], file: "a.test.ts"))
        XCTAssertNil(quickFix("skipped-test", at: 1, in: ["@unittest.skip"], file: "test_a.py"))
    }

    // MARK: js-var

    func testVarBecomesLet() {
        let lines = ["function f() {", "  var count = 0;", "  count += 1;", "  return count;", "}"]
        XCTAssertEqual(quickFix("js-var", at: 2, in: lines),
                       QuickFix(startLine: 2, removed: ["  var count = 0;"], added: ["  let count = 0;"]))
        XCTAssertEqual(quickFix("js-var", at: 1, in: ["export var total: number = 0;"])?.added,
                       ["export let total: number = 0;"])
    }

    func testVarStaysWhenBlockScopeCouldMatter() {
        let usedAfter = ["function f(items) {", "  if (items.length) {", "    var first = items[0];", "  }",
                         "  return first;", "}"]
        XCTAssertNil(quickFix("js-var", at: 3, in: usedAfter), "Used after its block")
        XCTAssertNil(quickFix("js-var", at: 3, in: ["function f() {", "  total = 1;", "  var total = 0;", "}"]),
                     "Used before its declaration")
        XCTAssertNil(quickFix("js-var", at: 1, in: ["var a = 1;", "var a = 2;"]), "Redeclared")
        XCTAssertNil(quickFix("js-var", at: 1, in: ["var total;"]), "No initializer")
        XCTAssertNil(quickFix("js-var", at: 1, in: ["var a = 1, b = 2;"]), "Two declarators")
        XCTAssertNil(quickFix("js-var", at: 1, in: ["let a = 1;"]), "Already let")
        XCTAssertNil(quickFix("js-var", at: 1, in: ["var a = 1"], file: "a.py"))
    }
}

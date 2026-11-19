import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class CommentedOutCodeRuleTests: XCTestCase {
    private func lines(
        _ contents: String, _ language: Language, settings: [String: RuleSettings] = [:]
    ) -> [Int] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a"), language: language, contents: contents)
        return CommentedOutCodeRule(profile: LanguageProfiles.profile(for: language))
            .evaluate(file: file, context: context).map(\.line)
    }

    private func minLines(_ value: Int) -> [String: RuleSettings] {
        let parameters = RuleParameters(values: ["minLines": .int(value)])
        return ["commented-out-code": RuleSettings(enabled: true, severity: .warning, parameters: parameters)]
    }

    // MARK: Positives

    func testFlagsCommentedOutSwiftOncePerRunAtItsFirstLine() {
        let contents = """
            func f() {
                // let total = compute(items)
                // print(total)
                return
            }

            """
        XCTAssertEqual(lines(contents, .swift), [2])
    }

    func testFlagsCommentedOutTypeScriptAndJavaScriptBlockComments() {
        XCTAssertEqual(lines("// const a = foo();\n// bar(a);\nexport {};\n", .typescript), [1])
        XCTAssertEqual(lines("/*\nvar x = 1;\nfoo(x);\n*/\nmodule.exports = {};\n", .javascript), [2])
        XCTAssertEqual(lines("/* var x = foo(bar); */\nbaz();\n", .javascript), [1], "a strong single-line block")
    }

    func testFlagsCommentedOutPythonShellGoCAndSql() {
        XCTAssertEqual(lines("# x = compute(y)\n# print(x)\nz = 1\n", .python), [1])
        XCTAssertEqual(lines("# if name == \"x\":\n#     return load(name)\n", .python), [1])
        XCTAssertEqual(lines("# export PATH=$PATH:/opt/bin\n# cd \"$DIR\" && make\necho hi\n", .bash), [1])
        XCTAssertEqual(lines("// fmt.Println(x)\n// return nil\n", .go), [1])
        XCTAssertEqual(lines("// #define DEBUG_ANALYZE\n// #define DEBUG_EXECUTE\nint x;\n", .c), [1])
        XCTAssertEqual(lines("-- SELECT * FROM users;\n-- DELETE FROM t;\n", .sql), [1])
        XCTAssertEqual(lines("<#\n$x = Get-Thing;\nWrite-Host $x;\n#>\n", .powershell), [2])
    }

    func testKeepsAWrappedCallInOneRun() {
        let contents = "    // fprintf(\n    //   stderr,\n    //   \"error: %s\\n\", message\n    // );\n"
        XCTAssertEqual(lines(contents, .c), [1])
    }

    func testFlagsALoneLineOnlyWhenItIsUnambiguousOrMinLinesIsOne() {
        XCTAssertEqual(lines("// let total = compute(items)\n", .swift), [1])
        XCTAssertEqual(lines("// print(x)\n", .swift), [])
        XCTAssertEqual(lines("// print(x)\n", .swift, settings: minLines(1)), [1])
        XCTAssertEqual(lines("// a = b\n// c = d\n", .swift, settings: minLines(3)), [])
    }

    // MARK: Skips

    func testSkipsDocComments() {
        XCTAssertEqual(lines("/// let x = compute()\n/// print(x)\nfunc f() {}\n", .swift), [])
        XCTAssertEqual(lines("//! foo(bar);\n//! baz();\n", .cpp), [])
        XCTAssertEqual(lines("/**\n * foo(bar);\n * baz();\n */\nfunction f() {}\n", .javascript), [])
    }

    func testSkipsHashLinesInsidePythonDocstrings() {
        let contents = "def f():\n    \"\"\"\n    # x = compute(y)\n    # print(x)\n    \"\"\"\n    return 1\n"
        XCTAssertEqual(lines(contents, .python), [])
    }

    func testSkipsLicenseHeaders() {
        let contents = "// Copyright (c) 2024 Example, Inc.\n// int x = 5;\n// y = x;\nlet z = 1\n"
        XCTAssertEqual(lines(contents, .swift), [])
        XCTAssertEqual(lines("/*\n * SPDX-License-Identifier: MIT\n * foo(bar);\n * baz();\n */\n", .c), [])
    }

    func testSkipsExamplesAfterALabelInsideFencesAndIndentedUnderProse() {
        XCTAssertEqual(lines("// Example:\n//\n//   let x = compute()\n//   print(x)\n", .swift), [])
        XCTAssertEqual(lines("// For example\n// let x = compute()\n// print(x)\n", .swift), [])
        XCTAssertEqual(lines("// ```\n// let x = compute()\n// print(x)\n// ```\n", .swift), [])
        let goDoc = "// Foo returns the value.\n//\n//\tx := Foo()\n//\tfmt.Println(x)\nfunc Foo() int { return 1 }\n"
        XCTAssertEqual(lines(goDoc, .go), [])
    }

    func testSkipsProseThatMentionsCode() {
        let contents = """
            // Return early if the cache is empty.
            // If load() fails, it means the cache is cold, so we retry.
            // del items[:] is faster than items.clear() here.
            let x = 1

            """
        XCTAssertEqual(lines(contents, .swift), [])
    }

    func testSkipsUrlsMarkersAndToolDirectives() {
        let swift = """
            // See https://example.com/a?b=c;
            // TODO: call(foo);
            // FIXME: x = y;
            // MARK: - Section {
            // swiftlint:disable:next force_cast
            // eslint-disable-next-line no-console
            // @ts-ignore
            // region Helpers {
            // endregion
            let x = 1

            """
        XCTAssertEqual(lines(swift, .swift), [])
        let python = "#!/usr/bin/env python\n# -*- coding: utf-8 -*-\n# type: ignore[attr-defined]\n# noqa: E501\nx = 1\n"
        XCTAssertEqual(lines(python, .python), [])
        XCTAssertEqual(lines("// CHECK: foo() {\n// CHECK-NEXT: bar();\n", .swift), [])
    }

    func testSkipsGoCgoPreamblesAndPolyglotBlocksAndUnknownLanguages() {
        let cgo = "// #include \"parser.c\"\n// #include \"scanner.c\"\nimport \"C\"\n"
        XCTAssertEqual(lines(cgo, .go), [])
        XCTAssertEqual(lines("<#'\nset -eu\nfoo=$(bar);\nexit 0;\n#>\n", .powershell), [])
        XCTAssertEqual(lines("# x = compute(y)\n# print(x)\n", .other("rb")), [])
    }

    func testRespectsDisabledSettings() {
        let off = ["commented-out-code": RuleSettings(enabled: false, severity: .warning, parameters: .empty)]
        XCTAssertEqual(lines("// a = b;\n// c = d;\n", .swift, settings: off), [])
    }

    func testIsRegisteredAsATextRule() {
        let ids = TextRules.make(profile: LanguageProfiles.profile(for: .swift)).map(\.id)
        XCTAssertTrue(ids.contains("commented-out-code"))
        XCTAssertTrue(ids.contains("redundant-comment"))
    }
}

final class RedundantCommentRuleTests: XCTestCase {
    private let enabled = [
        "redundant-comment": RuleSettings(enabled: true, severity: .warning, parameters: .empty)
    ]

    private func lines(_ contents: String, _ language: Language = .swift, enabled on: Bool = true) -> [Int] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: on ? enabled : [:])
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a"), language: language, contents: contents)
        return RedundantCommentRule(profile: LanguageProfiles.profile(for: language))
            .evaluate(file: file, context: context).map(\.line)
    }

    func testFlagsCommentsThatRestateTheNextLine() {
        XCTAssertEqual(lines("// increment counter\ncounter += 1\n"), [1])
        XCTAssertEqual(lines("// Set the name.\nself.name = name\n"), [1])
        XCTAssertEqual(lines("// return result\nreturn result\n"), [1])
        XCTAssertEqual(lines("// parse the user names\nlet userNames = parse(input)\n"), [1])
        XCTAssertEqual(lines("x = 1\n# return the text\nreturn text\n", .python), [2])
        XCTAssertEqual(lines("// Increment the prop score\nerrors[propA.index].score += 1;\n", .typescript), [1])
    }

    func testIsOptIn() {
        XCTAssertEqual(lines("// increment counter\ncounter += 1\n", enabled: false), [])
    }

    func testIgnoresCommentsThatAddInformation() {
        XCTAssertEqual(lines("// increment\ncounter += 1\n"), [], "needs two content words")
        XCTAssertEqual(lines("// increment counter to skip the header\ncounter += 1\n"), [])
        XCTAssertEqual(lines("// counter += 1 is safe\ncounter += 1\n"), [], "not plain prose")
    }

    func testIgnoresDocMultiLineAndTrailingComments() {
        XCTAssertEqual(lines("/// return result\nreturn result\n"), [])
        XCTAssertEqual(lines("// Why:\n// return result\nreturn result\n"), [])
        XCTAssertEqual(lines("/* return result */\nreturn result\n"), [])
        XCTAssertEqual(lines("let a = 1 // return result\nreturn result\n"), [])
    }

    func testIgnoresCommentsLabelingALargerConstruct() {
        XCTAssertEqual(lines("// parse the body\nlet body = parse(input, {\n    x\n})\n"), [])
        XCTAssertEqual(lines("// parse the body\nlet body = parser\n    .parse(input)\n"), [])
    }

    func testStemsAndSplitsIdentifiers() {
        XCTAssertEqual(RestatementWords.stem("increments"), "increment")
        XCTAssertEqual(RestatementWords.stem("parsed"), "pars")
        XCTAssertEqual(RestatementWords.stem("parsing"), "pars")
        XCTAssertTrue(RestatementWords.codeWords("let urlSession = URLSession()").isSuperset(of: ["url", "session"]))
    }
}

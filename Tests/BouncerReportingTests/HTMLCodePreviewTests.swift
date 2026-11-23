import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class HTMLCodePreviewTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func finding(_ rule: String, _ path: String, _ line: Int) -> Finding {
        Finding(ruleID: rule, severity: .warning, filePath: root.appendingPathComponent(path), line: line,
                message: "Message for \(rule).")
    }

    /// Numbered lines, `line 1` to `line count`, ending with a newline.
    private func numbered(_ count: Int) -> String {
        (1...count).map { "line \($0)" }.joined(separator: "\n") + "\n"
    }

    private func lookups(files: [String: String], rationale: [String: String] = [:],
                         examples: [String: RuleExample] = [:],
                         fix: @escaping @Sendable (Finding, [String]) -> QuickFix? = { _, _ in nil }) -> HTMLReportLookups {
        HTMLReportLookups(readFile: { files[$0.path] }, rationale: { rationale[$0] }, example: { examples[$0] },
                          fix: fix)
    }

    private func page(_ findings: [Finding], _ lookups: HTMLReportLookups) -> String {
        HTMLReporter(repoRoot: root, lookups: lookups)
            .report(AnalysisResult(findings: findings, coverage: nil), verbosity: .normal)
    }

    /// The JSON object in the page's `<script type="application/json">` element with this ID.
    private func json(_ page: String, id: String) throws -> [String: Any] {
        let start = try XCTUnwrap(page.range(of: "<script type=\"application/json\" id=\"\(id)\">"))
        let end = try XCTUnwrap(page.range(of: "</script>", range: start.upperBound..<page.endIndex))
        let json = Data(page[start.upperBound..<end.lowerBound].utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
    }

    /// The report data, with the separately embedded code previews under `source`.
    private func reportData(_ findings: [Finding], _ lookups: HTMLReportLookups) throws -> [String: Any] {
        let page = page(findings, lookups)
        var data = try json(page, id: "report-data")
        data["source"] = try json(page, id: "report-code")
        return data
    }

    /// The chunks embedded for the file at `index`, as `(firstLine, lines)`.
    private func chunks(_ data: [String: Any], file index: Int) throws -> [(Int, [String])]? {
        let source = try XCTUnwrap(data["source"] as? [String: Any])
        let code = try XCTUnwrap(source["code"] as? [Any])
        guard let chunks = code[index] as? [[Any]] else { return nil }
        return try chunks.map { (try XCTUnwrap($0[0] as? Int), try XCTUnwrap($0[1] as? [String])) }
    }

    func testPreviewWindowsMergePerFileAndLongLinesAreCutAndMarked() throws {
        var text = numbered(20).components(separatedBy: "\n")
        text[3] = String(repeating: "x", count: 300)
        let lookups = lookups(files: ["/repo/a.swift": text.joined(separator: "\r\n")])
        let data = try reportData([finding("r", "a.swift", 3), finding("r", "a.swift", 5),
                                   finding("r", "a.swift", 15)], lookups)
        let runs = try XCTUnwrap(chunks(data, file: 0))
        XCTAssertEqual(runs.map(\.0), [1, 13], "overlapping windows around lines 3 and 5 are stored once")
        XCTAssertEqual(runs[0].1.count, 7)
        XCTAssertEqual(runs[1].1, ["line 13", "line 14", "line 15", "line 16", "line 17"], "\\r is dropped")
        XCTAssertEqual(runs[0].1[3], String(repeating: "x", count: HTMLSourceExcerpts.maxLineLength) + "\u{0}")
        XCTAssertEqual((data["source"] as? [String: Any])?["context"] as? Int, HTMLSourceExcerpts.radius)
    }

    func testMergingJoinsOverlappingAndAdjacentWindowsOnly() {
        XCTAssertEqual(HTMLSourceExcerpts.merged([8...12, 1...3, 4...5, 2...4, 14...16]), [1...5, 8...12, 14...16])
        XCTAssertEqual(HTMLSourceExcerpts.window(around: 1, count: 3), 1...3)
        XCTAssertNil(HTMLSourceExcerpts.window(around: 0, count: 3))
    }

    func testAnUnreadableFileAndALinePastTheEndHaveNoPreview() throws {
        let lookups = lookups(files: ["/repo/short.swift": numbered(4)])
        let data = try reportData([finding("r", "binary.swift", 2), finding("r", "short.swift", 5),
                                   finding("r", "short.swift", 9)], lookups)
        XCTAssertEqual(data["files"] as? [String], ["binary.swift", "short.swift"])
        XCTAssertNil(try chunks(data, file: 0), "a file that can't be read as UTF-8 is null")
        XCTAssertNil(try chunks(data, file: 1), "lines past the end, including the empty one after the last newline")
        XCTAssertEqual((data["rows"] as? [[Any]])?.map(\.count), [5, 5, 5])
    }

    func testTheDefaultReaderSkipsFilesThatArentUTF8() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (text, binary) = (directory.appendingPathComponent("a.swift"), directory.appendingPathComponent("b.swift"))
        try Data("let a = 1\n".utf8).write(to: text)
        try Data([0xFF, 0xFE, 0x00, 0xC3]).write(to: binary)
        XCTAssertEqual(HTMLReportLookups().readFile(text), "let a = 1\n")
        XCTAssertNil(HTMLReportLookups().readFile(binary))
        XCTAssertNil(HTMLReportLookups().readFile(directory.appendingPathComponent("missing.swift")))
    }
}

extension HTMLCodePreviewTests {
    func testRationalesAndExamplesAreStoredPerRuleAndFixesPerRow() throws {
        let example = RuleExample(language: "swift", before: "let x = y!\n", after: "guard let x = y else { return }\n")
        let lookups = lookups(
            files: ["/repo/a.swift": "let a = b!\nlet c = 1\n"], rationale: ["force-unwrap": "Crashes on nil."],
            examples: ["force-unwrap": example, "long-lines": example],
            fix: { finding, lines in
                finding.ruleID == "force-unwrap"
                    ? QuickFix(startLine: finding.line, removed: [lines[finding.line - 1]], added: ["let a = b ?? 0"])
                    : nil
            })
        let data = try reportData([finding("force-unwrap", "a.swift", 1), finding("long-lines", "a.swift", 2),
                                   finding("todo", "a.swift", 2)], lookups)
        XCTAssertEqual(data["rules"] as? [String], ["force-unwrap", "long-lines", "todo"])
        let why = try XCTUnwrap(data["why"] as? [Any])
        XCTAssertEqual(why[0] as? String, "Crashes on nil.")
        XCTAssertTrue(why[1] is NSNull && why[2] is NSNull)
        let examples = try XCTUnwrap(data["examples"] as? [Any])
        XCTAssertEqual(examples[0] as? [String], ["swift", "let x = y!\n", "guard let x = y else { return }\n"])
        XCTAssertTrue(examples[2] is NSNull)
        let rows = try XCTUnwrap(data["rows"] as? [[Any]])
        XCTAssertEqual(rows.map(\.count), [6, 5, 5], "only a row with a fix carries the sixth element")
        let fix = try XCTUnwrap(rows[0][5] as? [Any])
        XCTAssertEqual(fix[0] as? Int, 1)
        XCTAssertEqual(fix[1] as? [String], ["let a = b!"])
        XCTAssertEqual(fix[2] as? [String], ["let a = b ?? 0"])
    }

    func testAQuickFixIsPreferredOverTheRulesExample() throws {
        let example = RuleExample(language: "ts", before: "a\n", after: "b\n")
        let lookups = lookups(files: ["/repo/a.swift": "let a = 1  \n"], examples: ["trailing": example],
                              fix: { _, _ in QuickFix(startLine: 1, removed: ["let a = 1  "], added: ["let a = 1"]) })
        let page = HTMLReporter(repoRoot: root, lookups: lookups)
            .report(AnalysisResult(findings: [finding("trailing", "a.swift", 1)], coverage: nil), verbosity: .normal)
        let data = try reportData([finding("trailing", "a.swift", 1)], lookups)
        let rows = try XCTUnwrap(data["rows"] as? [[Any]])
        XCTAssertEqual(rows[0].count, 6, "the fix is embedded even though the rule has an example")
        XCTAssertEqual((rows[0][5] as? [Any])?[1] as? [String], ["let a = 1  "], "trailing spaces survive")
        XCTAssertTrue(page.contains(#"rows[i][FIX] ? "fix" : examples[rows[i][2]] ? "example" : """#),
                      "the page shows the fix when there is one, and the example only otherwise")
        XCTAssertTrue(page.contains(#"replace(/ /g, "·").replace(/\t/g, "→")"#), "trailing whitespace is visible")
    }

    func testHostileCodeStaysTextInTheDataAndThePage() throws {
        let hostile = "</script><img src=x onerror=alert(1)>"
        let lookups = lookups(files: ["/repo/a.ts": "const a = 1;\n\(hostile)\n"], rationale: ["r": hostile],
                              examples: ["r": RuleExample(language: "ts", before: hostile, after: "<!--")])
        let page = HTMLReporter(repoRoot: root, lookups: lookups)
            .report(AnalysisResult(findings: [finding("r", "a.ts", 2)], coverage: nil), verbosity: .normal)
        XCTAssertEqual(page.components(separatedBy: "<script>").count, 2, "only the page's own script tag")
        XCTAssertFalse(page.contains("<img"))
        XCTAssertFalse(page.contains("<!--"))
        XCTAssertFalse(page.contains("innerHTML"), "the script builds every node from text")
        let data = try reportData([finding("r", "a.ts", 2)], lookups)
        XCTAssertEqual(try chunks(data, file: 0)?.first?.1, ["const a = 1;", hostile])
        XCTAssertEqual((data["why"] as? [String])?.first, hostile)
    }

    func testThePageWiresTheTooltipAndRowExpansionAccessibly() {
        let page = HTMLReporter(repoRoot: root).report(AnalysisResult(findings: [], coverage: nil), verbosity: .normal)
        for hook in ["id=\"why-tip\"", "id=\"why-texts\" hidden", "aria-describedby", "aria-expanded",
                     "addEventListener(\"focusin\"", "event.key !== \"Enter\" && event.key !== \" \"",
                     "position: fixed", "tr.detail", "@media (prefers-color-scheme: dark)"] {
            XCTAssertTrue(page.contains(hook), "missing \(hook)")
        }
    }

    func testCodePreviewsLiveInTheirOwnElementAndAreParsedOnlyOnFirstExpand() throws {
        let page = page([finding("r", "a.swift", 1)], lookups(files: ["/repo/a.swift": "let a = 1\n"]))
        let data = try json(page, id: "report-data")
        XCTAssertNil(data["code"], "the main data carries no code")
        XCTAssertNil(data["context"])
        XCTAssertNotNil(try json(page, id: "report-code")["code"])
        XCTAssertEqual(page.components(separatedBy: #"$("report-code")"#).count, 2, "read in exactly one place")
        XCTAssertTrue(page.contains(#"if (!source) source = JSON.parse($("report-code").textContent);"#),
                      "parsed once, on first use")
        XCTAssertFalse(page.contains(#"getElementById("report-code")"#), "not parsed with the data at load")
    }

    func testDataAndDocumentationFilesGetNoPreviewButKeepTheirFixes() throws {
        let paths = ["a.json", "b.JSONC", "c.md", "d.markdown", "e.mdx", "Package.lock", "f.po", "g.pot", "h.csv",
                     "i.tsv", "j.txt", "k.rst"]
        for path in paths {
            XCTAssertFalse(HTMLSourceExcerpts.showsPreview(of: root.appendingPathComponent(path)), path)
        }
        for path in ["package.json", "web/composer.json", "Package.JSON", "a.swift", "b.php", "Makefile"] {
            XCTAssertTrue(HTMLSourceExcerpts.showsPreview(of: root.appendingPathComponent(path)), path)
        }
        let text = "{\n  \"a\": 1  \n}\n"
        let lookups = lookups(files: ["/repo/data.json": text, "/repo/package.json": text, "/repo/composer.json": text],
                              fix: { _, _ in QuickFix(startLine: 2, removed: ["  \"a\": 1  "], added: ["  \"a\": 1"]) })
        let data = try reportData([finding("r", "data.json", 2), finding("r", "package.json", 2),
                                   finding("r", "composer.json", 2)], lookups)
        XCTAssertEqual(data["files"] as? [String], ["data.json", "package.json", "composer.json"])
        XCTAssertNil(try chunks(data, file: 0), "a data file's code isn't embedded")
        XCTAssertEqual(try chunks(data, file: 1)?.first?.1.count, 3, "package.json keeps its preview")
        XCTAssertEqual(try chunks(data, file: 2)?.first?.1.count, 3, "composer.json keeps its preview")
        XCTAssertEqual((data["rows"] as? [[Any]])?.map(\.count), [6, 6, 6], "every file keeps its quick fix")
    }
}

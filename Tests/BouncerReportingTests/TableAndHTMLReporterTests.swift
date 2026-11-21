import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class TableAndHTMLReporterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func finding(_ severity: Severity, _ rule: String, _ path: String, _ line: Int, _ message: String) -> Finding {
        Finding(ruleID: rule, severity: severity, filePath: root.appendingPathComponent(path), line: line, message: message)
    }

    private var result: AnalysisResult {
        AnalysisResult(findings: [
            finding(.warning, "long-lines", "Sources/b.swift", 9, "Line is too long."),
            finding(.error, "long-function", "Sources/a.swift", 3, "Too long | really"),
            finding(.info, "todo-density", "Sources/a.swift", 1, "Note")
        ], coverage: nil)
    }

    func testTableListsFindingsMostSevereFirstWithRelativePathsAndASummary() {
        let lines = TableReporter(repoRoot: root).report(result, verbosity: .normal).components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "| Severity | Rule          | Location          | Message            |")
        XCTAssertEqual(lines[1], "| -------- | ------------- | ----------------- | ------------------ |")
        XCTAssertTrue(lines[2].hasPrefix("| error    | long-function | Sources/a.swift:3 | Too long \\| really |"))
        XCTAssertTrue(lines[3].contains("| warning  |"))
        XCTAssertTrue(lines[4].contains("| info     |"))
        XCTAssertEqual(lines.last, "3 findings: 1 error, 1 warning, 1 info.")
    }

    func testTableCondensedAndEmptyResultsPrintOnlyTheSummary() {
        XCTAssertEqual(TableReporter(repoRoot: root).report(result, verbosity: .condensed),
                       "3 findings: 1 error, 1 warning, 1 info.")
        let empty = AnalysisResult(findings: [], coverage: CoverageReport(overallLineCoveragePercent: 81.25))
        XCTAssertEqual(TableReporter(repoRoot: root).report(empty, verbosity: .normal),
                       "No findings. Line coverage: 81.2%.")
    }

    func testHTMLEmbedsTheFindingsOnceInCompactForm() throws {
        let page = HTMLReporter(repoRoot: root).report(result, verbosity: .normal)
        XCTAssertTrue(page.hasPrefix("<!doctype html>"))
        XCTAssertTrue(page.contains("<title>Bouncer report: repo</title>"))
        XCTAssertTrue(page.contains("3 findings: 1 error, 1 warning, 1 info."))
        let data = try reportData(page)
        let files = try XCTUnwrap(data["files"] as? [String]), rules = try XCTUnwrap(data["rules"] as? [String])
        let severities = try XCTUnwrap(data["severities"] as? [String])
        let rows = try XCTUnwrap(data["rows"] as? [[Any]])
        let decoded = rows.map { row in
            "\(severities[row[3] as! Int]) \(rules[row[2] as! Int]) \(files[row[0] as! Int]):\(row[1]) \(row[4])"
        }
        XCTAssertEqual(decoded, ["error long-function Sources/a.swift:3 Too long | really",
                                 "warning long-lines Sources/b.swift:9 Line is too long.",
                                 "info todo-density Sources/a.swift:1 Note"], "most severe first, then path and line")
        XCTAssertEqual(files, ["Sources/b.swift", "Sources/a.swift"], "each file is written once")
        XCTAssertEqual(data["filePaths"] as? [String], ["/repo/Sources/b.swift", "/repo/Sources/a.swift"])
        XCTAssertEqual(data["key"] as? String, "/repo")
        XCTAssertNil(data["coverage"], "coverage is left out when it wasn't measured")
    }

    func testHTMLCarriesCoverageForTheJSONDownload() throws {
        let measured = AnalysisResult(findings: [], coverage: CoverageReport(overallLineCoveragePercent: 81.25))
        let data = try reportData(HTMLReporter(repoRoot: root).report(measured, verbosity: .normal))
        XCTAssertEqual(data["coverage"] as? Double, 81.25)
        XCTAssertEqual((data["rows"] as? [Any])?.count, 0)
    }

    func testHTMLDropsTheFullJSONCopyForAPreviewBuiltOnDemand() {
        let page = HTMLReporter(repoRoot: root).report(result, verbosity: .normal)
        XCTAssertFalse(page.contains("<pre id=\"json\">"), "no second, escaped copy of every finding")
        XCTAssertFalse(page.contains("&quot;ruleID&quot;"))
        XCTAssertTrue(page.contains("<pre id=\"json-preview\""))
        XCTAssertTrue(page.contains("new Blob(jsonParts(Infinity)"), "download builds the full document in the page")
    }

    func testHTMLRendersLazilyWithSortableHeadersAndARulePanel() {
        let page = HTMLReporter(repoRoot: root).report(result, verbosity: .normal)
        for hook in ["id=\"sentinel\"", "new IntersectionObserver", "id=\"rule-panel\"", "id=\"rule-list\"",
                     "id=\"copy-config\"", "id=\"show-all\"", "aria-sort=\"ascending\"", "class=\"arrow\"",
                     "<button class=\"sort\" data-key=\"location\">", "setTimeout(refresh, 200)",
                     "localStorage", "id=\"category-filter\" hidden"] {
            XCTAssertTrue(page.contains(hook), "missing \(hook)")
        }
    }

    func testHTMLKeepsFindingTextFromBecomingMarkupOrTemplate() throws {
        let hostile = AnalysisResult(findings: [
            finding(.error, "x", "a.swift", 1, "</script><script>alert(1)</script> <b>{{JSON}}</b> <!-- &amp;")
        ], coverage: nil)
        let page = HTMLReporter(repoRoot: root).report(hostile, verbosity: .normal)
        XCTAssertEqual(page.components(separatedBy: "<script>").count, 2, "only the page's own script tag")
        XCTAssertFalse(page.contains("<b>"))
        XCTAssertFalse(page.contains("<!-- &amp;"))
        XCTAssertTrue(page.contains("\\u003c\\/script\\u003e"), "the JSON data escapes < and >")
        XCTAssertTrue(page.contains("{{JSON}}"), "template-looking text stays as text")
        let rows = try XCTUnwrap(reportData(page)["rows"] as? [[Any]])
        XCTAssertEqual(rows.first?[4] as? String, "</script><script>alert(1)</script> <b>{{JSON}}</b> <!-- &amp;")
    }

    private func reportData(_ page: String) throws -> [String: Any] {
        let json = try XCTUnwrap(between(page, "<script type=\"application/json\" id=\"report-data\">", "</script>"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func between(_ text: String, _ start: String, _ end: String) -> String? {
        guard let from = text.range(of: start), let to = text.range(of: end, range: from.upperBound..<text.endIndex)
        else { return nil }
        return String(text[from.upperBound..<to.lowerBound])
    }
}

final class ReportLinkTests: XCTestCase {
    func testOutsideWSLGivesThePathAndFileURL() {
        let lines = ReportLink.lines(for: URL(fileURLWithPath: "/home/me/repo/report.html"), environment: [:])
        XCTAssertEqual(lines, ["Report written to /home/me/repo/report.html", "Open: file:///home/me/repo/report.html"])
    }

    func testInWSLOpensLinuxPathsThroughTheWslLocalhostShare() {
        let file = URL(fileURLWithPath: "/home/me/my repo/.bouncer-cache/report.html")
        let lines = ReportLink.lines(for: file, environment: ["WSL_DISTRO_NAME": "Ubuntu-24.04"])
        XCTAssertEqual(lines, [
            "Report written to /home/me/my repo/.bouncer-cache/report.html",
            "Open: file://wsl.localhost/Ubuntu-24.04/home/me/my%20repo/.bouncer-cache/report.html",
            #"Windows path: \\wsl.localhost\Ubuntu-24.04\home\me\my repo\.bouncer-cache\report.html"#
        ])
    }

    func testInWSLOpensMountedDrivesThroughTheirDriveURL() {
        let lines = ReportLink.lines(for: URL(fileURLWithPath: "/mnt/c/Users/Me/repo/report.html"),
                                     environment: ["WSL_DISTRO_NAME": "Ubuntu"])
        XCTAssertEqual(lines, ["Report written to /mnt/c/Users/Me/repo/report.html",
                               "Open: file:///C:/Users/Me/repo/report.html",
                               #"Windows path: C:\Users\Me\repo\report.html"#])
    }

    func testAnEmptyWSLDistroNameCountsAsOutsideWSL() {
        let lines = ReportLink.lines(for: URL(fileURLWithPath: "/home/me/report.html"),
                                     environment: ["WSL_DISTRO_NAME": ""])
        XCTAssertEqual(lines, ["Report written to /home/me/report.html", "Open: file:///home/me/report.html"])
    }

    func testInWSLMapsMountedDrivesBackToWindowsPaths() {
        let windows = ReportLink.windowsLocation(forLinuxPath: "/mnt/c/Users/Me/repo/report.html", distro: "Ubuntu")
        XCTAssertEqual(windows.path, #"C:\Users\Me\repo\report.html"#)
        XCTAssertEqual(windows.url, "file:///C:/Users/Me/repo/report.html")
    }
}

extension TableAndHTMLReporterTests {
    func testHTMLTagsMappedRulesWithTheirOWASPCategoryForTheFilter() throws {
        let tagged = AnalysisResult(findings: [
            finding(.warning, "long-lines", "a.swift", 1, "Long."),
            finding(.warning, "sql-string-building", "b.ts", 2, "SQL."),
            finding(.warning, "weak-crypto", "c.go", 3, "MD5.")
        ], coverage: nil)
        let data = try reportData(HTMLReporter(repoRoot: root).report(tagged, verbosity: .normal))
        let rules = try XCTUnwrap(data["rules"] as? [String])
        let owasp = try XCTUnwrap(data["owasp"] as? [Any])
        XCTAssertEqual(rules, ["long-lines", "sql-string-building", "weak-crypto"])
        XCTAssertTrue(owasp[0] is NSNull, "an unmapped rule is null")
        XCTAssertEqual(owasp[1] as? String, "A05:2025")
        XCTAssertEqual(owasp[2] as? String, "A04:2025")
        XCTAssertEqual(data["owaspTitles"] as? [String: String],
                       ["A05:2025": "Injection", "A04:2025": "Cryptographic Failures"])
    }

    func testHTMLLeavesOutOWASPDataWhenNoRuleIsMapped() throws {
        let data = try reportData(HTMLReporter(repoRoot: root).report(result, verbosity: .normal))
        XCTAssertNil(data["owasp"])
        XCTAssertNil(data["owaspTitles"])
    }
}

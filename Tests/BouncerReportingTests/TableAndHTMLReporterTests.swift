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

    func testHTMLHoldsTheRowsAndTheJSONReport() throws {
        let page = HTMLReporter(repoRoot: root).report(result, verbosity: .normal)
        XCTAssertTrue(page.hasPrefix("<!doctype html>"))
        XCTAssertTrue(page.contains("<title>Bouncer report: repo</title>"))
        XCTAssertTrue(page.contains("3 findings: 1 error, 1 warning, 1 info."))
        let rows = try XCTUnwrap(between(page, "<script type=\"application/json\" id=\"rows\">", "</script>"))
        let decoded = try JSONDecoder().decode([ReportRow].self, from: Data(rows.utf8))
        XCTAssertEqual(decoded.map(\.location), ["Sources/a.swift:3", "Sources/b.swift:9", "Sources/a.swift:1"])
        let json = try XCTUnwrap(between(page, "<pre id=\"json\">", "</pre>"))
        XCTAssertTrue(json.contains("&quot;ruleID&quot; : &quot;long-function&quot;"))
    }

    func testHTMLKeepsFindingTextFromBecomingMarkupOrTemplate() {
        let hostile = AnalysisResult(findings: [
            finding(.error, "x", "a.swift", 1, "</script><script>alert(1)</script> <b>{{JSON}}</b>")
        ], coverage: nil)
        let page = HTMLReporter(repoRoot: root).report(hostile, verbosity: .normal)
        XCTAssertEqual(page.components(separatedBy: "<script>").count, 2, "only the page's own script tag")
        XCTAssertFalse(page.contains("<b>"))
        XCTAssertTrue(page.contains("\\u003c\\/script\\u003e"), "the JSON data escapes < and >")
        XCTAssertTrue(page.contains("{{JSON}}"), "template-looking text stays as text")
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

    func testInWSLAddsTheWslLocalhostShareForLinuxPaths() {
        let file = URL(fileURLWithPath: "/home/me/my repo/.bouncer-cache/report.html")
        let lines = ReportLink.lines(for: file, environment: ["WSL_DISTRO_NAME": "Ubuntu-24.04"])
        XCTAssertEqual(lines[2], "From Windows: file://wsl.localhost/Ubuntu-24.04/home/me/my%20repo/.bouncer-cache/report.html")
        XCTAssertEqual(lines[3], #"Windows path: \\wsl.localhost\Ubuntu-24.04\home\me\my repo\.bouncer-cache\report.html"#)
    }

    func testInWSLMapsMountedDrivesBackToWindowsPaths() {
        let windows = ReportLink.windowsLocation(forLinuxPath: "/mnt/c/Users/Me/repo/report.html", distro: "Ubuntu")
        XCTAssertEqual(windows.path, #"C:\Users\Me\repo\report.html"#)
        XCTAssertEqual(windows.url, "file:///C:/Users/Me/repo/report.html")
    }
}

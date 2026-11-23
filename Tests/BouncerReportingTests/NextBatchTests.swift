import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class NextBatchRankingTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")
    private let costs: NextBatchRanking.CostLookup = { ["long-function": .refactor, "duplicate-block": .refactor][$0] }

    private func finding(_ rule: String, _ path: String, _ line: Int = 1, _ severity: Severity = .warning) -> Finding {
        Finding(ruleID: rule, severity: severity, filePath: root.appendingPathComponent(path), line: line, message: "m")
    }

    private func order(_ findings: [Finding], _ order: NextBatchRanking.Order, touched: [String] = []) -> [String] {
        let ranking = NextBatchRanking(order: order, touched: touched, cost: costs)
        return ranking.ranked(ranking.clusters(findings, repoRoot: root)).map { "\($0.path) \($0.ruleID)" }
    }

    func testQuickFixesFirstPutsEveryMechanicalFixBeforeAnyRefactor() {
        let findings = [
            finding("long-function", "A.swift", 1, .error), finding("force-unwrap", "B.swift", 1, .info),
            finding("magic-number", "C.swift", 1, .error), finding("duplicate-block", "D.swift", 1, .warning)
        ]
        XCTAssertEqual(order(findings, .quickFixesFirst), [
            "C.swift magic-number", "B.swift force-unwrap", "A.swift long-function", "D.swift duplicate-block"
        ])
    }

    func testSeverityFirstPutsErrorsFirstThenMechanicalWithinEach() {
        let findings = [
            finding("long-function", "A.swift", 1, .error), finding("force-unwrap", "B.swift", 1, .warning),
            finding("magic-number", "C.swift", 1, .error), finding("duplicate-block", "D.swift", 1, .warning)
        ]
        XCTAssertEqual(order(findings, .severityFirst), [
            "C.swift magic-number", "A.swift long-function", "B.swift force-unwrap", "D.swift duplicate-block"
        ])
    }

    func testAClusterTakesItsMostSevereFinding() {
        let findings = [finding("force-unwrap", "A.swift", 1, .info), finding("force-unwrap", "A.swift", 2, .error),
                        finding("magic-number", "B.swift", 1, .warning)]
        XCTAssertEqual(order(findings, .quickFixesFirst), ["A.swift force-unwrap", "B.swift magic-number"])
    }

    func testTiesGoToOWASPThenTouchedFilesThenLargerClustersThenPath() {
        let findings = [
            finding("force-unwrap", "A.swift"), finding("force-unwrap", "B.swift"), finding("force-unwrap", "B.swift", 2),
            finding("force-unwrap", "C.swift"), finding("force-unwrap", "D.swift"), finding("insecure-http-url", "E.swift")
        ]
        XCTAssertEqual(order(findings, .quickFixesFirst, touched: ["D.swift", "C.swift"]), [
            "E.swift insecure-http-url", "D.swift force-unwrap", "C.swift force-unwrap", "B.swift force-unwrap",
            "A.swift force-unwrap"
        ])
    }

    func testAnUntaggedRuleCountsAsMechanical() {
        let ranking = NextBatchRanking(order: .quickFixesFirst, cost: { _ in nil })
        let clusters = ranking.clusters([finding("my-custom-rule", "A.swift")], repoRoot: root)
        XCTAssertEqual(clusters.map(\.cost), [.mechanical])
    }

    func testPickCountsTheOtherClusters() {
        let ranking = NextBatchRanking(order: .quickFixesFirst, cost: costs)
        let findings = [finding("a", "A.swift"), finding("a", "A.swift", 3), finding("b", "A.swift"), finding("a", "B.swift")]
        let pick = ranking.pick(findings, repoRoot: root)
        XCTAssertEqual(pick?.cluster.path, "A.swift")
        XCTAssertEqual(pick?.cluster.findings.map(\.line), [1, 3])
        XCTAssertEqual(pick?.clustersLeft, 2)
        XCTAssertNil(ranking.pick([], repoRoot: root))
    }
}

final class NextBatchWriterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")
    private let source = NextBatchSource(lines: (1...30).map { "line \($0)" })

    private func pick(_ lines: [Int], rule: String = "force-unwrap", cost: FixCost = .mechanical) -> NextBatchPick {
        let findings = lines.map {
            Finding(ruleID: rule, severity: .warning, filePath: root.appendingPathComponent("A.swift"), line: $0,
                    message: "Unwrap it safely.")
        }
        return NextBatchPick(cluster: FindingCluster(path: "A.swift", findings: findings, cost: cost), clustersLeft: 37)
    }

    func testShowsAMergedWindowAroundEachFindingWithLineNumbers() {
        let text = NextBatchWriter(maxChars: 4_000).render(pick([5, 6, 20]), source: source)
        XCTAssertEqual(text, """
            A.swift · force-unwrap (mechanical, warning) · 3 findings · 37 clusters left
              5 Unwrap it safely.
              6
                4| line 4
                5| line 5
                6| line 6
                7| line 7
              20
                19| line 19
                20| line 20
                21| line 21
            Next: fix these, then call verify with files ["A.swift"]; then next_batch again.
            """)
    }

    func testARefactorShowsTheEnclosingDeclarationInsteadOfAWindow() {
        var lines = (1...30).map { "    body \($0)" }
        lines[2] = "    private func load(_ id: Int) -> Data {"
        let text = NextBatchWriter(maxChars: 4_000).render(
            pick([12], rule: "long-function", cost: .refactor), source: NextBatchSource(lines: lines)
        )
        XCTAssertTrue(text.contains("    3|     private func load(_ id: Int) -> Data {\n    ...\n    12|     body 12"), text)
        XCTAssertFalse(text.contains("11|"), text)
    }

    func testFindsDeclarationsAcrossLanguages() {
        for declaration in ["def run(self):", "pub(crate) fn run() {", "export function run() {", "- (void)run {",
                            "@MainActor public static func run()", "func (s *Server) Run() {"] {
            XCTAssertEqual(NextBatchSnippets.signatureLine(above: 2, in: [declaration, "  x"]), 1, declaration)
        }
        XCTAssertNil(NextBatchSnippets.signatureLine(above: 2, in: ["let value = 1", "return value"]))
    }

    func testACutClusterEndsWithWholeLinesAndSaysHowToGetTheRest() {
        let pick = pick(Array(stride(from: 2, through: 29, by: 3)))
        for maxChars in [260, 400, 500] {
            let text = NextBatchWriter(maxChars: maxChars).render(pick, source: source)
            XCTAssertLessThanOrEqual(text.count, maxChars, text)
            XCTAssertTrue(text.contains("more in this cluster: call findings with rule force-unwrap and path A.swift."))
            XCTAssertTrue(text.hasSuffix("then next_batch again."), text)
        }
    }

    func testAFileChangedSinceTheScanShowsNoCode() {
        let changed = NextBatchSource(lines: nil, changedSinceScan: true)
        let text = NextBatchWriter(maxChars: 4_000).render(pick([5]), source: changed)
        XCTAssertTrue(text.hasPrefix("A.swift · force-unwrap (mechanical, warning) · 1 finding · 37 clusters left "
                                     + "(changed since scan; verify it)\n  5 Unwrap it safely.\nNext:"), text)
    }

    func testReadsAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("next-batch-\(UUID()).swift")
        try "a\nb".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(NextBatchSource.read(url).lines, ["a", "b"])
        XCTAssertNil(NextBatchSource.read(url.appendingPathExtension("missing")).lines)
    }
}

final class NextBatchSourceTests: XCTestCase {
    func testReadsACRLFFileAsSeparateLines() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("crlf-\(UUID().uuidString).ts")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("let a = 1;\r\nlet b = 2;\r\n".utf8).write(to: url)
        XCTAssertEqual(NextBatchSource.read(url).lines, ["let a = 1;", "let b = 2;", ""])
    }
}

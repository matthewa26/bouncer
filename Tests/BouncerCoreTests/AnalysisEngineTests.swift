import XCTest
import Foundation
@testable import BouncerCore

/// A fixed file list, for engine tests that don't need git or a real filesystem.
private struct FakeFileProvider: TargetFileProvider {
    let files: [URL]
    func targetFiles() throws -> [URL] { files }
}

/// In-memory file contents, keyed by URL.
private struct FakeContentsProvider: FileContentsProvider {
    let contents: [URL: String]
    func contents(of url: URL) throws -> String { contents[url] ?? "" }
}

/// A `LanguageAnalyzer` that returns a fixed finding for every file it sees.
private struct FixedFindingAnalyzer: LanguageAnalyzer {
    let supportedLanguage: Language
    let line: Int
    func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
        [Finding(ruleID: "fake-rule", severity: .warning, filePath: file.path, line: line, message: "fake finding")]
    }
}

/// A `CoverageProvider` that always returns a fixed percentage.
private struct FixedCoverageProvider: CoverageProvider {
    let percent: Double
    func canParse(reportPath: URL) -> Bool { true }
    func parse(reportPath: URL) throws -> CoverageReport { CoverageReport(overallLineCoveragePercent: percent) }
}

final class AnalysisEngineTests: XCTestCase {
    func testCollectsFindingsFromEveryAnalyzedFile() throws {
        let repoRoot = URL(fileURLWithPath: "/repo")
        let fileURL = repoRoot.appendingPathComponent("a.swift")
        let engine = AnalysisEngine(
            fileProvider: FakeFileProvider(files: [fileURL]),
            contentsProvider: FakeContentsProvider(contents: [fileURL: "let x = 1\n"]),
            knownAnalyzers: [.swift: FixedFindingAnalyzer(supportedLanguage: .swift, line: 1)],
            fallbackAnalyzer: FixedFindingAnalyzer(supportedLanguage: .other(""), line: 1),
            context: AnalysisContext(repoRoot: repoRoot, ruleSettings: [:])
        )
        let result = try engine.run()
        XCTAssertEqual(result.findings.count, 1)
        XCTAssertEqual(result.findings.first?.ruleID, "fake-rule")
    }

    func testDropsFindingsABouncerCommentSuppresses() throws {
        let repoRoot = URL(fileURLWithPath: "/repo")
        let suppressed = repoRoot.appendingPathComponent("a.swift")
        let kept = repoRoot.appendingPathComponent("b.swift")
        let engine = AnalysisEngine(
            fileProvider: FakeFileProvider(files: [suppressed, kept]),
            contentsProvider: FakeContentsProvider(contents: [
                suppressed: "let x = 1 // bouncer:disable-line fake-rule -- known\n", kept: "let x = 1\n"
            ]),
            knownAnalyzers: [.swift: FixedFindingAnalyzer(supportedLanguage: .swift, line: 1)],
            fallbackAnalyzer: FixedFindingAnalyzer(supportedLanguage: .other(""), line: 1),
            context: AnalysisContext(repoRoot: repoRoot, ruleSettings: [:])
        )
        XCTAssertEqual(try engine.run().findings.map(\.filePath.lastPathComponent), ["b.swift"])
    }

    func testFiltersOutFindingsAlreadyInTheBaseline() throws {
        let repoRoot = URL(fileURLWithPath: "/repo")
        let fileURL = repoRoot.appendingPathComponent("a.swift")
        let fingerprint = Baseline.fingerprint(ruleID: "fake-rule", relativePath: "a.swift", lineContent: "let x = 1")
        let engine = AnalysisEngine(
            fileProvider: FakeFileProvider(files: [fileURL]),
            contentsProvider: FakeContentsProvider(contents: [fileURL: "let x = 1\n"]),
            knownAnalyzers: [.swift: FixedFindingAnalyzer(supportedLanguage: .swift, line: 1)],
            fallbackAnalyzer: FixedFindingAnalyzer(supportedLanguage: .other(""), line: 1),
            context: AnalysisContext(repoRoot: repoRoot, ruleSettings: [:]),
            baseline: Baseline(fingerprints: [fingerprint])
        )
        let result = try engine.run()
        XCTAssertTrue(result.findings.isEmpty)
    }

    func testReportsASyntheticFindingWhenCoverageIsBelowThreshold() throws {
        let repoRoot = URL(fileURLWithPath: "/repo")
        let engine = AnalysisEngine(
            fileProvider: FakeFileProvider(files: []),
            contentsProvider: FakeContentsProvider(contents: [:]),
            knownAnalyzers: [:],
            fallbackAnalyzer: FixedFindingAnalyzer(supportedLanguage: .other(""), line: 1),
            context: AnalysisContext(repoRoot: repoRoot, ruleSettings: [:]),
            coverage: .init(provider: FixedCoverageProvider(percent: 50), reportPath: repoRoot.appendingPathComponent("lcov.info"), threshold: 80)
        )
        let result = try engine.run()
        XCTAssertTrue(result.findings.contains { $0.ruleID == CoverageThresholdChecker.ruleID })
    }

    func testDoesNotReportACoverageFindingWhenCoverageMeetsTheThreshold() throws {
        let repoRoot = URL(fileURLWithPath: "/repo")
        let engine = AnalysisEngine(
            fileProvider: FakeFileProvider(files: []),
            contentsProvider: FakeContentsProvider(contents: [:]),
            knownAnalyzers: [:],
            fallbackAnalyzer: FixedFindingAnalyzer(supportedLanguage: .other(""), line: 1),
            context: AnalysisContext(repoRoot: repoRoot, ruleSettings: [:]),
            coverage: .init(provider: FixedCoverageProvider(percent: 90), reportPath: repoRoot.appendingPathComponent("lcov.info"), threshold: 80)
        )
        let result = try engine.run()
        XCTAssertTrue(result.findings.isEmpty)
    }

    func testRoutesObjectiveCHeadersToTheObjectiveCAnalyzerAndOtherHeadersToC() throws {
        let repoRoot = URL(fileURLWithPath: "/repo")
        let objc = repoRoot.appendingPathComponent("Widget.h"), plain = repoRoot.appendingPathComponent("util.h")
        let engine = AnalysisEngine(
            fileProvider: FakeFileProvider(files: [objc, plain]),
            contentsProvider: FakeContentsProvider(contents: [
                objc: "NS_ASSUME_NONNULL_BEGIN\n@interface Widget : NSObject\n@end\n", plain: "int util(void);\n"
            ]),
            knownAnalyzers: [
                .objc: FixedFindingAnalyzer(supportedLanguage: .objc, line: 1),
                .c: FixedFindingAnalyzer(supportedLanguage: .c, line: 2)
            ],
            fallbackAnalyzer: FixedFindingAnalyzer(supportedLanguage: .other(""), line: 3),
            context: AnalysisContext(repoRoot: repoRoot, ruleSettings: [:])
        )
        let lines = try engine.run().findings.map { "\($0.filePath.lastPathComponent):\($0.line)" }
        XCTAssertEqual(lines.sorted(), ["Widget.h:1", "util.h:2"])
    }
}

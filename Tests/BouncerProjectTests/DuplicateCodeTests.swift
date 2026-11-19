import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class DuplicateCodeTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    // MARK: - Helpers

    private func source(_ path: String, _ text: String) -> SourceFile {
        SourceFile(path: RepoPath.url(path, in: root), language: Language.from(fileExtension: (path as NSString).pathExtension),
                   contents: text)
    }

    private func tokens(_ path: String, _ text: String, keepLiterals: Bool = false) -> [CloneToken] {
        CloneTokenizer.tokens(of: source(path, text), keepLiterals: keepLiterals) ?? []
    }

    private func context(_ params: [String: RuleParameterValue] = [:], enabled: Bool = true) -> AnalysisContext {
        let settings = RuleSettings(enabled: enabled, severity: .warning, parameters: RuleParameters(values: params))
        return AnalysisContext(repoRoot: root, ruleSettings: ["duplicate-code": settings])
    }

    private func facts(_ path: String, _ text: String, context: AnalysisContext? = nil) -> FileFacts {
        let clones = DuplicateCodeRule().cloneFacts(for: source(path, text), cached: nil, context: context ?? self.context())
        return FileFacts(path: path, contentHash: "h", module: ModuleFacts(imports: []), clones: clones)
    }

    private func findings(
        _ files: [(String, String)], targets: Set<String>? = nil, params: [String: RuleParameterValue] = [:]
    ) -> [Finding] {
        let context = context(params)
        let all = files.map { facts($0.0, $0.1, context: context) }
        return ProjectRules().findings(for: all, targets: targets ?? Set(files.map(\.0)), context: context)
            .filter { $0.ruleID == "duplicate-code" }
    }

    private func located(_ found: [Finding]) -> [String] {
        found.map { RepoPath.relative($0.filePath, to: root) }
    }

    /// A Swift block of roughly 130 tokens over 20 code lines, with renameable names.
    private func block(_ name: String = "summarize", values: String = "values", total: String = "total") -> String {
        """
        func \(name)(\(values): [Int], limit: Int) -> String {
            var \(total) = 0
            for value in \(values) where value > limit {
                \(total) += value * 2
            }
            let average = \(values).isEmpty ? 0 : \(total) / \(values).count
            if average > limit {
                return "high: \\(average)"
            }
            guard \(total) < 1000 else {
                return "overflow"
            }
            var labels: [String] = []
            for (index, value) in \(values).enumerated() {
                labels.append("\\(index)=\\(value)")
            }
            let joined = labels.joined(separator: ", ")
            return "low: \\(\(total)) of \\(\(values).count) [\\(joined)]"
        }
        """
    }

    private func file(_ prefix: String, _ body: String) -> String {
        "import Foundation\n\nlet \(prefix)Marker = \(prefix.count)\n\n" + body + "\n\nstruct \(prefix)Tail {}\n"
    }

    // MARK: - Tokenizer

    func testSwiftTokensDropCommentsAndNormalizeNamesAndLiterals() {
        let first = tokens("a.swift", "/// Docs.\nlet count = 1 // one\n/* block\n */ print(\"x\")\n")
        let second = tokens("b.swift", "let total = 42\nprint(\"different\")\n")
        XCTAssertEqual(first.map(\.hash), second.map(\.hash))
        XCTAssertEqual(first.map(\.line), [2, 2, 2, 2, 4, 4, 4, 4])
        XCTAssertEqual(first.count, 8, "let, ID, =, LIT, ID, (, LIT, )")
    }

    func testKeywordsAndPunctuationKeepTheirText() {
        XCTAssertNotEqual(tokens("a.swift", "let x = y").map(\.hash), tokens("a.swift", "var x = y").map(\.hash))
        XCTAssertNotEqual(tokens("a.swift", "x + y").map(\.hash), tokens("a.swift", "x - y").map(\.hash))
    }

    func testPythonHashCommentsAndTripleQuotedStrings() {
        let text = "# comment\ndef f(x):\n    \"\"\"Doc\n    more\"\"\"\n    return x  # trailing\n"
        let found = tokens("a.py", text)
        XCTAssertEqual(found.count, 9, "def ID ( ID ) : LIT return ID")
        XCTAssertEqual(found.last?.line, 5)
        XCTAssertEqual(found.map(\.hash), tokens("b.py", "def g(y):\n    'other'\n    return y\n").map(\.hash))
    }

    func testTypeScriptTemplatesAndGoRawStringsAreSingleLiterals() {
        let typeScript = tokens("a.ts", "const s = `a ${b}\nc`; // x\nlet t = 'q';\n")
        XCTAssertEqual(typeScript.count, 10)
        XCTAssertEqual(typeScript.last?.line, 3)
        let go = tokens("a.go", "x := `raw\n// not a comment`\n")
        XCTAssertEqual(go.count, 4)
    }

    func testKeepingLiteralsDistinguishesValues() {
        XCTAssertEqual(tokens("a.ts", "f(1, 'a')").map(\.hash), tokens("a.ts", "f(2, 'b')").map(\.hash))
        XCTAssertNotEqual(
            tokens("a.ts", "f(1, 'a')", keepLiterals: true).map(\.hash),
            tokens("a.ts", "f(2, 'b')", keepLiterals: true).map(\.hash)
        )
    }

    func testUnsupportedLanguagesAreNotTokenized() {
        XCTAssertNil(CloneTokenizer.tokens(of: source("a.sql", "select 1"), keepLiterals: false))
    }

    // MARK: - Fingerprinting

    func testWinnowingIsDeterministicAndCoversEveryWindow() {
        let stream = tokens("a.swift", block())
        let first = CloneFingerprinter.fingerprints(of: stream, scheme: "s")
        XCTAssertEqual(first, CloneFingerprinter.fingerprints(of: stream, scheme: "s"))
        XCTAssertFalse(first.offsets.isEmpty)
        XCTAssertLessThan(first.offsets.count, stream.count / 3)
        let gaps = zip(first.offsets.dropFirst(), first.offsets).map { $0 - $1 }
        XCTAssertTrue(gaps.allSatisfy { $0 > 0 && $0 <= CloneFingerprinter.window }, "\(gaps)")
    }

    func testLowDiversityDataTablesGetNoFingerprints() {
        let table = "let table = [" + (0..<200).map { "\($0)" }.joined(separator: ", ") + "]\n"
        let picked = CloneFingerprinter.fingerprints(of: tokens("a.swift", table), scheme: "s").offsets
        XCTAssertTrue(picked.allSatisfy { $0 == 0 }, "only the k-gram that includes the declaration: \(picked)")
    }

    func testCachedFingerprintsAreReusedOnlyForTheCurrentScheme() {
        let rule = DuplicateCodeRule(), file = source("a.swift", block())
        let current = rule.cloneFacts(for: file, cached: nil, context: context())
        let stale = CloneFacts(scheme: "old", hashes: [1], offsets: [0], lines: [0], endLines: [0], lineNumbers: [1])
        XCTAssertEqual(rule.cloneFacts(for: file, cached: stale, context: context()), current)
        let marker = CloneFacts(scheme: current?.scheme ?? "", hashes: [], offsets: [], lines: [], endLines: [],
                                lineNumbers: [])
        XCTAssertEqual(rule.cloneFacts(for: file, cached: marker, context: context()), marker)
        XCTAssertNil(rule.cloneFacts(for: file, cached: nil, context: context(enabled: false)))
        XCTAssertEqual(rule.cloneFacts(for: file, cached: stale, context: context(enabled: false)), stale,
                       "a disabled rule keeps the cache warm")
        XCTAssertNotEqual(rule.cloneFacts(for: file, cached: nil, context: context(["ignoreLiterals": .bool(false)]))?.scheme,
                          current?.scheme)
    }

    // MARK: - Detection

    func testReportsAnExactCopyOnceAtTheLaterFile() {
        let found = findings([("Sources/B/b.swift", file("b", block())), ("Sources/A/a.swift", file("a", block()))])
        XCTAssertEqual(located(found), ["Sources/B/b.swift"])
        let message = found.first?.message ?? ""
        XCTAssertTrue(message.hasPrefix("Duplicates lines "), message)
        XCTAssertTrue(message.contains(" of Sources/A/a.swift ("), message)
        XCTAssertTrue(message.hasSuffix(" tokens)."), message)
        XCTAssertGreaterThanOrEqual(found.first?.line ?? 0, 4)
    }

    func testFindsACopyWithConsistentlyRenamedIdentifiers() {
        let renamed = block("describe", values: "numbers", total: "sum")
        XCTAssertEqual(located(findings([("a.swift", file("a", block())), ("b.swift", file("b", renamed))])), ["b.swift"])
    }

    func testFindsCopiesAcrossTypeScriptAndPython() {
        let typeScript = (0..<6).map { "export function f\($0)(a: number, b: string): string { return b.repeat(a) + '\($0)'; }" }
            .joined(separator: "\n")
        XCTAssertEqual(located(findings([("x.ts", typeScript), ("y.ts", "// copy\n" + typeScript)])), ["y.ts"])
        let python = (0..<8).map { "def f\($0)(a, b):\n    if a > b:\n        return a * \($0)\n    return [b, a]\n" }
            .joined()
        XCTAssertEqual(located(findings([("p.py", python), ("q.py", "import os\n" + python)])), ["q.py"])
    }

    func testIgnoresCopiesBelowTheThresholds() {
        let files = [("a.swift", file("a", block())), ("b.swift", file("b", block()))]
        XCTAssertTrue(findings(files, params: ["minTokens": .int(400)]).isEmpty)
        XCTAssertTrue(findings(files, params: ["minLines": .int(40)]).isEmpty)
        let small = "func f(a: Int) -> Int {\n    return a + 1\n}\n"
        XCTAssertTrue(findings([("a.swift", file("a", small)), ("b.swift", file("b", small))]).isEmpty)
    }

    func testSkipsCopiesWithinOneFile() {
        XCTAssertTrue(findings([("a.swift", file("a", block() + "\n" + block("other")))]).isEmpty)
    }

    func testGroupsAManyWayCopyIntoOneClass() {
        let paths = ["e.swift", "c.swift", "a.swift", "d.swift", "b.swift"]
        let found = findings(paths.map { ($0, file(String($0.prefix(1)), block())) })
        XCTAssertEqual(located(found), ["b.swift", "c.swift", "d.swift", "e.swift"])
        XCTAssertTrue(found.allSatisfy { $0.message.contains(" of a.swift (") && $0.message.contains("one of 5 copies") },
                      found.map(\.message).joined(separator: "\n"))
    }

    func testOnlyReportsInTargetFiles() {
        let files = [("a.swift", file("a", block())), ("b.swift", file("b", block())), ("c.swift", file("c", block()))]
        XCTAssertEqual(located(findings(files, targets: ["c.swift"])), ["c.swift"])
        let atFirst = findings(files, targets: ["a.swift"])
        XCTAssertEqual(located(atFirst), ["a.swift"])
        XCTAssertTrue(atFirst.first?.message.contains(" of b.swift (") ?? false)
        XCTAssertTrue(findings(files, targets: ["other.swift"]).isEmpty)
    }

    func testIgnoreGlobsLeaveFilesOutOfTheComparison() {
        let files = [("a.swift", file("a", block())), ("Generated/b.swift", file("b", block()))]
        XCTAssertTrue(findings(files, params: ["ignore": .stringList(["Generated/**"])]).isEmpty)
    }

    func testOutputOrderIsStable() {
        let files = (0..<4).map { ("f\($0).swift", file("f\($0)", block() + "\n" + block("g", values: "v\($0)"))) }
        let first = findings(files).map { "\($0.filePath.path):\($0.line):\($0.message)" }
        XCTAssertEqual(first, findings(files.reversed()).map { "\($0.filePath.path):\($0.line):\($0.message)" })
    }

    // MARK: - Near-duplicates (Type-3)

    /// The standard block with one line edited: a line inserted, a line changed, or a line deleted.
    private func edited(_ edit: String) -> String {
        let lines = block().components(separatedBy: "\n")
        switch edit {
        case "inserted":
            return (lines[..<9] + ["    precondition(limit >= 0, \"negative\")"] + lines[9...]).joined(separator: "\n")
        case "changed":
            return lines.map { $0.contains("guard total") ? "    guard total * 3 <= limit + 999 else {" : $0 }
                .joined(separator: "\n")
        default:
            return lines.filter { !$0.contains("let average") }.map { $0.replacingOccurrences(of: "average", with: "total") }
                .joined(separator: "\n")
        }
    }

    func testJoinsCopiesSeparatedByAnInsertedChangedOrDeletedLine() {
        for edit in ["inserted", "changed", "deleted"] {
            let found = findings([("a.swift", file("a", block())), ("b.swift", file("b", edited(edit)))])
            XCTAssertEqual(located(found), ["b.swift"], edit)
            let message = found.first?.message ?? ""
            XCTAssertTrue(message.hasPrefix("Nearly duplicates lines "), "\(edit): \(message)")
            XCTAssertTrue(message.range(of: #"\(\d+ tokens, ~\d+% identical\)\.$"#, options: .regularExpression) != nil,
                          "\(edit): \(message)")
        }
    }

    func testANearDuplicateCoversBothSidesOfTheEdit() {
        let found = findings([("a.swift", file("a", block())), ("b.swift", file("b", edited("inserted")))])
        let exact = findings([("a.swift", file("a", block())), ("b.swift", file("b", edited("inserted")))],
                             params: ["maxGap": .int(0)])
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(exact.allSatisfy { $0.message.hasPrefix("Duplicates lines ") }, exact.map(\.message).description)
        let span = { (finding: Finding) -> Int in
            Int(finding.message.split(separator: "–")[1].split(separator: " ")[0]) ?? 0
        }
        XCTAssertGreaterThan(span(found[0]), exact.map(span).max() ?? 0, "the joined region reaches past the edit")
    }

    func testDoesNotJoinBelowTheSimilarityOrPastTheGap() {
        let files = [("a.swift", file("a", block())), ("b.swift", file("b", edited("changed")))]
        let strict = findings(files, params: ["minSimilarity": .int(99)])
        XCTAssertTrue(strict.allSatisfy { !$0.message.hasPrefix("Nearly") }, strict.map(\.message).description)
        XCTAssertTrue(findings(files, params: ["maxGap": .int(0)]).allSatisfy { !$0.message.hasPrefix("Nearly") })
        let filler = (0..<6).map { "    let unrelated\($0) = labels.map { $0.count + \($0) }.reduce(0, +)" }
        let lines = block().components(separatedBy: "\n")
        let distant = (lines[..<9] + filler + lines[9...]).joined(separator: "\n")
        let far = findings([("a.swift", file("a", block())), ("b.swift", file("b", distant))])
        XCTAssertTrue(far.allSatisfy { !$0.message.hasPrefix("Nearly") }, far.map(\.message).description)
    }

    func testExactAndRenamedCopiesKeepTheirMessage() {
        let renamed = block("describe", values: "numbers", total: "sum")
        let found = findings([("a.swift", file("a", block())), ("b.swift", file("b", renamed))])
        XCTAssertEqual(found.map(\.message), findings([("a.swift", file("a", block())), ("b.swift", file("b", renamed))],
                                                       params: ["maxGap": .int(0)]).map(\.message))
        XCTAssertFalse(found.first?.message.contains("identical") ?? true)
    }

    func testMergerJoinsOnlyCloseOrderedSimilarRuns() {
        let run = { (first: Range<Int>, second: Range<Int>) in
            CloneRun(firstFile: 0, secondFile: 1, firstEntries: first.lowerBound...first.lowerBound,
                     secondEntries: second.lowerBound...second.lowerBound, firstTokens: first, secondTokens: second,
                     matched: first.count, longestPiece: first.count)
        }
        let merger = CloneMerger(maxGap: 30, minSimilarity: 80)
        let joined = merger.merged([run(0..<60, 0..<60), run(70..<130, 75..<135)])
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined.first?.tokens, 135)
        XCTAssertEqual(joined.first?.matched, 130, "the smaller gap is credited")
        XCTAssertEqual(merger.merged([run(0..<60, 0..<60), run(100..<160, 100..<160)]).count, 2, "gap too wide")
        XCTAssertEqual(merger.merged([run(0..<60, 0..<60), run(50..<110, 65..<125)]).count, 2, "overlapping")
        XCTAssertEqual(merger.merged([run(0..<20, 0..<20), run(45..<65, 45..<65)]).count, 2, "too dissimilar")
        XCTAssertEqual(CloneMerger(maxGap: 0, minSimilarity: 80).merged([run(0..<60, 0..<60), run(70..<130, 75..<135)])
            .count, 2)
    }

    // MARK: - Cache

    func testFactsStoreRoundTripsFingerprintsAndRebuildsAnOldVersion() throws {
        let repo = FileManager.default.temporaryDirectory.appendingPathComponent("dup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        let stored = facts("a.swift", block())
        try JSONFactsStore(repoRoot: repo).save([stored])
        XCTAssertEqual(JSONFactsStore(repoRoot: repo).cachedFacts(path: "a.swift", contentHash: "h"), stored)
        XCTAssertNotNil(stored.clones)
        let cacheFile = repo.appendingPathComponent(".bouncer-cache/facts.json")
        let old = try String(contentsOf: cacheFile, encoding: .utf8).replacingOccurrences(of: "\"version\":5", with: "\"version\":4")
        try old.write(to: cacheFile, atomically: true, encoding: .utf8)
        XCTAssertNil(JSONFactsStore(repoRoot: repo).cachedFacts(path: "a.swift", contentHash: "h"))
    }
}

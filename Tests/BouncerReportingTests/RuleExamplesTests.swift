import XCTest
@testable import BouncerReporting

final class RuleExamplesTests: XCTestCase {
    /// Catalog rules that can't be shown as one before and after, each with the reason. Keep this tiny.
    private let exemptions: [String: String] = [:]

    /// The fence languages examples may use.
    private let knownLanguages: Set = [
        "bash", "c", "cpp", "go", "java", "javascript", "json", "objc", "php", "powershell", "python", "rust", "sql",
        "swift", "text", "toml", "typescript", "yaml"
    ]

    func testEmbeddedExamplesMatchTheArticle() throws {
        let article = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/BouncerCore/BouncerCore.docc/Articles/RuleExamples.md")
        let markdown = try String(contentsOf: article, encoding: .utf8).replacingOccurrences(of: "\r", with: "")
        let embedded = RuleExamplesText.markdown.replacingOccurrences(of: "\r", with: "")
        XCTAssertTrue(
            embedded == markdown,
            "RuleExamplesText.swift is out of date with RuleExamples.md: run Scripts/generate-rule-catalog.sh"
        )
    }

    func testEveryCatalogRuleHasAnExampleOrIsExempt() {
        let missing = RuleCatalog.ruleIDs.filter { RuleExamples.example(for: $0) == nil && exemptions[$0] == nil }
        XCTAssertEqual(missing, [])
        let exemptWithExample = exemptions.keys.filter { RuleExamples.example(for: $0) != nil }
        XCTAssertEqual(exemptWithExample, [], "An exempt rule has an example; drop the exemption")
    }

    func testNoExampleNamesAnUnknownRule() {
        let known = Set(RuleCatalog.ruleIDs)
        XCTAssertEqual(RuleExamples.ruleIDs.filter { !known.contains($0) }, [])
    }

    func testEveryHeadingParsesIntoAnExample() {
        let headings = RuleExamplesText.markdown.components(separatedBy: "\n").filter { $0.hasPrefix("### ") }
        XCTAssertEqual(headings.count, RuleExamples.ruleIDs.count, "A heading lacks a before/after pair, or repeats")
    }

    func testBeforeAndAfterDiffer() {
        let same = RuleExamples.ruleIDs.filter { id in RuleExamples.example(for: id).map { $0.before == $0.after } ?? true }
        XCTAssertEqual(same, [])
    }

    func testEveryExampleIsNonEmptyOnBothSides() {
        let empty = RuleExamples.ruleIDs.filter { id in
            RuleExamples.example(for: id).map { $0.before.isEmpty || $0.after.isEmpty } ?? true
        }
        XCTAssertEqual(empty, [])
    }

    func testFenceLanguagesAreKnown() {
        let unknown = RuleExamples.ruleIDs.compactMap { RuleExamples.example(for: $0)?.language }
            .filter { !knownLanguages.contains($0) }
        XCTAssertEqual(unknown, [])
    }

    func testUnknownRuleHasNoExample() {
        XCTAssertNil(RuleExamples.example(for: "nope"))
        XCTAssertNil(RuleExamples.example(for: ""))
    }

    func testExampleStripsTheFencesAndKeepsIndentation() throws {
        let example = try XCTUnwrap(RuleExamples.example(for: "else-after-return"))
        XCTAssertEqual(example.language, "typescript")
        XCTAssertTrue(example.before.hasPrefix("function displayName(user?: User): string {\n  if (!user) {"))
        XCTAssertFalse(example.before.contains("```"))
        XCTAssertFalse(example.after.contains("```"))
        XCTAssertTrue(example.after.hasSuffix("  return user.name;\n}"))
    }

    func testFinalNewlineExampleKeepsItsTrailingBlankLine() throws {
        let example = try XCTUnwrap(RuleExamples.example(for: "missing-final-newline"))
        XCTAssertFalse(example.before.hasSuffix("\n"))
        XCTAssertTrue(example.after.hasSuffix(";\n"))
    }

    func testParserReadsPairsAndSkipsMismatchedOnes() {
        let markdown = """
            # Title

            ### `good-rule`

            ```swift before
                let a = 1
            ```

            ```swift after
                let b = 1
            ```

            ### `mixed-languages`

            ```swift before
            x
            ```

            ```python after
            y
            ```

            ### `no-after`

            ```go before
            z
            ```
            """
        let examples = RuleExampleParser.examples(in: markdown)
        XCTAssertEqual(examples, ["good-rule": RuleExample(language: "swift", before: "    let a = 1", after: "    let b = 1")])
    }

    func testParserIgnoresUntaggedFencesAndReadsCRLF() {
        let markdown = "### `rule`\r\n```\r\nnot an example\r\n```\r\n```c before\r\na();\r\n```\r\n```c after\r\nb();\r\n```\r\n"
        XCTAssertEqual(RuleExampleParser.examples(in: markdown), ["rule": RuleExample(language: "c", before: "a();", after: "b();")])
    }
}

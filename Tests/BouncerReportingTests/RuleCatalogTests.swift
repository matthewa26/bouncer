import XCTest
@testable import BouncerCore
@testable import BouncerReporting

final class RuleCatalogTests: XCTestCase {
    private func text(_ ruleID: String) throws -> String {
        try XCTUnwrap(RuleCatalog.explain(ruleID), "No catalog entry for \(ruleID)").text
    }

    func testEmbeddedCatalogMatchesTheArticle() throws {
        let article = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/BouncerCore/BouncerCore.docc/Articles/RuleCatalog.md")
        let markdown = try String(contentsOf: article, encoding: .utf8).replacingOccurrences(of: "\r", with: "")
        let embedded = RuleCatalogText.markdown.replacingOccurrences(of: "\r", with: "")
        XCTAssertTrue(
            embedded == markdown,
            "RuleCatalogText.swift is out of date with RuleCatalog.md: run Scripts/generate-rule-catalog.sh"
        )
    }

    func testPerFileRuleShowsItsRowConfigurationAndSuppression() throws {
        let text = try text("long-function")
        XCTAssertEqual(RuleCatalog.explain("long-function")?.id, "long-function")
        XCTAssertTrue(text.hasPrefix("long-function (rule catalog: Code smells)"), text)
        XCTAssertTrue(text.contains("- A function's logical line count. Default: warning. Parameters: maxLines (40)."))
        XCTAssertTrue(text.contains(#""rules": {"long-function": {"enabled": false}} turns it off"#), text)
        XCTAssertTrue(text.contains(#""severity": "error""#), text)
        XCTAssertTrue(text.contains(#""params": {"maxLines": 40}"#), text)
        XCTAssertTrue(text.contains("// bouncer:disable-line long-function -- reason"), text)
        XCTAssertFalse(text.contains("`"), text)
        XCTAssertFalse(text.contains("OWASP"), text)
        XCTAssertTrue(text.contains("Fix cost: refactor (needs restructuring)."), text)
    }

    func testLanguageNoteInTheRuleIDCellCounts() throws {
        let text = try text("force-unwrap")
        XCTAssertTrue(text.contains("- [Swift] A force unwrap, x!. Default: warning. Parameters: none."), text)
        XCTAssertLessThan(text.count, 900)
    }

    func testPerLanguageExtraWithOWASPCategory() throws {
        let text = try text("rust-unwrap")
        XCTAssertTrue(text.hasPrefix("rust-unwrap (rule catalog: Per-language extras)"), text)
        XCTAssertTrue(text.contains("- [Rust] .unwrap() or .expect(…) outside test code"), text)
        XCTAssertTrue(text.contains("OWASP: A10:2025 Mishandling of Exceptional Conditions."), text)
        XCTAssertTrue(text.contains("Conditions.\nFix cost: mechanical (a local fix)."), "Cost follows OWASP")
    }

    func testProjectRuleThatIsOffUntilConfigured() throws {
        let text = try text("layer-violation")
        XCTAssertTrue(text.hasPrefix("layer-violation (rule catalog: Project rules)"), text)
        XCTAssertTrue(text.contains(#"{"layer-violation": {"enabled": true}} turns it on"#), text)
    }

    func testRuleDocumentedInSeveralRowsListsEachLanguage() throws {
        let text = try text("insecure-random")
        for language in ["TypeScript/JavaScript", "Python", "Go"] {
            XCTAssertTrue(text.contains("- [\(language)] "), text)
        }
        XCTAssertTrue(text.contains("OWASP: A04:2025 Cryptographic Failures."), text)
    }

    func testSecurityTableRowAndSharedRowIDs() throws {
        let ssrf = try text("ssrf")
        XCTAssertTrue(ssrf.contains("OWASP: A01:2025 Broken Access Control."), ssrf)
        XCTAssertTrue(ssrf.contains("- [TS/JS, Python, Go, Java, Swift, Objective-C] Request input"), ssrf)
        XCTAssertFalse(ssrf.contains("A01:2025. "), "The category column is left to the OWASP line")
        XCTAssertTrue(try text("c-unsafe-string-function").contains("- [Objective-C] The C checks"))
    }

    func testUnknownAndNearMissIDsHaveNoEntry() {
        XCTAssertNil(RuleCatalog.explain("no-such-rule"))
        XCTAssertNil(RuleCatalog.explain("Force-Unwrap"))
        XCTAssertNil(RuleCatalog.explain("force"))
        XCTAssertNil(RuleCatalog.explain("languages"), "A parameter named in a language note isn't a rule")
    }

    func testRuleIDsAreSortedUniqueAndComplete() {
        let ids = RuleCatalog.ruleIDs
        XCTAssertEqual(ids, Array(Set(ids)).sorted())
        let expected = ["force-unwrap", "rust-unwrap", "import-cycle", "insecure-random", "ssrf", "complexity-ratchet"]
        for id in expected { XCTAssertTrue(ids.contains(id), id) }
        for id in ids { XCTAssertNotNil(RuleCatalog.explain(id), id) }
    }

    func testEveryOWASPMappedRuleHasAnEntry() {
        let missing = OWASPCategory.mappedRuleIDs.filter { RuleCatalog.explain($0) == nil }
        XCTAssertEqual(missing, [])
    }

    func testForceUnwrapIsAMechanicalFix() throws {
        XCTAssertTrue(try text("force-unwrap").contains("Fix cost: mechanical (a local fix)."))
    }

    func testEveryCatalogRuleHasAFixCost() {
        let missing = RuleCatalog.ruleIDs.filter { FixCost.cost(forRule: $0) == nil }
        XCTAssertEqual(missing, [], "No fix-cost tag in FixCost.table: \(missing.joined(separator: ", "))")
    }

    func testEveryTaggedRuleIsARealRule() {
        let known = Set(RuleCatalog.ruleIDs).union(FixCost.uncataloguedRuleIDs)
        let unknown = FixCost.taggedRuleIDs.filter { !known.contains($0) }
        XCTAssertEqual(unknown, [], "Tagged but not a rule (a typo?): \(unknown.joined(separator: ", "))")
        let documented = FixCost.uncataloguedRuleIDs.filter { RuleCatalog.ruleIDs.contains($0) }
        XCTAssertEqual(documented, [], "Now in the catalog; drop from uncataloguedRuleIDs: \(documented)")
    }

    /// The longest a rationale may be, in characters, so the HTML report's tooltip stays short.
    private let maxRationaleLength = 280
    /// The shortest a rationale may be, in characters, so a placeholder can't stand in for one.
    private let minRationaleLength = 80

    func testEveryCatalogRuleHasAShortRationale() {
        for id in RuleCatalog.ruleIDs {
            let rationale = RuleCatalog.rationale(for: id) ?? ""
            XCTAssertGreaterThanOrEqual(rationale.count, minRationaleLength, "No real rationale for \(id)")
            XCTAssertLessThanOrEqual(rationale.count, maxRationaleLength, "Rationale too long for \(id)")
            XCTAssertFalse(rationale.contains("`") || rationale.contains("|"), "Markdown left in \(id)'s rationale")
        }
    }

    func testEveryRationaleNamesACatalogRule() {
        let unknown = RuleCatalog.rationaleRuleIDs.filter { !RuleCatalog.ruleIDs.contains($0) }
        XCTAssertEqual(unknown, [], "Rationale rows for rules the catalog doesn't define: \(unknown)")
    }

    func testUnknownRuleHasNoRationale() {
        XCTAssertNil(RuleCatalog.rationale(for: "nope"))
        XCTAssertNil(RuleCatalog.rationale(for: "Force-Unwrap"))
    }

    func testExplanationShowsTheRationaleOnceUnderTheHeading() throws {
        for id in ["force-unwrap", "sql-string-building", "import-cycle", "c-unsafe-string-function"] {
            let text = try text(id)
            let rationale = try XCTUnwrap(RuleCatalog.rationale(for: id))
            let lines = text.components(separatedBy: "\n")
            XCTAssertEqual(lines[1], "Why it matters: \(rationale)", text)
            XCTAssertEqual(text.components(separatedBy: rationale).count, 2, "Rationale not shown exactly once")
            XCTAssertFalse(text.contains("Why each rule matters"), "The rationale table isn't a catalog section")
        }
    }

    func testRationaleTableAddsNoRuleRows() throws {
        let text = try text("long-function")
        XCTAssertTrue(text.hasPrefix("long-function (rule catalog: Code smells)\nWhy it matters: "), text)
        XCTAssertEqual(text.components(separatedBy: "\n- ").count, 2, "Exactly one documenting row")
    }
}

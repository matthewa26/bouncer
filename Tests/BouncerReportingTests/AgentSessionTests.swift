import XCTest
import Foundation
import BouncerCore
@testable import BouncerReporting

final class FindingDeltaTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func finding(_ rule: String, _ path: String, _ line: Int, _ message: String = "m") -> Finding {
        Finding(ruleID: rule, severity: .warning, filePath: root.appendingPathComponent(path), line: line, message: message)
    }

    func testSplitsFixedRemainingAndNew() {
        let before = [finding("a", "A.swift", 1), finding("b", "A.swift", 2), finding("c", "A.swift", 3)]
        let after = [finding("b", "A.swift", 2), finding("d", "A.swift", 4)]
        let delta = FindingDelta(before: before, after: after)
        XCTAssertEqual(delta.fixed.map(\.ruleID), ["a", "c"])
        XCTAssertEqual(delta.remaining.map(\.ruleID), ["b"])
        XCTAssertEqual(delta.new.map(\.ruleID), ["d"])
        XCTAssertEqual(delta.summary, "2 fixed, 1 still there, 1 new.")
    }

    func testAFindingThatMovedLinesIsStillThere() {
        let delta = FindingDelta(before: [finding("a", "A.swift", 10, "x")], after: [finding("a", "A.swift", 14, "x")])
        XCTAssertEqual(delta.remaining.map(\.line), [14])
        XCTAssertTrue(delta.fixed.isEmpty && delta.new.isEmpty)
    }

    func testAFindingWhoseMessageChangedOnTheSameLineIsStillThere() {
        let delta = FindingDelta(before: [finding("long", "A.swift", 3, "15 lines")], after: [finding("long", "A.swift", 3, "12 lines")])
        XCTAssertEqual(delta.remaining.map(\.message), ["12 lines"])
    }

    func testEachOldFindingMatchesOnlyOnce() {
        let before = [finding("a", "A.swift", 1, "x")]
        let after = [finding("a", "A.swift", 1, "x"), finding("a", "A.swift", 5, "x")]
        let delta = FindingDelta(before: before, after: after)
        XCTAssertEqual(delta.remaining.count, 1)
        XCTAssertEqual(delta.new.map(\.line), [5])
    }

    func testTheSameRuleInAnotherFileDoesNotMatch() {
        let delta = FindingDelta(before: [finding("a", "A.swift", 1)], after: [finding("a", "B.swift", 1)])
        XCTAssertEqual(delta.fixed.count, 1)
        XCTAssertEqual(delta.new.count, 1)
    }
}

final class FindingCursorTests: XCTestCase {
    func testRoundTrips() {
        for offset in [0, 1, 35, 36, 1_000_000] {
            XCTAssertEqual(FindingCursor.decode(FindingCursor.encode(offset: offset)), offset)
        }
    }

    func testRejectsForeignCursors() {
        for cursor in ["", "f", "20", "x10", "f-1", "fZZ", "f1.5"] {
            XCTAssertNil(FindingCursor.decode(cursor), cursor)
        }
    }
}

final class AgentSessionTextTests: XCTestCase {
    func testAgeWording() {
        XCTAssertEqual(AgentSessionText.age(seconds: 0), "just now")
        XCTAssertEqual(AgentSessionText.age(seconds: 42), "42 s ago")
        XCTAssertEqual(AgentSessionText.age(seconds: 250), "4 min ago")
        XCTAssertEqual(AgentSessionText.age(seconds: 7_300), "2 h ago")
        XCTAssertEqual(AgentSessionText.age(seconds: 86_400), "1 day ago")
        XCTAssertEqual(AgentSessionText.age(seconds: 3 * 86_400), "3 days ago")
    }

    func testAgeHeader() {
        XCTAssertEqual(
            AgentSessionText.ageHeader(seconds: 250), "Results from 4 min ago; verify re-checks files you edited."
        )
    }

    func testProgressWording() {
        XCTAssertEqual(
            AgentSessionText.progress(done: 120, total: 284, elapsedSeconds: 3),
            "Scanning: 42% (120 of 284 files), 3s elapsed. Call status."
        )
        XCTAssertEqual(
            AgentSessionText.progress(done: 0, total: nil, elapsedSeconds: 0),
            "Scanning: listing files, 0s elapsed. Call status."
        )
        XCTAssertEqual(
            AgentSessionText.progress(done: 5, total: 5, elapsedSeconds: 9, step: "running project rules"),
            "Scanning: all 5 files analyzed, running project rules, 9s elapsed. Call status."
        )
    }
}

final class NameSuggestionsTests: XCTestCase {
    private let names = ["force-cast", "force-try", "force-unwrap", "long-function", "long-lines", "magic-number"]

    func testSuggestsNamesContainingTheQueryOrNearIt() {
        XCTAssertEqual(NameSuggestions.closest(to: "force", among: names), ["force-cast", "force-try", "force-unwrap"])
        XCTAssertEqual(NameSuggestions.closest(to: "force-unwarp", among: names).first, "force-unwrap")
        XCTAssertEqual(NameSuggestions.closest(to: "Long-Function", among: names), ["long-function"])
    }

    func testSuggestsNothingForAnUnrelatedName() {
        XCTAssertEqual(NameSuggestions.closest(to: "zzzzzzzz", among: names), [])
    }

    func testCapsTheSuggestions() {
        XCTAssertEqual(NameSuggestions.closest(to: "o", among: names, limit: 2).count, 2)
    }

    func testDistance() {
        XCTAssertEqual(NameSuggestions.distance(Array("kitten"), Array("sitting")), 3)
        XCTAssertEqual(NameSuggestions.distance(Array(""), Array("abc")), 3)
    }
}

final class AgentPagerTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func findings(_ count: Int, rule: (Int) -> String = { _ in "rule" }) -> [Finding] {
        (1...count).map { index in
            Finding(
                ruleID: rule(index), severity: .warning, filePath: root.appendingPathComponent("F\(index % 3).swift"),
                line: index, message: "message \(index)"
            )
        }
    }

    func testShowsEverythingThatFits() {
        let pager = AgentPager(repoRoot: root)
        let page = pager.page(pager.ordered(findings(3)), offset: 0, maxChars: 1_000)
        XCTAssertEqual(page.shown, 3)
        XCTAssertNil(page.nextOffset)
        XCTAssertTrue(page.text.hasSuffix("3 findings."))
    }

    func testNeverExceedsTheBudgetAndPagesWithoutGapsOrRepeats() {
        let pager = AgentPager(repoRoot: root)
        let all = pager.ordered(findings(200))
        var offset = 0, seen = 0
        while true {
            let page = pager.page(all, offset: offset, maxChars: 300)
            XCTAssertLessThanOrEqual(page.text.count, 300)
            XCTAssertGreaterThan(page.shown, 0)
            seen += page.shown
            guard let next = page.nextOffset else { break }
            XCTAssertTrue(page.text.hasSuffix("Next cursor: \(FindingCursor.encode(offset: next))."), page.text)
            offset = next
        }
        XCTAssertEqual(seen, 200)
    }

    func testRuleGroupingPagesInRenderedOrder() {
        let pager = AgentPager(repoRoot: root, grouping: .rule)
        let all = pager.ordered(findings(30) { $0.isMultiple(of: 2) ? "b-rule" : "a-rule" })
        XCTAssertEqual(all.prefix(15).map(\.ruleID), Array(repeating: "a-rule", count: 15))
        let first = pager.page(all, offset: 0, maxChars: 200)
        let rows = first.text.components(separatedBy: "\n").filter { $0.hasPrefix("  ") }
        XCTAssertEqual(rows.count, first.shown)
        let expected = all.prefix(first.shown).map { "\(RepoPath.relative($0.filePath, to: root)):\($0.line)" }
        XCTAssertEqual(rows.map { String($0.dropFirst(2).split(separator: " ")[0]) }, expected)
    }

    func testABudgetTooSmallForAFindingSaysSo() {
        let pager = AgentPager(repoRoot: root)
        let page = pager.page(findings(5), offset: 0, maxChars: 40)
        XCTAssertEqual(page.shown, 0)
        XCTAssertTrue(page.text.contains("raise max_chars"), page.text)
    }

    func testFooterCountsFindingsBeforeFiltersAndCanOmitTheCursor() {
        let pager = AgentPager(repoRoot: root)
        let footer = AgentPageFooter(unfilteredTotal: 900, namesCursor: false)
        let page = pager.page(pager.ordered(findings(50)), offset: 0, maxChars: 200, footer: footer)
        XCTAssertTrue(page.text.hasSuffix("of 50 findings (900 before filters)."), page.text)
    }
}

final class FindingSelectionFilteringTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    func testFiltersByRuleSeverityAndPathKeepingOrder() {
        let findings = [
            Finding(ruleID: "b", severity: .error, filePath: root.appendingPathComponent("Z/One.swift"), line: 9, message: ""),
            Finding(ruleID: "a", severity: .warning, filePath: root.appendingPathComponent("A/Two.swift"), line: 1, message: ""),
            Finding(ruleID: "b", severity: .info, filePath: root.appendingPathComponent("Z/Three.swift"), line: 2, message: ""),
            Finding(ruleID: "b", severity: .error, filePath: root.appendingPathComponent("A/Four.swift"), line: 3, message: "")
        ]
        var selection = FindingSelection()
        selection.rules = ["b"]
        selection.minimumSeverity = .warning
        XCTAssertEqual(selection.filtering(findings, repoRoot: root).map(\.line), [9, 3])
        selection.paths = ["Z/**"]
        XCTAssertEqual(selection.filtering(findings, repoRoot: root).map(\.line), [9])
    }
}

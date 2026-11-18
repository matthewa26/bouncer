import XCTest
@testable import BouncerCore

final class BaselineTests: XCTestCase {
    func testFingerprintIsStableForIdenticalContent() {
        let a = Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "func f() {")
        let b = Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "func f() {")
        XCTAssertEqual(a, b)
    }

    func testFingerprintIgnoresSurroundingWhitespace() {
        let a = Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "func f() {")
        let b = Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "   func f() {  ")
        XCTAssertEqual(a, b)
    }

    func testFingerprintDiffersByRuleOrPathOrContent() {
        let base = Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "func f() {")
        XCTAssertNotEqual(base, Baseline.fingerprint(ruleID: "other-rule", relativePath: "a.swift", lineContent: "func f() {"))
        XCTAssertNotEqual(base, Baseline.fingerprint(ruleID: "long-function", relativePath: "b.swift", lineContent: "func f() {"))
        XCTAssertNotEqual(base, Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "func g() {"))
    }

    func testEmptyBaselineContainsNothing() {
        let fingerprint = Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "func f() {")
        XCTAssertFalse(Baseline.empty.contains(fingerprint))
    }

    func testBaselineContainsAnAcceptedFingerprint() {
        let fingerprint = Baseline.fingerprint(ruleID: "long-function", relativePath: "a.swift", lineContent: "func f() {")
        let baseline = Baseline(fingerprints: [fingerprint])
        XCTAssertTrue(baseline.contains(fingerprint))
    }
}

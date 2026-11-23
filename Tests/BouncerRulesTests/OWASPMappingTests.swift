import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class OWASPMappingTests: XCTestCase {
    /// The rules this wave added for the OWASP Top 10:2025.
    private let addedRules = [
        "ssrf", "open-redirect", "cors-credentials-any-origin", "debug-mode-enabled", "permissive-cors",
        "insecure-cookie", "xml-external-entities", "hardcoded-iv", "short-crypto-key", "objc-shell-injection",
        "template-injection", "nosql-injection", "jwt-verification-disabled", "timing-unsafe-comparison",
        "unsafe-deserialization", "unlogged-security-failure", "fail-open"
    ]

    /// The security rules that existed before this wave.
    private let earlierSecurityRules = [
        "path-traversal", "insecure-http-url", "hardcoded-ip", "secret-looking-pattern", "weak-crypto",
        "insecure-random", "disabled-tls-verification", "sql-string-building", "sql-missing-where", "shell-eval-usage",
        "powershell-invoke-expression", "c-gets-usage", "c-unsafe-string-function", "python-shell-injection",
        "js-shell-injection", "go-shell-injection", "swift-shell-injection", "js-eval", "js-raw-html",
        "python-eval-exec", "powershell-plaintext-password", "python-unsafe-deserialization", "logged-secret",
        "empty-catch", "swift-discarded-try", "python-bare-except", "java-generic-exception-catch"
    ]

    private let languages: [Language] = [
        .swift, .python, .zsh, .bash, .powershell, .typescript, .javascript, .cpp, .java, .go, .sql, .c, .objc, .php
    ]

    /// Every rule ID the text-rule registry builds, across every language.
    private var registered: Set<String> {
        Set(languages.flatMap { TextRules.make(profile: LanguageProfiles.profile(for: $0)).map(\.id) })
    }

    func testEveryRuleAddedThisWaveIsRegisteredAndMapped() {
        for ruleID in addedRules {
            XCTAssertTrue(registered.contains(ruleID), "\(ruleID) isn't registered")
            XCTAssertNotNil(OWASPCategory.category(forRule: ruleID), "\(ruleID) isn't mapped")
        }
        XCTAssertEqual(Set(SecurityRules.all.map(\.id)), Set(addedRules))
    }

    func testEveryRegisteredSecurityRuleHasACategory() {
        let security = registered.intersection(addedRules + earlierSecurityRules)
        XCTAssertEqual(security, Set(addedRules + earlierSecurityRules), "a security rule is no longer registered")
        for ruleID in security {
            XCTAssertNotNil(OWASPCategory.category(forRule: ruleID), "\(ruleID) isn't mapped")
        }
    }

    func testTheRuleCatalogLabelsEveryRegisteredMappedRuleWithItsCategory() throws {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/BouncerCore/BouncerCore.docc/Articles/RuleCatalog.md")
        let rows = try String(contentsOf: catalog, encoding: .utf8).split(separator: "\n").filter { $0.hasPrefix("|") }
        for ruleID in registered.sorted() {
            guard let category = OWASPCategory.category(forRule: ruleID) else { continue }
            let labelled = rows.contains { $0.contains("`\(ruleID)`") && $0.contains(category.rawValue) }
            XCTAssertTrue(labelled, "RuleCatalog.md has no row for \(ruleID) labelled \(category.rawValue)")
        }
    }
}

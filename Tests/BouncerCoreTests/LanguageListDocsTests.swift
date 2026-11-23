import XCTest
import Foundation
import BouncerCore

/// Keeps the language lists in the README, the landing page, and the docs overview in step with `Language`, so a
/// newly supported language can't be left out of the places people first read about Bouncer.
final class LanguageListDocsTests: XCTestCase {
    /// The pages that list every supported language, relative to the repository root.
    private static let pages = ["README.md", "Site/index.html", "Sources/BouncerCore/BouncerCore.docc/BouncerCore.md"]

    /// Every supported language. Adding a case to `Language` breaks the switch in `spellings(of:)`, a reminder to
    /// list it here too.
    private static let languages: [Language] = [
        .swift, .python, .zsh, .bash, .powershell, .typescript, .javascript, .cpp, .java, .go, .sql, .c, .objc,
        .rust, .php
    ]

    /// The names a page may use for a language; any one of them counts as listing it.
    ///
    /// - Parameter language: The language.
    /// - Returns: Its accepted spellings, or none for `.other`, which no page lists.
    private static func spellings(of language: Language) -> [String] {
        switch language {
        case .swift: ["Swift"]
        case .python: ["Python"]
        case .zsh: ["zsh", "shell"]
        case .bash: ["bash", "shell"]
        case .powershell: ["PowerShell"]
        case .typescript: ["TypeScript"]
        case .javascript: ["JavaScript"]
        case .cpp: ["C++"]
        case .java: ["Java,", "Java "]
        case .go: ["Go"]
        case .sql: ["SQL"]
        case .c: ["C,", "C "]
        case .objc: ["Objective-C"]
        case .rust: ["Rust"]
        case .php: ["PHP"]
        case .other: []
        }
    }

    /// Reads a page from the repository.
    ///
    /// - Parameter path: The page's path relative to the repository root.
    /// - Returns: Its text.
    private func page(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func testEveryPageNamesEverySupportedLanguage() throws {
        for path in Self.pages {
            let text = try page(path)
            for language in Self.languages {
                XCTAssertTrue(Self.spellings(of: language).contains { text.contains($0) }, "\(path) omits \(language)")
            }
        }
    }
}

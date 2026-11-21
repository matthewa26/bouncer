/// A source language Bouncer can analyze.
///
/// Swift, Python, Go, TypeScript, JavaScript, Objective-C, and Rust are analyzed through
/// a real syntax tree. Every other case is analyzed heuristically, and `.other` exists
/// so a file in an unrecognized language is still given a best-effort pass
/// instead of being skipped outright.
public enum Language: Hashable, Sendable {
    case swift
    case python
    case zsh
    case bash
    case powershell
    case typescript
    case javascript
    case cpp
    case java
    case go
    case sql
    case c
    /// Objective-C and Objective-C++ (`.m`, `.mm`, and `.h` headers that use Objective-C syntax).
    case objc
    /// Rust (`.rs`).
    case rust
    case other(String)
}

extension Language {
    /// The language each recognized file extension maps to.
    private static let byExtension: [String: Language] = [
        "swift": .swift, "py": .python, "zsh": .zsh, "sh": .bash, "bash": .bash,
        "ps1": .powershell, "psm1": .powershell,
        "ts": .typescript, "tsx": .typescript, "mts": .typescript, "cts": .typescript,
        "js": .javascript, "jsx": .javascript, "mjs": .javascript, "cjs": .javascript,
        "cpp": .cpp, "cc": .cpp, "cxx": .cpp, "hpp": .cpp, "hh": .cpp,
        "java": .java, "go": .go, "sql": .sql, "c": .c, "h": .c, "m": .objc, "mm": .objc,
        "rs": .rust
    ]

    /// Line openings that only Objective-C uses, which make a `.h` header Objective-C rather than C.
    private static let objcHeaderMarkers = [
        "@interface", "@protocol", "@class", "@import", "#import", "NS_ASSUME_NONNULL_BEGIN", "@property"
    ]

    /// Maps a file extension (without the leading dot) to the language that owns it.
    ///
    /// - Parameter fileExtension: The file's extension, case-insensitive.
    /// - Returns: The matching `Language`, or `.other` with the extension preserved.
    public static func from(fileExtension: String) -> Language {
        byExtension[fileExtension.lowercased()] ?? .other(fileExtension)
    }

    /// Maps a file to its language by extension, reading its contents where the extension is ambiguous.
    ///
    /// A `.h` header is shared by C, C++, and Objective-C, so one that opens a line with an Objective-C
    /// directive (`@interface`, `#import`, `NS_ASSUME_NONNULL_BEGIN`, …) is Objective-C and any other is C.
    /// Every other extension maps exactly as `from(fileExtension:)` maps it.
    ///
    /// - Parameters:
    ///   - fileExtension: The file's extension, case-insensitive.
    ///   - contents: The file's text.
    /// - Returns: The file's language.
    public static func from(fileExtension: String, contents: String) -> Language {
        let language = from(fileExtension: fileExtension)
        guard language == .c, fileExtension.lowercased() == "h" else { return language }
        return isObjectiveCHeader(contents) ? .objc : .c
    }

    /// Reports whether a header's text uses Objective-C: a line that starts with one of its directives.
    ///
    /// - Parameter contents: The header's text.
    /// - Returns: Whether any line opens with an Objective-C marker.
    static func isObjectiveCHeader(_ contents: String) -> Bool {
        contents.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            return objcHeaderMarkers.contains { trimmed.hasPrefix($0) }
        }
    }
}

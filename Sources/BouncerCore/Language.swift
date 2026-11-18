/// A source language Bouncer can analyze.
///
/// Swift, Python, Go, TypeScript, and JavaScript are analyzed through a real
/// syntax tree. Every other case is analyzed heuristically, and `.other` exists
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
        "java": .java, "go": .go, "sql": .sql, "c": .c, "h": .c
    ]

    /// Maps a file extension (without the leading dot) to the language that owns it.
    ///
    /// - Parameter fileExtension: The file's extension, case-insensitive.
    /// - Returns: The matching `Language`, or `.other` with the extension preserved.
    public static func from(fileExtension: String) -> Language {
        byExtension[fileExtension.lowercased()] ?? .other(fileExtension)
    }
}

import BouncerCore

extension HTMLReportData {
    /// A run of consecutive source lines from one file, encoded as `[firstLine, [line, …]]`. A line cut for
    /// length ends with `HTMLSourceExcerpts.truncationMark`.
    struct Chunk: Encodable, Equatable {
        /// The 1-based number of the run's first line.
        let start: Int
        /// The lines, in order.
        let lines: [String]

        /// Writes the run as a JSON array.
        ///
        /// - Parameter encoder: The encoder.
        /// - Throws: Any error the encoder raises.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(start)
            try container.encode(lines)
        }
    }

    /// A finding's quick fix, encoded as `[startLine, [removed, …], [added, …]]` and appended to its row.
    struct Fix: Encodable, Equatable {
        /// The 1-based line the edit starts at.
        let startLine: Int
        /// The lines the edit removes, prepared for display.
        let removed: [String]
        /// The lines that replace them, prepared for display.
        let added: [String]

        /// Creates the embedded form of a fix.
        ///
        /// - Parameters:
        ///   - fix: The fix.
        ///   - display: Prepares each line for display.
        init(_ fix: QuickFix, display: (String) -> String) {
            (startLine, removed, added) = (fix.startLine, fix.removed.map(display), fix.added.map(display))
        }

        /// Writes the fix as a JSON array.
        ///
        /// - Parameter encoder: The encoder.
        /// - Throws: Any error the encoder raises.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(startLine)
            try container.encode(removed)
            try container.encode(added)
        }
    }

    /// A rule's generic example, encoded as `[language, before, after]`.
    struct Example: Encodable, Equatable {
        /// The example's language, as its fence names it.
        let language: String
        /// The code the rule reports.
        let before: String
        /// The same code, fixed.
        let after: String

        /// Creates the embedded form of an example.
        ///
        /// - Parameter example: The example.
        init(_ example: RuleExample) {
            (language, before, after) = (example.language, example.before, example.after)
        }

        /// Writes the example as a JSON array.
        ///
        /// - Parameter encoder: The encoder.
        /// - Throws: Any error the encoder raises.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            try container.encode(language)
            try container.encode(before)
            try container.encode(after)
        }
    }
}

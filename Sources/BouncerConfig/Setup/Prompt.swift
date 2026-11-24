import Foundation
#if os(Windows)
import ucrt
#endif

/// Why an interactive prompt stopped without an answer.
public enum PromptError: Error, Equatable, CustomStringConvertible {
    /// Input ended (EOF or Ctrl-D) before the question was answered.
    case endOfInput

    /// A human-readable explanation.
    public var description: String { "Input ended before every question was answered; nothing was written." }
}

/// One option of a described choice: a short label, and a line saying what picking it means.
public struct PromptOption: Sendable, Equatable {
    /// The option's name, shown after its number.
    public let label: String
    /// What picking it means, shown indented below the label; each of its lines is indented the same.
    public let detail: String

    /// Creates an option.
    ///
    /// - Parameters:
    ///   - label: The option's name.
    ///   - detail: What picking it means.
    public init(_ label: String, detail: String) {
        self.label = label
        self.detail = detail
    }
}

/// Line-oriented terminal questions with defaults, validation, and re-asking on bad input.
///
/// Input and output are injected so a scripted session can drive it in tests. A blank answer takes the
/// default; an invalid one is explained and asked again; end of input throws `PromptError.endOfInput`, so a
/// caller can abort cleanly instead of acting on half an answer set.
public struct Prompt {
    private let readLine: () -> String?
    private let write: (String) -> Void

    /// Creates a prompt over arbitrary line input and text output.
    ///
    /// - Parameters:
    ///   - readLine: Returns the next input line without its newline, or `nil` at end of input.
    ///   - write: Writes text verbatim, without adding a newline.
    public init(readLine: @escaping () -> String?, write: @escaping (String) -> Void) {
        self.readLine = readLine
        self.write = write
    }

    /// A prompt over standard input and standard output.
    ///
    /// Every write is flushed, so a question that doesn't end in a newline shows before the read that waits for its
    /// answer. glibc and Darwin flush standard output before reading a terminal, but musl, which the static Linux
    /// build uses, doesn't, so on Linux and WSL the wizard looked hung.
    public static var standard: Prompt {
        Prompt(readLine: { Swift.readLine() }, write: { print($0, terminator: ""); fflush(nil) })
    }

    /// Writes one line of text.
    ///
    /// - Parameter text: The line, without a trailing newline.
    public func say(_ text: String) {
        write(text + "\n")
    }

    /// Asks the user to pick one of several options, by number or by name.
    ///
    /// - Parameters:
    ///   - question: The question text.
    ///   - options: The options, listed and numbered from 1.
    ///   - defaultOption: The option a blank answer picks; it should be one of `options`.
    /// - Returns: The chosen option.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    public func choice(_ question: String, options: [String], default defaultOption: String) throws -> String {
        say(question)
        for (index, option) in options.enumerated() { say("  \(index + 1)) \(option)") }
        return try ask("Choose", hint: "[\(defaultOption)]", fallback: defaultOption) { answer in
            Int(answer).flatMap { options.indices.contains($0 - 1) ? options[$0 - 1] : nil }
                ?? options.first { $0.caseInsensitiveCompare(answer) == .orderedSame }
        }
    }

    /// Asks the user to pick one of several options, each explained on its own line, by number.
    ///
    /// - Parameters:
    ///   - question: The question text.
    ///   - options: The options, listed as `1. label` with each line of their detail indented below.
    ///   - defaultIndex: The index of the option a blank answer picks.
    /// - Returns: The chosen option's index.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    public func choice(_ question: String, described options: [PromptOption], default defaultIndex: Int) throws -> Int {
        say(question)
        for (index, option) in options.enumerated() {
            say("  \(index + 1). \(option.label)")
            option.detail.split(separator: "\n").forEach { say("     \($0)") }
        }
        return try ask("Choose", hint: "[\(defaultIndex + 1)]", fallback: defaultIndex) { answer in
            Int(answer).flatMap { options.indices.contains($0 - 1) ? $0 - 1 : nil }
        }
    }

    /// Asks for a whole number within a range.
    ///
    /// - Parameters:
    ///   - question: The question text.
    ///   - defaultValue: The value a blank answer picks.
    ///   - range: The accepted values.
    /// - Returns: The entered number.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    public func integer(_ question: String, default defaultValue: Int, range: ClosedRange<Int>) throws -> Int {
        let hint = "(\(range.lowerBound)-\(range.upperBound)) [\(defaultValue)]"
        return try ask(question, hint: hint, fallback: defaultValue) { answer in
            Int(answer).flatMap { range.contains($0) ? $0 : nil }
        }
    }

    /// Asks a yes-or-no question.
    ///
    /// - Parameters:
    ///   - question: The question text.
    ///   - defaultValue: The answer a blank line picks.
    /// - Returns: `true` for yes.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    public func yesNo(_ question: String, default defaultValue: Bool) throws -> Bool {
        try ask(question, hint: defaultValue ? "[Y/n]" : "[y/N]", fallback: defaultValue) { answer in
            switch answer.lowercased() {
            case "y", "yes": return true
            case "n", "no": return false
            default: return nil
            }
        }
    }

    /// Asks for free text.
    ///
    /// - Parameters:
    ///   - question: The question text.
    ///   - defaultValue: The text a blank answer picks (shown unless empty); `nil` makes an answer required.
    /// - Returns: The entered text, trimmed of surrounding whitespace.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    public func text(_ question: String, default defaultValue: String?) throws -> String {
        let hint = defaultValue.map { $0.isEmpty ? "" : "[\($0)]" } ?? ""
        return try ask(question, hint: hint, fallback: defaultValue) { $0 }
    }

    /// Asks one question until it gets a blank (default) or parseable answer.
    ///
    /// - Parameters:
    ///   - question: The question text.
    ///   - hint: The bracketed default or format hint shown after the question.
    ///   - fallback: The value for a blank answer; `nil` makes an answer required.
    ///   - parse: Converts a trimmed, non-blank answer, or returns `nil` to reject it.
    /// - Returns: The parsed answer or the fallback.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private func ask<T>(_ question: String, hint: String, fallback: T?, parse: (String) -> T?) throws -> T {
        while true {
            write(hint.isEmpty ? "\(question): " : "\(question) \(hint): ")
            guard let line = readLine() else { write("\n"); throw PromptError.endOfInput }
            let answer = line.trimmingCharacters(in: .whitespaces)
            if answer.isEmpty, let fallback { return fallback }
            if !answer.isEmpty, let value = parse(answer) { return value }
            say(answer.isEmpty ? "  An answer is required." : "  \"\(answer)\" isn't a valid answer; try again.")
        }
    }
}

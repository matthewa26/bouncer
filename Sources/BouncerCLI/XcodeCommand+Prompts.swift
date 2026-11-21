#if canImport(XcodeProj)
import ArgumentParser
import Foundation
import BouncerConfig
import BouncerXcode

/// Asks which targets `bouncer xcode install` should add its phase to, when `--target` wasn't given.
enum XcodeTargetPicker {
    /// Lists the project's targets and asks for comma-separated numbers, defaulting to every non-test target.
    ///
    /// - Parameter editor: The opened project.
    /// - Returns: The chosen target names.
    /// - Throws: `ValidationError` without a terminal to ask on, or `PromptError.endOfInput`.
    static func choose(from editor: XcodeProjectEditor) throws -> [String] {
        let names = editor.targetNames
        guard Terminal.standardInputIsInteractive else {
            throw ValidationError("Pass --target <name> (repeatable). Targets: \(names.joined(separator: ", ")).")
        }
        let prompt = Prompt.standard
        prompt.say("Which targets should run Bouncer on every build?")
        names.enumerated().forEach { prompt.say("  \($0.offset + 1)) \($0.element)") }
        let defaults = editor.defaultTargetNames.compactMap { names.firstIndex(of: $0) }.map { String($0 + 1) }
        return try ask(prompt, names: names, defaultAnswer: defaults.joined(separator: ","))
    }

    /// Asks until the answer is a valid list of target numbers.
    ///
    /// - Parameters:
    ///   - prompt: Where to ask.
    ///   - names: The numbered targets.
    ///   - defaultAnswer: The numbers a blank answer picks.
    /// - Returns: The chosen target names.
    /// - Throws: `PromptError.endOfInput` if input ends first.
    private static func ask(_ prompt: Prompt, names: [String], defaultAnswer: String) throws -> [String] {
        while true {
            let answer = try prompt.text("Targets (comma-separated numbers)", default: defaultAnswer)
            if let chosen = parse(answer, names: names) { return chosen }
            prompt.say("  \"\(answer)\" isn't a list of numbers from 1 to \(names.count); try again.")
        }
    }

    /// Reads a comma-separated list of 1-based target numbers.
    ///
    /// - Parameters:
    ///   - answer: The typed answer, such as `1, 3`.
    ///   - names: The numbered targets.
    /// - Returns: The named targets, each once, or `nil` if any entry isn't a listed number or none were given.
    static func parse(_ answer: String, names: [String]) -> [String]? {
        let entries = answer.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let indices = entries.compactMap { Int($0) }.filter { names.indices.contains($0 - 1) }
        guard !indices.isEmpty, indices.count == entries.count else { return nil }
        var seen = Set<Int>()
        return indices.filter { seen.insert($0).inserted }.map { names[$0 - 1] }
    }
}
#endif

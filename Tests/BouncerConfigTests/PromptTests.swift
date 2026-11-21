import XCTest
@testable import BouncerConfig

/// A scripted terminal: answers come from `lines`, everything written lands in `output`.
final class ScriptedTerminal {
    var lines: [String]
    var output = ""

    init(_ lines: [String]) {
        self.lines = lines
    }

    var prompt: Prompt {
        Prompt(readLine: { [self] in lines.isEmpty ? nil : lines.removeFirst() }, write: { [self] in output += $0 })
    }
}

final class PromptTests: XCTestCase {
    func testChoiceAcceptsNumberNameOrBlankDefault() throws {
        let terminal = ScriptedTerminal(["2", "QUIET", ""])
        let options = ["normal", "verbose", "quiet"]
        XCTAssertEqual(try terminal.prompt.choice("Pick", options: options, default: "normal"), "verbose")
        XCTAssertEqual(try terminal.prompt.choice("Pick", options: options, default: "normal"), "quiet")
        XCTAssertEqual(try terminal.prompt.choice("Pick", options: options, default: "normal"), "normal")
        XCTAssertTrue(terminal.output.contains("  2) verbose"))
    }

    func testChoiceReasksOnInvalidAnswer() throws {
        let terminal = ScriptedTerminal(["9", "nope", "1"])
        XCTAssertEqual(try terminal.prompt.choice("Pick", options: ["a", "b"], default: "b"), "a")
        XCTAssertEqual(terminal.output.components(separatedBy: "isn't a valid answer").count, 3)
    }

    func testIntegerEnforcesRangeAndDefaults() throws {
        let terminal = ScriptedTerminal(["0", "abc", "25", ""])
        XCTAssertEqual(try terminal.prompt.integer("Max", default: 40, range: 1...100), 25)
        XCTAssertEqual(try terminal.prompt.integer("Max", default: 40, range: 1...100), 40)
        XCTAssertTrue(terminal.output.contains("Max (1-100) [40]: "))
    }

    func testYesNo() throws {
        let terminal = ScriptedTerminal(["y", "NO", "", "maybe", "yes"])
        XCTAssertTrue(try terminal.prompt.yesNo("Ok?", default: false))
        XCTAssertFalse(try terminal.prompt.yesNo("Ok?", default: true))
        XCTAssertFalse(try terminal.prompt.yesNo("Ok?", default: false))
        XCTAssertTrue(try terminal.prompt.yesNo("Ok?", default: false))
    }

    func testTextWithoutDefaultRequiresAnAnswer() throws {
        let terminal = ScriptedTerminal(["", "  team  "])
        XCTAssertEqual(try terminal.prompt.text("Name", default: nil), "team")
        XCTAssertTrue(terminal.output.contains("An answer is required."))
    }

    func testEndOfInputThrows() {
        let terminal = ScriptedTerminal([])
        XCTAssertThrowsError(try terminal.prompt.yesNo("Ok?", default: true)) { error in
            XCTAssertEqual(error as? PromptError, .endOfInput)
        }
    }
}

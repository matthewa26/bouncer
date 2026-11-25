import XCTest

final class RulesCommandTests: XCTestCase {
    private func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = try BouncerBinary.url()
        process.arguments = ["rules"] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testListsRulesBySectionWithTheirDefaultSeverity() throws {
        let (status, output) = try run([])
        XCTAssertEqual(status, 0, output)
        XCTAssertTrue(output.hasPrefix("Code smells\n  file-length "), output)
        XCTAssertNotNil(output.range(of: #"\n  long-function +warning\n"#, options: .regularExpression), output)
        XCTAssertTrue(output.contains("Run bouncer rules <id>"), output)
    }

    func testExplainsOneRule() throws {
        let (status, output) = try run(["force-unwrap"])
        XCTAssertEqual(status, 0, output)
        XCTAssertTrue(output.hasPrefix("force-unwrap (rule catalog: "), output)
        XCTAssertTrue(output.contains("// bouncer:disable-line force-unwrap -- reason"), output)
    }

    func testUnknownRuleFailsWithASuggestion() throws {
        let (status, output) = try run(["long-functon"])
        XCTAssertNotEqual(status, 0)
        XCTAssertTrue(output.contains("Did you mean: long-function?"), output)
    }
}

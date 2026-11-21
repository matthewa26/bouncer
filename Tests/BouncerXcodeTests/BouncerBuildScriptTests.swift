import XCTest
import Foundation
@testable import BouncerXcode

final class BouncerBuildScriptTests: XCTestCase {
    func testScriptStartsWithTheMarkerAndExtendsPath() {
        let lines = BouncerBuildScript(scope: .review, failOn: .error).text.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], BouncerBuildScript.marker)
        XCTAssertEqual(lines[1], "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH\"")
        XCTAssertTrue(BouncerBuildScript.isBouncerScript(lines.joined(separator: "\n")))
        XCTAssertFalse(BouncerBuildScript.isBouncerScript("swiftlint"))
        XCTAssertFalse(BouncerBuildScript.isBouncerScript(nil))
    }

    func testMissingBouncerOnlyWarns() {
        let text = BouncerBuildScript(scope: .review, failOn: .error).text
        XCTAssertTrue(text.contains("if ! command -v bouncer >/dev/null 2>&1; then\n"
            + "  echo \"warning: Bouncer isn't installed; see https://matthewa26.github.io/bouncer/\"\n  exit 0\nfi"))
    }

    func testSandboxedBuildsWarnInsteadOfPassingSilently() {
        let text = BouncerBuildScript(scope: .review, failOn: .error).text
        XCTAssertTrue(text.contains("if [ \"$ENABLE_USER_SCRIPT_SANDBOXING\" = YES ]; then\n  echo \"warning: "))
    }

    func testScopeAndFailOnPickTheCommand() {
        let flags = "--format xcode --progress off --no-update-check"
        XCTAssertEqual(BouncerBuildScript(scope: .review, failOn: .error).command,
                       "bouncer review \"$SRCROOT\" --exclude '**/*.xcodeproj/**' \(flags) --severity-threshold error")
        XCTAssertEqual(BouncerBuildScript(scope: .check, failOn: .warning).command,
                       "bouncer check \(flags) --severity-threshold warning")
    }

    func testNeverRewritesErrorsAsWarningsAndSucceeds() {
        let command = BouncerBuildScript(scope: .check, failOn: .never).command
        XCTAssertTrue(command.hasPrefix("bouncer check --format xcode"))
        XCTAssertTrue(command.contains("| sed -E 's/^(.+:[0-9]+:[0-9]+): error: /\\1: warning: /'"))
        XCTAssertTrue(command.hasSuffix("\nexit 0"))
    }

    func testNeverRewriteMatchesXcodeDiagnostics() throws {
        #if os(Windows)
        throw XCTSkip("The build script runs in Xcode's /bin/sh, which Windows doesn't have.")
        #endif
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '/a b/c.swift:3:1: error: x [r]\\nsummary error: y\\n' | "
            + "sed -E 's/^(.+:[0-9]+:[0-9]+): error: /\\1: warning: /'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(output, "/a b/c.swift:3:1: warning: x [r]\nsummary error: y\n")
    }
}

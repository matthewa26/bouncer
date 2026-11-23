import XCTest

/// The parts of an `initialize` result the test reads.
private struct InitializeResult: Decodable {
    struct ServerInfo: Decodable {
        let name: String
    }

    let serverInfo: ServerInfo
    let instructions: String?
}

/// The parts of a `tools/list` result the test reads.
private struct ToolsListResult: Decodable {
    struct Tool: Decodable {
        let name: String
        let inputSchema: Schema?
    }

    struct Schema: Decodable {
        let properties: [String: Ignored]?
    }

    /// Any JSON value, decoded only to learn that it's there.
    struct Ignored: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    let tools: [Tool]
}

/// Drives the built `bouncer mcp` through a whole agent session against a throwaway git repository and checks every
/// response: each stdout line must be one JSON-RPC response, and nothing else may reach stdout.
final class MCPEndToEndTests: XCTestCase {
    private var repo: FixtureRepo?
    private var server: MCPSession?

    override func setUpWithError() throws {
        let fixture = try FixtureRepo.make()
        repo = fixture
        server = try MCPSession(binary: BouncerBinary.url(), fixture: fixture)
    }

    override func tearDown() {
        server?.kill()
        repo?.remove()
        super.tearDown()
    }

    func testAgentSessionOverStdio() throws {
        try checkInitialize()
        try checkToolsList()
        try checkFirstScan()
        try checkFindingsPaging()
        try checkNextBatch()
        try checkNextBatchFilters()
        try checkVerify()
        try checkExplainRule()
        try checkCommitCheck()
        try checkImmediateRefresh()
        try checkCleanExit()
    }

    // MARK: - Steps

    private func checkInitialize() throws {
        let client = ["name": "test-mcp", "version": "0"]
        let params: [String: Any] = ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": client]
        let result = try session().request("initialize", params, as: InitializeResult.self)
        try expect(result.serverInfo.name == "bouncer", "initialize names the server")
        try expect((result.instructions ?? "").contains("scan"), "initialize teaches the loop")
        try session().notify("notifications/initialized")
    }

    private func checkToolsList() throws {
        let list = try session().request("tools/list", as: ToolsListResult.self).tools
        let names: Set = ["scan", "status", "findings", "next_batch", "verify", "check", "explain_rule"]
        try expect(Set(list.map(\.name)) == names, "tools/list: \(list.map(\.name).sorted())")
        let findings = list.last { $0.name == "findings" }
        try expect(findings?.inputSchema?.properties?["cursor"] != nil, "findings takes a cursor")
    }

    private func checkFirstScan() throws {
        let early = try call("findings")
        try expect(early.isError && early.text.contains("No scan yet. Call scan first."),
                   "findings before a scan is an error")
        let summary = try scanToEnd()
        try expect(!summary.isError && summary.text.contains("findings:") && summary.text.contains("Results from"),
                   "status ends with the summary")
        try expect(summary.text.contains("force-unwrap"), "the summary names the top rules")
    }

    private func checkFindingsPaging() throws {
        let first = try call("findings", ["max_chars": 220])
        try expect(length(first) <= 220, "findings fits max_chars")
        try expect(first.text.contains("Next cursor: f"), "a truncated page names the next cursor")
        let cursor = try XCTUnwrap(first.text.components(separatedBy: "Next cursor: ").last)
        let second = try call("findings", ["max_chars": 220, "cursor": trimmingTrailingDots(cursor)])
        try expect(!second.isError && length(second) <= 220 && second.text.contains("Showing"),
                   "the cursor fetches the next page")
        let filtered = try call("findings", ["rule": ["force-unwrap"], "severity": "error"])
        try expect(filtered.text.contains("Sources/Unwrap.swift") && !filtered.text.contains("magic-number"),
                   "findings filters by rule and severity")
    }

    private func checkNextBatch() throws {
        let batch = try call("next_batch")
        let lines = batch.text.components(separatedBy: "\n")
        try expect(!batch.isError && lines[0].hasPrefix("Results from"), "next_batch opens with the result's age")
        try expect(lines.count > 1, "next_batch header")
        let header = lines[1]
        try expect(header.hasPrefix("Sources/") && header.contains(" · ") && header.contains("clusters left"),
                   "next_batch header")
        try expect(header.contains("(mechanical, error)") && header.contains("force-unwrap"),
                   "next_batch picks the error cluster first")
        try expect(lines.contains { $0.contains("| ") }, "next_batch shows numbered code lines")
        try expect(lines[lines.count - 1].hasPrefix("Next: fix these, then call verify"),
                   "next_batch ends with the verify call")
    }

    private func checkNextBatchFilters() throws {
        let cut = try call("next_batch", ["rule": "magic-number", "max_chars": 450])
        try expect(!cut.isError && length(cut) <= 450 && cut.text.contains("| "),
                   "next_batch fits max_chars and still shows code")
        try expect(cut.text.contains("Sources/Many.swift · magic-number"), "next_batch filters by rule")
        try expect(cut.text.contains("more in this cluster: call findings with rule magic-number"),
                   "a cut cluster says how to get the rest")
        let none = try call("next_batch", ["rule": "no-such-rule"])
        try expect(!none.isError && none.text.contains("Nothing left to fix"), "next_batch with nothing matching")
        let bad = try call("findings", ["severity": "fatal"])
        try expect(bad.isError && bad.text.contains("severity must be one of"), "a bad argument is an error")
    }

    private func checkVerify() throws {
        try fixture().write("Sources/Unwrap.swift", FixtureRepo.docs("Reads a value.", returns: "The value, or 0.")
            + "func read(_ value: Int?) -> Int {\n    value ?? 0\n}\n")
        let verified = try call("verify", ["files": ["Sources/Unwrap.swift"]])
        try expect(!verified.isError && verified.text.contains("1 fixed") && verified.text.contains("0 new"),
                   "verify reports the fixed finding")
        try expect(verified.text.contains("refresh on the next scan"), "verify notes project-wide rules")
        let after = try call("findings", ["rule": "force-unwrap"])
        try expect(!after.text.contains("Sources/Unwrap.swift") && after.text.contains("5 findings"),
                   "verify updated the in-memory result")
    }

    private func checkExplainRule() throws {
        let known = try call("explain_rule", ["id": "force-unwrap"])
        try expect(!known.isError && known.text.contains("force-unwrap"), "explain_rule explains a known rule")
        let typo = try call("explain_rule", ["id": "force-unwarp"])
        try expect(typo.isError && typo.text.contains("Did you mean") && typo.text.contains("force-unwrap"),
                   "explain_rule suggests close IDs")
    }

    private func checkCommitCheck() throws {
        try fixture().write("Sources/Staged.swift", FixtureRepo.docs("Reads.", returns: "It.")
            + "func readAgain(_ value: Int?) -> Int {\n    value!\n}\n")
        try fixture().git(["add", "Sources/Staged.swift"])
        let blocked = try call("check")
        try expect(!blocked.isError && blocked.text.contains("would block the commit")
                   && blocked.text.contains("Sources/Staged.swift"), "check lists blockers")
        try fixture().git(["reset", "-q", "Sources/Staged.swift"])
        let clear = try call("check")
        try expect(!clear.isError && clear.text.contains("Nothing blocks the commit."), "check passes with nothing staged")
    }

    private func checkImmediateRefresh() throws {
        try fixture().write(".bouncer", #"{ "rules": { "force-unwrap": { "severity": "error" } }, "#
            + #""agent": { "refresh": "immediate" } }"#)
        let rescan = try scanToEnd()
        try expect(rescan.text.contains("reused findings for") && !rescan.text.contains("saved run not used"),
                   "the agent section keeps the saved run")
        try fixture().write("Sources/Alpha.swift", FixtureRepo.docs("Reads.", returns: "It.")
            + "func readAlpha(_ value: Int?) -> Int {\n    value ?? 1\n}\n")
        let refreshed = try call("findings", ["rule": "force-unwrap"])
        try expect(refreshed.text.hasPrefix("Re-checked 1 changed file.")
                   && !refreshed.text.contains("Sources/Alpha.swift"), "immediate refresh")
        let status = try call("status")
        try expect(status.text.hasPrefix("Results are current."), "immediate refresh with nothing changed")
    }

    private func checkCleanExit() throws {
        let (rest, status) = try session().finish()
        try expect(rest.isEmpty, "stdout holds nothing but responses: \(rest.debugDescription)")
        try expect(status == 0, "the server exits cleanly at end of input (status \(status))")
    }

    // MARK: - Helpers

    private func session() throws -> MCPSession {
        try XCTUnwrap(server, "the server didn't start")
    }

    private func fixture() throws -> FixtureRepo {
        try XCTUnwrap(repo, "the fixture wasn't created")
    }

    private func call(_ name: String, _ arguments: [String: Any] = [:]) throws -> ToolReply {
        try session().call(name, arguments)
    }

    /// How long a scan may take before the test gives up, generous for a slow CI machine or VM.
    private static let scanDeadline: TimeInterval = 120
    /// The pause between status polls, so a slow scan is waited on by time rather than by a count of calls.
    private static let pollInterval: TimeInterval = 0.1

    /// Starts a scan and polls status until it stops reporting progress or the deadline passes.
    private func scanToEnd() throws -> ToolReply {
        var reply = try call("scan")
        let deadline = Date().addingTimeInterval(Self.scanDeadline)
        while reply.text.hasPrefix("Scanning"), Date() < deadline {
            Thread.sleep(forTimeInterval: Self.pollInterval)
            reply = try call("status")
        }
        return reply
    }

    /// A reply's length in Unicode scalars, which is never less than its `Character` count, so a budget check on it is
    /// at least as strict as the server's own.
    private func length(_ reply: ToolReply) -> Int {
        reply.text.unicodeScalars.count
    }

    private func trimmingTrailingDots(_ text: String) -> String {
        String(text.reversed().drop { $0 == "." }.reversed())
    }

    /// Fails the test with the last tool reply and the server's stderr when a condition doesn't hold.
    private func expect(_ condition: Bool, _ message: String) throws {
        guard !condition else { return }
        let reply = server?.lastReply
        throw EndToEndFailure("""
            \(message)
            --- last reply\(reply?.isError == true ? " [error]" : ""):
            \(reply?.text ?? "<none>")
            --- server stderr:
            \(server?.stderr ?? "")
            """)
    }
}

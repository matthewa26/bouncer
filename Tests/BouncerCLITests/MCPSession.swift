import Foundation

/// What a `tools/call` returned: the first content block's text and whether the tool reported an error.
struct ToolReply {
    let text: String
    let isError: Bool
}

/// The parts of a `tools/call` result the test reads.
private struct ToolCallResult: Decodable {
    struct Content: Decodable {
        let text: String
    }

    let content: [Content]
    let isError: Bool
}

/// A JSON-RPC response whose `result` decodes as `Result`.
private struct Response<Result: Decodable>: Decodable {
    let result: Result
}

/// A running `bouncer mcp` server, driven over newline-delimited JSON-RPC on its stdin and stdout.
final class MCPSession {
    /// How long any one response, or the exit at end of input, may take.
    static let timeout: TimeInterval = 60

    private let process = Process()
    private let input = Pipe()
    private let output: PipeReader
    private let errors: PipeReader
    private let exited = DispatchSemaphore(value: 0)
    private var nextID = 0
    /// The most recent tool reply, for failure messages.
    private(set) var lastReply = ToolReply(text: "<none>", isError: false)

    /// Launches `bouncer mcp` on a repository.
    ///
    /// - Parameters:
    ///   - binary: The `bouncer` executable.
    ///   - fixture: The repository to serve; the server runs inside it, with its home directory.
    init(binary: URL, fixture: FixtureRepo) throws {
        #if !os(Windows)
        // A server that dies mid-test must fail the write, not kill the test runner with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        #endif
        let stdout = Pipe(), stderr = Pipe()
        process.executableURL = binary
        process.arguments = ["mcp", fixture.repo.path]
        process.currentDirectoryURL = fixture.repo
        process.environment = fixture.environment
        process.standardInput = input
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [exited] _ in exited.signal() }
        try process.run()
        output = PipeReader(stdout.fileHandleForReading)
        errors = PipeReader(stderr.fileHandleForReading)
    }

    /// What the server has written to stderr so far.
    var stderr: String {
        errors.unread
    }

    /// Sends a request and decodes its result, after checking the response is the JSON-RPC reply to this request.
    func request<Result: Decodable>(_ method: String, _ params: [String: Any]? = nil, as type: Result.Type) throws
        -> Result {
        nextID += 1
        try write(["jsonrpc": "2.0", "method": method, "id": nextID].merging(params.map { ["params": $0] } ?? [:]) { $1 })
        let line: String
        do {
            line = try output.nextLine(within: Self.timeout)
        } catch {
            throw EndToEndFailure("\(error) waiting for the reply to \(method) \(params.map { "\($0)" } ?? "")")
        }
        let envelope = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        guard let envelope else { throw EndToEndFailure("stdout line isn't JSON: \(line.debugDescription)") }
        guard envelope["id"] as? Int == nextID, envelope["jsonrpc"] as? String == "2.0" else {
            throw EndToEndFailure("unexpected response: \(line.debugDescription)")
        }
        return try JSONDecoder().decode(Response<Result>.self, from: Data(line.utf8)).result
    }

    /// Sends a notification, which gets no response.
    func notify(_ method: String) throws {
        try write(["jsonrpc": "2.0", "method": method])
    }

    /// Calls a tool.
    ///
    /// - Parameters:
    ///   - name: The tool's name.
    ///   - arguments: Its arguments.
    /// - Returns: The tool's text and error flag.
    @discardableResult
    func call(_ name: String, _ arguments: [String: Any] = [:]) throws -> ToolReply {
        let result = try request("tools/call", ["name": name, "arguments": arguments], as: ToolCallResult.self)
        guard let first = result.content.first else { throw EndToEndFailure("\(name) returned no content") }
        lastReply = ToolReply(text: first.text, isError: result.isError)
        return lastReply
    }

    /// Closes stdin, then collects whatever else reached stdout and the exit status.
    ///
    /// - Returns: Stdout after the last response, and the exit status.
    /// - Throws: `EndToEndFailure` when stdout stays open or the server doesn't exit in time.
    func finish() throws -> (rest: String, status: Int32) {
        try input.fileHandleForWriting.close()
        let rest = try output.remainder(within: Self.timeout)
        guard exited.wait(timeout: .now() + Self.timeout) == .success else {
            throw EndToEndFailure("the server didn't exit within \(Int(Self.timeout))s of end of input")
        }
        return (rest, process.terminationStatus)
    }

    /// Stops the server if it's still running.
    func kill() {
        if process.isRunning { process.terminate() }
    }

    private func write(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        try input.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
    }
}

import Foundation

/// A Model Context Protocol server that offers one handler's tools over JSON-RPC 2.0.
///
/// Messages are newline-delimited JSON, one per line, as the MCP stdio transport defines. The server answers
/// `initialize`, `ping`, `tools/list` and `tools/call`, ignores notifications, and handles requests one at a
/// time in the order they arrive.
public actor MCPServer {
    /// The newest protocol version the server speaks, offered when a client asks for one it doesn't.
    static let latestProtocolVersion = "2025-06-18"
    /// Every protocol version the server speaks, newest first.
    static let supportedProtocolVersions = [latestProtocolVersion, "2025-03-26", "2024-11-05"]

    /// Who the server is.
    private let info: MCPServerInfo
    /// The tools on offer and the code that runs them.
    private let handler: any MCPToolHandler

    /// Creates a server.
    ///
    /// - Parameters:
    ///   - info: Who the server is, for the `initialize` handshake.
    ///   - handler: The tools on offer and the code that runs them.
    public init(info: MCPServerInfo, handler: any MCPToolHandler) {
        self.info = info
        self.handler = handler
    }

    /// Handles one incoming line.
    ///
    /// - Parameter line: One line of input, with or without its line ending.
    /// - Returns: The response line to write, without a line ending, or `nil` for a notification or blank line.
    public func handle(line: String) async -> String? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let message = try? JSONValue.parse(text) else {
            return JSONRPCResponse.failure(.parseError, id: .null)
        }
        return await respond(to: message)
    }

    /// Answers a parsed message: a request with its response, a notification with nothing.
    ///
    /// - Parameter message: The parsed JSON.
    /// - Returns: The response line, or `nil` when there's nothing to answer.
    private func respond(to message: JSONValue) async -> String? {
        switch JSONRPCIncoming.classify(message) {
        case .request(let request): return await respond(to: request)
        case .silent: return nil
        case .rejected(let id, let error): return JSONRPCResponse.failure(error, id: id)
        }
    }

    /// Reads standard input line by line until it ends, writing each response to standard output.
    ///
    /// Input is read on a dedicated thread, so the blocking reads never hold a concurrency thread. Each
    /// response is written as one line and reaches the client at once; nothing else is written to standard
    /// output.
    public func serveStandardIO() async {
        for await line in StandardIO.inputLines() {
            guard let response = await handle(line: line) else { continue }
            StandardIO.writeLine(response)
        }
    }

    /// Answers a request with its result or an error.
    ///
    /// - Parameter request: The request.
    /// - Returns: The response line.
    private func respond(to request: JSONRPCRequest) async -> String {
        do {
            return JSONRPCResponse.success(try await result(for: request), id: request.id)
        } catch {
            return JSONRPCResponse.failure(error, id: request.id)
        }
    }

    /// Runs a request's method.
    ///
    /// - Parameter request: The request.
    /// - Returns: The method's result.
    /// - Throws: `JSONRPCError` for an unknown method or bad parameters.
    private func result(for request: JSONRPCRequest) async throws(JSONRPCError) -> JSONValue {
        switch request.method {
        case "initialize": return initializeResult(request.params)
        case "ping": return [:]
        case "tools/list": return ["tools": .array(handler.tools().map(\.listing))]
        case "tools/call": return try await callTool(request.params)
        default: throw .methodNotFound(request.method)
        }
    }

    /// The `initialize` result: the agreed protocol version, the server's capabilities, and who it is.
    ///
    /// - Parameter params: The request's parameters, whose `protocolVersion` is the client's preference.
    /// - Returns: The result.
    private func initializeResult(_ params: [String: JSONValue]) -> JSONValue {
        var result: [String: JSONValue] = [
            "protocolVersion": .string(Self.negotiatedVersion(params["protocolVersion"]?.stringValue)),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(info.name), "version": .string(info.version)]
        ]
        result["instructions"] = info.instructions.map(JSONValue.string)
        return .object(result)
    }

    /// Picks the protocol version to speak.
    ///
    /// - Parameter requested: The version the client asked for, if any.
    /// - Returns: The requested version when it's supported, or the newest supported one.
    static func negotiatedVersion(_ requested: String?) -> String {
        if let requested, supportedProtocolVersions.contains(requested) { return requested }
        return latestProtocolVersion
    }

    /// Runs a `tools/call` request.
    ///
    /// - Parameter params: The request's parameters: the tool's `name` and optional `arguments` object.
    /// - Returns: The tool's result as a `tools/call` result.
    /// - Throws: `JSONRPCError.invalidParams` for a missing or unknown tool name, or non-object arguments.
    private func callTool(_ params: [String: JSONValue]) async throws(JSONRPCError) -> JSONValue {
        guard let name = params["name"]?.stringValue else { throw .invalidParams("name must be a string") }
        guard handler.tools().contains(where: { $0.name == name }) else {
            throw .invalidParams("Unknown tool: \(name)")
        }
        let arguments = params["arguments"] ?? [:]
        guard let members = arguments.objectValue else { throw .invalidParams("arguments must be an object") }
        return await handler.call(name, arguments: members).response
    }
}

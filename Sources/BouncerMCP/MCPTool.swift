import Foundation

/// A tool the server offers, as `tools/list` describes it.
public struct MCPTool: Sendable, Equatable {
    /// The name a client calls the tool by.
    public let name: String
    /// What the tool does, for the model deciding whether to call it.
    public let description: String
    /// A JSON Schema object describing the tool's arguments.
    public let inputSchema: JSONValue

    /// Creates a tool description.
    ///
    /// - Parameters:
    ///   - name: The name a client calls the tool by.
    ///   - description: What the tool does.
    ///   - inputSchema: A JSON Schema object describing the tool's arguments.
    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    /// The tool as one entry of a `tools/list` result.
    var listing: JSONValue {
        ["name": .string(name), "description": .string(description), "inputSchema": inputSchema]
    }
}

/// What a tool call produced: one block of text, and whether it reports a failure.
public struct MCPToolResult: Sendable, Equatable {
    /// The text shown to the model.
    public let text: String
    /// Whether the call failed, which the model sees as a tool error rather than a protocol error.
    public let isError: Bool

    /// Creates a tool result.
    ///
    /// - Parameters:
    ///   - text: The text shown to the model.
    ///   - isError: Whether the call failed.
    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    /// The result as a `tools/call` result object.
    var response: JSONValue {
        ["content": [["type": "text", "text": .string(text)]], "isError": .bool(isError)]
    }
}

/// The tools a server offers and the code that runs them.
public protocol MCPToolHandler: Sendable {
    /// The tools on offer, in the order `tools/list` reports them.
    ///
    /// - Returns: The tools.
    func tools() -> [MCPTool]

    /// Runs one of the tools from `tools()`.
    ///
    /// - Parameters:
    ///   - name: The tool's name, which is always one `tools()` returned.
    ///   - arguments: The call's arguments, empty when the client sent none.
    /// - Returns: The tool's output, with `isError` set when it failed.
    func call(_ name: String, arguments: [String: JSONValue]) async -> MCPToolResult
}

/// Who the server is, as the `initialize` handshake reports it.
public struct MCPServerInfo: Sendable {
    /// The server's name.
    let name: String
    /// The server's version.
    let version: String
    /// Guidance for the client on how to use the server, or `nil` for none.
    let instructions: String?

    /// Creates the server's identity.
    ///
    /// - Parameters:
    ///   - name: The server's name.
    ///   - version: The server's version.
    ///   - instructions: Guidance for the client on how to use the server, or `nil` for none.
    public init(name: String, version: String, instructions: String? = nil) {
        self.name = name
        self.version = version
        self.instructions = instructions
    }
}

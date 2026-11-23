import BouncerMCP

/// The tools `bouncer mcp` offers, with JSON Schemas an agent reads to call them.
enum ToolSchemas {
    /// The JSON Schema type of a text argument.
    private static let stringType: JSONValue = "string"

    /// The severities, least severe first.
    private static let severities: JSONValue = ["info", "warning", "error"]

    /// A property schema.
    ///
    /// - Parameters:
    ///   - type: Its JSON Schema type.
    ///   - text: What it means.
    ///   - extra: More keywords, such as `enum` or `minimum`.
    /// - Returns: The schema.
    private static func property(_ type: JSONValue, _ text: String, _ extra: [String: JSONValue] = [:]) -> JSONValue {
        .object(extra.merging(["type": type, "description": .string(text)]) { _, new in new })
    }

    /// A string, or an array of strings.
    ///
    /// - Parameter text: What it holds.
    /// - Returns: The schema.
    private static func stringOrArray(_ text: String) -> JSONValue {
        let array: JSONValue = ["type": "array", "items": ["type": stringType]]
        return ["description": .string(text), "anyOf": [["type": stringType], array]]
    }

    /// An object schema.
    ///
    /// - Parameters:
    ///   - properties: Its properties.
    ///   - required: The required ones.
    /// - Returns: The schema.
    private static func object(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        ["type": "object", "properties": .object(properties), "required": .array(required.map(JSONValue.string))]
    }

    /// Adds the budget arguments every paged tool takes.
    ///
    /// - Parameter properties: The tool's own properties.
    /// - Returns: Them and `max_tokens` and `max_chars`.
    private static func budgeted(_ properties: [String: JSONValue]) -> [String: JSONValue] {
        let tokens = "Cap on the response, estimated at 4 characters per token. Default 2000."
        return properties.merging([
            "max_tokens": property("integer", tokens, ["minimum": 1]),
            "max_chars": property("integer", "Exact cap on the response, in characters.", ["minimum": 1])
        ]) { first, _ in first }
    }

    /// Every tool.
    static let all: [MCPTool] = [scan, status, findings, nextBatch, verify, check, explainRule]

    /// `scan`.
    private static let scan = MCPTool(
        name: "scan",
        description: "Analyze the repo (incrementally from the saved last run) and keep the result in memory. "
            + "Returns the summary if it finishes within a few seconds, otherwise progress; then call status.",
        inputSchema: object([
            "path": property(stringType, "Directory to scan, relative to the repo root. Default: the server's."),
            "profile": property(stringType, "A bundled or repo profile to apply, such as kirby."),
            "changed_since": property(stringType, "Only analyze files changed since this git revision, such as main."),
            "full": property("boolean", "Re-analyze every file, ignoring the saved last run.")
        ])
    )

    /// `status`.
    private static let status = MCPTool(
        name: "status",
        description: "Progress of a running scan, or the finished scan's summary and age.",
        inputSchema: object([:])
    )

    /// `findings`.
    private static let findings = MCPTool(
        name: "findings",
        description: "List findings from the last scan, one line each, grouped by file or rule. "
            + "When the answer is cut to the budget it ends with a cursor for the next page.",
        inputSchema: object(budgeted([
            "rule": stringOrArray("Only these rule IDs, such as force-unwrap."),
            "path": stringOrArray("Only files matching these globs, relative to the repo root, such as Sources/**."),
            "severity": property(stringType, "The least severe finding to list.", ["enum": severities]),
            "group_by": property(stringType, "Group under file (default) or rule.", ["enum": ["file", "rule"]]),
            "cursor": property(stringType, "The cursor the previous page ended with.")
        ]))
    )

    /// `next_batch`.
    private static let nextBatch = MCPTool(
        name: "next_batch",
        description: "The one file and rule to fix next, following the repo's work order, with the code around "
            + "each finding. Fix them, verify the file, and call next_batch again.",
        inputSchema: object(budgeted([
            "rule": stringOrArray("Only these rule IDs, such as force-unwrap."),
            "path": stringOrArray("Only files matching these globs, relative to the repo root, such as Sources/**.")
        ]))
    )

    /// `verify`.
    private static let verify = MCPTool(
        name: "verify",
        description: "Re-check files you edited with the per-file rules and update the result. "
            + "Returns only the delta: fixed, still there, and new findings.",
        inputSchema: object(
            budgeted(["files": stringOrArray("The files to re-check, relative to the repo root or absolute.")]),
            required: ["files"]
        )
    )

    /// `check`.
    private static let check = MCPTool(
        name: "check",
        description: "Run the pre-commit check on the staged git diff, change rules and baseline included. "
            + "Returns only the findings that would block the commit.",
        inputSchema: object(budgeted([:]))
    )

    /// `explain_rule`.
    private static let explainRule = MCPTool(
        name: "explain_rule",
        description: "Explain a rule: what it checks, why, how to fix it, and how to configure or suppress it.",
        inputSchema: object(["id": property(stringType, "The rule ID, such as force-unwrap.")], required: ["id"])
    )
}

import Foundation
import BouncerMCP

/// The `bouncer mcp` tools: lists them and routes each call to the session, turning every failure into an
/// error result with a one-line reason.
struct BouncerTools: MCPToolHandler {
    /// Runs one tool against the session.
    typealias Route = @Sendable (MCPSession, ToolArguments) async throws -> MCPAnswer

    /// Each tool's route, by name.
    private static let routes: [String: Route] = [
        "scan": { session, arguments in try await session.scan(ScanOptions(arguments)) },
        "status": { session, _ in try await session.status() },
        "findings": { session, arguments in try await session.findings(arguments) },
        "verify": { session, arguments in try await session.verify(arguments) },
        "check": { session, arguments in try await session.check(arguments) },
        "explain_rule": { _, arguments in try RuleExplainer.explain(arguments) }
    ]

    /// The session the tools answer from.
    let session: MCPSession

    /// The tools, with their argument schemas.
    ///
    /// - Returns: The tools.
    func tools() -> [MCPTool] {
        ToolSchemas.all
    }

    /// Runs one tool.
    ///
    /// - Parameters:
    ///   - name: The tool's name.
    ///   - arguments: Its arguments.
    /// - Returns: Its answer, or an error result.
    func call(_ name: String, arguments: [String: JSONValue]) async -> MCPToolResult {
        guard let route = Self.routes[name] else { return MCPToolResult(text: "Unknown tool \(name).", isError: true) }
        let start = ContinuousClock.now
        let result = await Self.run(route, session: session, arguments: ToolArguments(values: arguments))
        session.defaults.log.write("\(name) took \(ContinuousClock.now - start), \(result.text.count) chars")
        return result
    }

    /// Runs a route, catching its errors.
    ///
    /// - Parameters:
    ///   - route: The route.
    ///   - session: The session.
    ///   - arguments: The arguments.
    /// - Returns: The answer, or an error result.
    private static func run(_ route: Route, session: MCPSession, arguments: ToolArguments) async -> MCPToolResult {
        do {
            return MCPToolResult(text: try await route(session, arguments).text)
        } catch let error as ToolError {
            return MCPToolResult(text: error.message, isError: true)
        } catch {
            return MCPToolResult(text: ToolError.oneLine(error), isError: true)
        }
    }
}

extension ScanOptions {
    /// Reads a `scan` call's arguments.
    ///
    /// - Parameter arguments: `path`, `profile`, `changed_since`, and `full`.
    /// - Throws: `ToolError` for an argument of the wrong type, or `full` with `changed_since`.
    init(_ arguments: ToolArguments) throws {
        (path, profile) = (try arguments.string("path"), try arguments.string("profile"))
        (changedSince, full) = (try arguments.string("changed_since"), try arguments.bool("full"))
        if full, changedSince != nil { throw ToolError("full can't be combined with changed_since.") }
    }
}

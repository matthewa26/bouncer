import XCTest
@testable import BouncerMCP

/// A handler with one echoing tool and one that always fails.
private struct TestHandler: MCPToolHandler {
    func tools() -> [MCPTool] {
        [
            MCPTool(name: "echo", description: "Echoes its text argument.",
                    inputSchema: ["type": "object", "properties": ["text": ["type": "string"]]]),
            MCPTool(name: "fail", description: "Always fails.", inputSchema: ["type": "object"])
        ]
    }

    func call(_ name: String, arguments: [String: JSONValue]) async -> MCPToolResult {
        if name == "fail" { return MCPToolResult(text: "it broke", isError: true) }
        return MCPToolResult(text: arguments["text"]?.stringValue ?? "<none>")
    }
}

final class MCPServerTests: XCTestCase {
    private func server(instructions: String? = nil) -> MCPServer {
        MCPServer(info: MCPServerInfo(name: "test", version: "1.2.3", instructions: instructions),
                  handler: TestHandler())
    }

    /// Sends one line and parses the response line.
    private func send(_ line: String, to server: MCPServer? = nil) async throws -> JSONValue {
        let response = await (server ?? self.server()).handle(line: line)
        let text = try XCTUnwrap(response)
        XCTAssertFalse(text.contains("\n"))
        return try JSONValue.parse(text)
    }

    private func errorCode(_ response: JSONValue) -> Int? {
        response["error"]?["code"]?.intValue
    }

    func testInitializeEchoesASupportedVersion() async throws {
        let response = try await send(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#,
            to: server(instructions: "Use review."))
        XCTAssertEqual(response["jsonrpc"], "2.0")
        XCTAssertEqual(response["id"], 1)
        let result = try XCTUnwrap(response["result"])
        XCTAssertEqual(result["protocolVersion"], "2025-03-26")
        XCTAssertEqual(result["capabilities"], ["tools": ["listChanged": false]])
        XCTAssertEqual(result["serverInfo"], ["name": "test", "version": "1.2.3"])
        XCTAssertEqual(result["instructions"], "Use review.")
    }

    func testInitializeOffersTheLatestVersionForAnUnsupportedOne() async throws {
        let response = try await send(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        XCTAssertEqual(response["result"]?["protocolVersion"], "2025-06-18")
        XCTAssertNil(response["result"]?["instructions"])
    }

    func testInitializeWithoutParamsOffersTheLatestVersion() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
        XCTAssertEqual(response["result"]?["protocolVersion"], "2025-06-18")
    }

    func testPingReturnsAnEmptyObject() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)
        XCTAssertEqual(response["result"], [:])
    }

    func testToolsListDescribesEachTool() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#)
        let tools = try XCTUnwrap(response["result"]?["tools"]?.arrayValue)
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0], [
            "name": "echo", "description": "Echoes its text argument.",
            "inputSchema": ["type": "object", "properties": ["text": ["type": "string"]]]
        ])
        XCTAssertEqual(tools[1]["name"], "fail")
    }

    func testToolsCallReturnsTextContent() async throws {
        let response = try await send(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi\nthere"}}}"#)
        XCTAssertEqual(response["result"], ["content": [["type": "text", "text": "hi\nthere"]], "isError": false])
    }

    func testToolsCallWithoutArgumentsPassesAnEmptyObject() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo"}}"#)
        XCTAssertEqual(response["result"]?["content"]?.arrayValue?.first?["text"], "<none>")
    }

    func testToolsCallReportsAToolFailureAsIsError() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"fail"}}"#)
        XCTAssertEqual(response["result"]?["isError"], true)
        XCTAssertEqual(response["result"]?["content"]?.arrayValue?.first?["text"], "it broke")
        XCTAssertNil(response["error"])
    }

    func testUnknownToolIsInvalidParams() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope"}}"#)
        XCTAssertEqual(errorCode(response), -32602)
        XCTAssertEqual(response["id"], 5)
        XCTAssertNil(response["result"])
    }

    func testNonObjectArgumentsAreInvalidParams() async throws {
        let response = try await send(
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"echo","arguments":[1]}}"#)
        XCTAssertEqual(errorCode(response), -32602)
    }

    func testUnknownMethodIsMethodNotFound() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":6,"method":"resources/list"}"#)
        XCTAssertEqual(errorCode(response), -32601)
        XCTAssertEqual(response["id"], 6)
    }

    func testUnparseableLineIsAParseErrorWithNullID() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":1,"method""#)
        XCTAssertEqual(errorCode(response), -32700)
        XCTAssertEqual(response["id"], .null)
        XCTAssertEqual(response.objectValue?.keys.contains("id"), true)
    }

    func testNonObjectJSONIsAnInvalidRequest() async throws {
        for line in [#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#, "42", #""ping""#] {
            let response = try await send(line)
            XCTAssertEqual(errorCode(response), -32600, line)
            XCTAssertEqual(response["id"], .null, line)
        }
    }

    func testRequestWithoutMethodIsAnInvalidRequestUnderItsID() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":9}"#)
        XCTAssertEqual(errorCode(response), -32600)
        XCTAssertEqual(response["id"], 9)
    }

    func testNotificationsGetNoResponse() async {
        let server = server()
        for line in [
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#,
            #"{"jsonrpc":"2.0","method":"anything/else"}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{}}"#,
            "", "   ", "\r\n"
        ] {
            let response = await server.handle(line: line)
            XCTAssertNil(response, line)
        }
    }

    func testStringIDsAreEchoedExactly() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":"abc-1","method":"ping"}"#)
        XCTAssertEqual(response["id"], "abc-1")
    }

    func testNumberIDsAreEchoedAsIntegers() async throws {
        let text = await server().handle(line: #"{"jsonrpc":"2.0","id":42,"method":"ping"}"#)
        XCTAssertEqual(text, #"{"id":42,"jsonrpc":"2.0","result":{}}"#)
    }

    func testTrailingCarriageReturnIsIgnored() async throws {
        let response = try await send("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}\r")
        XCTAssertEqual(response["result"], [:])
    }

    func testNullIDIsAnInvalidRequest() async throws {
        let response = try await send(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#)
        XCTAssertEqual(errorCode(response), -32600)
    }
}

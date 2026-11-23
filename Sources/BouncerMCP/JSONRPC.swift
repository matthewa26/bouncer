import Foundation

/// A JSON-RPC 2.0 error, sent back in place of a result.
struct JSONRPCError: Error, Equatable {
    /// The line wasn't JSON.
    static let parseErrorCode = -32_700
    /// The JSON wasn't a request object.
    static let invalidRequestCode = -32_600
    /// The method isn't one the server knows.
    static let methodNotFoundCode = -32_601
    /// The method's parameters were wrong.
    static let invalidParamsCode = -32_602
    /// The server failed while answering.
    static let internalErrorCode = -32_603

    /// The standard error code.
    let code: Int
    /// A one-line description of what went wrong.
    let message: String

    /// The error for a line that isn't JSON.
    static let parseError = JSONRPCError(code: parseErrorCode, message: "Parse error")

    /// The error for JSON that isn't a valid request.
    ///
    /// - Parameter reason: What's wrong with it.
    /// - Returns: The error.
    static func invalidRequest(_ reason: String) -> JSONRPCError {
        JSONRPCError(code: invalidRequestCode, message: "Invalid request: \(reason)")
    }

    /// The error for a method the server doesn't implement.
    ///
    /// - Parameter method: The method's name.
    /// - Returns: The error.
    static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: methodNotFoundCode, message: "Method not found: \(method)")
    }

    /// The error for parameters the method can't use.
    ///
    /// - Parameter reason: What's wrong with them.
    /// - Returns: The error.
    static func invalidParams(_ reason: String) -> JSONRPCError {
        JSONRPCError(code: invalidParamsCode, message: "Invalid params: \(reason)")
    }
}

/// A request the server must answer.
struct JSONRPCRequest: Equatable {
    /// The id to echo in the response: a string or a number.
    let id: JSONValue
    /// The method's name.
    let method: String
    /// The parameters, empty when the request had none.
    let params: [String: JSONValue]
}

/// What one parsed message asks of the server.
enum JSONRPCIncoming: Equatable {
    /// A request to answer.
    case request(JSONRPCRequest)
    /// A notification, or a response to a request the server never sent: nothing to answer.
    case silent
    /// A message to answer with an error, under the id it had (or `null` when it had no usable one).
    case rejected(id: JSONValue, error: JSONRPCError)

    /// The member naming the protocol version.
    static let versionKey = "jsonrpc"
    /// The protocol version every message must name.
    static let version: JSONValue = "2.0"

    /// Sorts a parsed message into a request, something to ignore, or something to reject.
    ///
    /// - Parameter message: The parsed JSON.
    /// - Returns: What the server should do with it.
    static func classify(_ message: JSONValue) -> JSONRPCIncoming {
        guard let object = message.objectValue else {
            return .rejected(id: .null, error: .invalidRequest("expected a JSON object"))
        }
        guard let method = object["method"]?.stringValue, object[versionKey] == version else {
            return malformed(object)
        }
        guard let rawID = object["id"] else { return .silent }
        return request(id: rawID, method: method, params: object["params"])
    }

    /// Handles an object that isn't a well-formed request or notification.
    ///
    /// - Parameter object: The message's members.
    /// - Returns: `silent` for a response to ignore, or a rejection under the message's id when it has one.
    private static func malformed(_ object: [String: JSONValue]) -> JSONRPCIncoming {
        if isResponse(object) { return .silent }
        let error = JSONRPCError.invalidRequest("expected \(versionKey) 2.0 and a string method")
        return .rejected(id: usableID(object["id"]) ?? .null, error: error)
    }

    /// Builds a request from its parts, rejecting a bad id or non-object parameters.
    ///
    /// - Parameters:
    ///   - rawID: The message's `id` member.
    ///   - method: The method's name.
    ///   - params: The message's `params` member, if it had one.
    /// - Returns: The request, or a rejection.
    private static func request(id rawID: JSONValue, method: String, params: JSONValue?) -> JSONRPCIncoming {
        guard let id = usableID(rawID) else {
            return .rejected(id: .null, error: .invalidRequest("id must be a string or a number"))
        }
        guard let params else { return .request(JSONRPCRequest(id: id, method: method, params: [:])) }
        guard let members = params.objectValue else {
            return .rejected(id: id, error: .invalidParams("params must be an object"))
        }
        return .request(JSONRPCRequest(id: id, method: method, params: members))
    }

    /// Whether a message is a response (a result or an error under an id) rather than a request.
    ///
    /// - Parameter object: The message's members.
    /// - Returns: `true` for a response.
    private static func isResponse(_ object: [String: JSONValue]) -> Bool {
        object["method"] == nil && object["id"] != nil && (object["result"] != nil || object["error"] != nil)
    }

    /// The id when it's one a response can echo: a string or a number.
    ///
    /// - Parameter id: The message's `id` member, if it had one.
    /// - Returns: The id, or `nil` when it's missing or of another kind.
    private static func usableID(_ id: JSONValue?) -> JSONValue? {
        switch id {
        case .string?, .number?: return id
        default: return nil
        }
    }
}

/// Builds the response lines the server writes.
enum JSONRPCResponse {
    /// The line sent if a response can't be encoded, which only a non-finite number in a result causes.
    static let encodingFailureLine = #"{"error":{"code":-32603,"message":"Internal error: unencodable response"},"#
        + #""id":null,"jsonrpc":"2.0"}"#

    /// A successful response.
    ///
    /// - Parameters:
    ///   - result: The method's result.
    ///   - id: The request's id.
    /// - Returns: The response as one line of JSON.
    static func success(_ result: JSONValue, id: JSONValue) -> String {
        line([JSONRPCIncoming.versionKey: JSONRPCIncoming.version, "id": id, "result": result])
    }

    /// An error response.
    ///
    /// - Parameters:
    ///   - error: What went wrong.
    ///   - id: The request's id, or `null` when it couldn't be read.
    /// - Returns: The response as one line of JSON.
    static func failure(_ error: JSONRPCError, id: JSONValue) -> String {
        let body: JSONValue = ["code": .number(Double(error.code)), "message": .string(error.message)]
        return line([JSONRPCIncoming.versionKey: JSONRPCIncoming.version, "id": id, "error": body])
    }

    /// Encodes a response, falling back to a fixed internal error.
    ///
    /// - Parameter response: The response object.
    /// - Returns: The response as one line of JSON.
    private static func line(_ response: JSONValue) -> String {
        (try? response.compactJSON()) ?? encodingFailureLine
    }
}

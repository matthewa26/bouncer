/// When a long-lived agent session, such as `bouncer mcp`, notices files that changed on disk.
public enum AgentRefresh: String, Codable, Sendable, CaseIterable {
    /// Before answering any call, re-analyze the files that changed since the last answer.
    case immediate
    /// Keep the result as it was until the next scan, or until the agent verifies the files it edited.
    case nextScan = "next-scan"
}

/// What an agent session recommends fixing first.
public enum AgentWorkOrder: String, Codable, Sendable, CaseIterable {
    /// Every mechanical fix before any refactor; within each, errors before warnings before info.
    case quickFixesFirst = "quick-fixes-first"
    /// Errors before warnings before info, whatever the effort; within each, mechanical before refactor.
    case severityFirst = "severity-first"
}

/// The `agent` section of `.bouncer`: how Bouncer behaves when a coding agent drives it.
public struct AgentConfig: Codable, Sendable, Equatable {
    /// When edited files are picked up; `nil` means `next-scan`.
    public var refresh: AgentRefresh?
    /// What to fix first; `nil` means `quick-fixes-first`.
    public var workOrder: AgentWorkOrder?

    /// Creates an agent config.
    ///
    /// - Parameters:
    ///   - refresh: When edited files are picked up, or `nil` for the default (`next-scan`).
    ///   - workOrder: What to fix first, or `nil` for the default (`quick-fixes-first`).
    public init(refresh: AgentRefresh? = nil, workOrder: AgentWorkOrder? = nil) {
        self.refresh = refresh
        self.workOrder = workOrder
    }

    /// Merges another config's fields over this one's, preferring the other's when both are set.
    ///
    /// - Parameter other: The config whose fields take precedence.
    /// - Returns: The merged config.
    public func merging(_ other: AgentConfig) -> AgentConfig {
        AgentConfig(refresh: other.refresh ?? refresh, workOrder: other.workOrder ?? workOrder)
    }
}

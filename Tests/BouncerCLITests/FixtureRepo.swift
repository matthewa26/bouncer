import BouncerCore
import Foundation

/// A throwaway git repository of Swift files with known findings, plus an empty home directory for the server.
struct FixtureRepo {
    /// The scratch directory holding everything; removed by `remove()`.
    let work: URL
    /// The repository root.
    let repo: URL
    /// The home directory the server and git run with, so the user's own settings stay out of the test.
    let home: URL

    /// The config every session starts with: force unwraps are errors.
    static let config = #"{ "rules": { "force-unwrap": { "severity": "error" } } }"# + "\n"

    /// A doc comment for a one-parameter function, as every fixture function carries one.
    static func docs(_ summary: String, returns: String) -> String {
        "/// \(summary)\n///\n/// - Parameter value: The value.\n/// - Returns: \(returns)\n"
    }

    /// Creates the repository, writes the starting files, and commits them.
    static func make() throws -> FixtureRepo {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("bouncer-mcp-\(UUID().uuidString)")
        let fixture = FixtureRepo(
            work: work, repo: work.appendingPathComponent("repo"), home: work.appendingPathComponent("home")
        )
        try FileManager.default.createDirectory(at: fixture.home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: fixture.repo.appendingPathComponent("Sources"), withIntermediateDirectories: true
        )
        try fixture.git(["init", "-q"])
        try fixture.git(["config", "user.email", "test@example.com"])
        try fixture.git(["config", "user.name", "Test"])
        try fixture.writeStartingFiles()
        try fixture.git(["add", "-A"])
        try fixture.git(["-c", "commit.gpgsign=false", "commit", "-qm", "initial"])
        return fixture
    }

    /// The environment for child processes: this process's, with the fixture's home directory.
    var environment: [String: String] {
        ProcessInfo.processInfo.environment.merging(["HOME": home.path, "USERPROFILE": home.path]) { $1 }
    }

    /// Overwrites a file in the repository.
    func write(_ path: String, _ contents: String) throws {
        try contents.write(to: repo.appendingPathComponent(path), atomically: false, encoding: .utf8)
    }

    /// Runs git in the repository, failing on a non-zero exit.
    func git(_ arguments: [String]) throws {
        guard let git = ExecutableLocator.path(of: "git") else { throw EndToEndFailure("git isn't on PATH") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = arguments
        process.currentDirectoryURL = repo
        process.environment = environment
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EndToEndFailure("git \(arguments.joined(separator: " ")) failed: \(message)")
        }
    }

    /// Deletes the scratch directory.
    func remove() {
        try? FileManager.default.removeItem(at: work)
    }

    private func writeStartingFiles() throws {
        try write(".bouncer", Self.config)
        try write("Sources/Unwrap.swift", Self.docs("Reads a value.", returns: "The value, unwrapped.")
            + "func read(_ value: Int?) -> Int {\n    value!\n}\n")
        try write("Sources/Numbers.swift", Self.docs("Adds numbers.", returns: "The sum.")
            + "func add(_ value: Int) -> Int {\n    let first = value + 7_919\n    let second = first * 104_729\n"
            + "    let third = second - 15_485_863\n    let fourth = third + 32_452_843\n"
            + "    return fourth + 49_979_687\n}\n")
        try write("Sources/Many.swift", ["One", "Two", "Three"].map { name in
            Self.docs("Scales.", returns: "It, scaled.") + "func scale\(name)(_ value: Int) -> Int {\n"
                + "    let first = value + 7_919\n    let second = first * 104_729\n"
                + "    let third = second - 15_485_863\n    return third + 32_452_843 * 49_979_687\n}\n"
        }.joined())
        for name in ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"] {
            try write("Sources/\(name).swift", Self.docs("Reads.", returns: "It.")
                + "func read\(name)(_ value: Int?) -> Int {\n    value!\n}\n")
        }
    }
}

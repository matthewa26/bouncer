import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class MissingLockfileRuleTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lockfile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ contents: String = "") throws {
        let url = RepoPath.url(path, in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func flagged(_ targets: Set<String>, params: [String: RuleParameterValue] = [:]) -> [String] {
        let settings = RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: params))
        let context = AnalysisContext(repoRoot: root, ruleSettings: ["missing-lockfile": settings])
        let index = ProjectIndex(facts: [], resolvers: ImportResolvers(paths: [], repoRoot: root))
        return MissingLockfileRule().evaluate(index, targets: targets, context: context)
            .map { RepoPath.relative($0.filePath, to: root) + ":\($0.line)" }
    }

    func testFlagsAnNpmPackageWithDependenciesButNoLockfile() throws {
        try write("web/package.json", #"{"dependencies": {"a": "^1.0.0"}}"#)
        try write("empty/package.json", #"{"name": "empty", "dependencies": {}}"#)
        try write("locked/package.json", #"{"devDependencies": {"a": "^1.0.0"}}"#)
        try write("locked/pnpm-lock.yaml")
        XCTAssertEqual(flagged(["web/package.json", "empty/package.json", "locked/package.json"]), ["web/package.json:1"])
    }

    func testAcceptsAWorkspaceRootLockfileAboveAPackage() throws {
        try write("package.json", #"{"workspaces": ["packages/*"], "devDependencies": {"a": "1"}}"#)
        try write("yarn.lock")
        try write("packages/ui/package.json", #"{"dependencies": {"b": "^2.0.0"}}"#)
        XCTAssertEqual(flagged(["package.json", "packages/ui/package.json"]), [])
    }

    func testFlagsBinaryCratesAndWorkspacesButNotLibraries() throws {
        try write("app/Cargo.toml", "[package]\nname = \"app\"\n")
        try write("app/src/main.rs", "fn main() {}\n")
        try write("tool/Cargo.toml", "[package]\nname = \"tool\"\n\n[[bin]]\nname = \"tool\"\n")
        try write("lib/Cargo.toml", "[package]\nname = \"lib\"\n")
        try write("lib/src/lib.rs")
        try write("ws/Cargo.toml", "[workspace]\nmembers = [\"cli\"]\n")
        try write("ws/Cargo.lock")
        try write("ws/cli/Cargo.toml", "[package]\nname = \"cli\"\n")
        try write("ws/cli/src/main.rs")
        let targets: Set = ["app/Cargo.toml", "tool/Cargo.toml", "lib/Cargo.toml", "ws/Cargo.toml", "ws/cli/Cargo.toml"]
        XCTAssertEqual(flagged(targets), ["app/Cargo.toml:1", "tool/Cargo.toml:1"])
    }

    func testFlagsAComposerPackageRequiringPackagesWithoutAComposerLock() throws {
        try write("app/composer.json", #"{"require": {"php": ">=8.2", "vendor/lib": "^1.0"}}"#)
        try write("dev/composer.json", #"{"require-dev": {"phpunit/phpunit": "^11.0"}}"#)
        try write("platform/composer.json", #"{"require": {"php": ">=8.4", "ext-json": "*"}}"#)
        try write("locked/composer.json", #"{"require": {"vendor/lib": "^1.0"}}"#)
        try write("locked/composer.lock", "{}")
        try write("broken/composer.json", "{ not json")
        try write("composer.lock", "{}")
        let targets: Set = [
            "app/composer.json", "dev/composer.json", "platform/composer.json", "locked/composer.json",
            "broken/composer.json"
        ]
        XCTAssertEqual(flagged(targets), ["app/composer.json:1", "dev/composer.json:1"])
    }

    func testChecksTheRootSwiftPackageOnlyWhenOptedIn() throws {
        try write("Package.swift", ".package(url: \"https://github.com/a/b.git\", from: \"1.0.0\")\n")
        XCTAssertEqual(flagged(["Package.swift"]), [])
        XCTAssertEqual(flagged(["Package.swift"], params: ["swiftPackages": .bool(true)]), ["Package.swift:1"])
        try write("Package.resolved", "{}")
        XCTAssertEqual(flagged(["Package.swift"], params: ["swiftPackages": .bool(true)]), [])
    }

    func testIgnoresManifestsThatAreNotBeingChecked() throws {
        try write("web/package.json", #"{"dependencies": {"a": "^1.0.0"}}"#)
        XCTAssertEqual(flagged([]), [])
    }
}

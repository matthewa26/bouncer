import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class ProjectRulesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("project-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func facts(_ path: String, _ imports: [String]) -> FileFacts {
        FileFacts(path: path, contentHash: "h", module: ModuleFacts(imports: imports.enumerated().map {
            ImportFact(specifier: $0.element, line: $0.offset + 1)
        }))
    }

    private func cycles(_ files: [FileFacts], targets: Set<String> = []) -> [Finding] {
        let context = AnalysisContext(repoRoot: root, ruleSettings: [:])
        return ProjectRules().findings(for: files, targets: targets, context: context).filter { $0.ruleID == "import-cycle" }
    }

    private func resolve(_ specifier: String, from path: String, paths: Set<String>) -> String? {
        ImportResolvers(paths: paths, repoRoot: root).resolver(for: path)?.resolve(specifier, from: path)
    }

    func testReportsEachCycleOnceWithItsPath() {
        let files = [facts("a.ts", ["./b"]), facts("b.ts", ["./c"]), facts("c.ts", ["./a"]), facts("d.ts", ["./a"])]
        let found = cycles(files)
        XCTAssertEqual(found.map(\.message), ["Import cycle: a.ts → b.ts → c.ts → a.ts."])
        XCTAssertEqual(found.first.map { RepoPath.relative($0.filePath, to: root) }, "a.ts")
    }

    func testReportsACycleInATargetFileWhenOneIsInvolved() {
        let files = [facts("a.ts", ["./b"]), facts("b.ts", ["./a"])]
        let found = cycles(files, targets: ["b.ts"])
        XCTAssertEqual(found.first.map { RepoPath.relative($0.filePath, to: root) }, "b.ts")
        XCTAssertEqual(found.first?.message, "Import cycle: b.ts → a.ts → b.ts.")
    }

    func testIgnoresAcyclicGraphsAndExternalImports() {
        XCTAssertTrue(cycles([facts("a.ts", ["./b", "react"]), facts("b.ts", ["lodash"])]).isEmpty)
    }

    func testFindsCyclesBetweenSwiftTargets() {
        let files = [facts("Sources/A/a.swift", ["B", "Foundation"]), facts("Sources/B/b.swift", ["A"])]
        XCTAssertEqual(cycles(files).map(\.message), ["Import cycle: A → B → A."])
    }

    func testResolvesTypeScriptRelativeIndexAndJsSpecifiers() {
        let paths: Set<String> = ["src/a.ts", "src/lib/index.ts", "src/c.tsx", "src/d.ts"]
        XCTAssertEqual(resolve("./lib", from: "src/a.ts", paths: paths), "src/lib/index.ts")
        XCTAssertEqual(resolve("./c", from: "src/a.ts", paths: paths), "src/c.tsx")
        XCTAssertEqual(resolve("./d.js", from: "src/a.ts", paths: paths), "src/d.ts")
        XCTAssertEqual(resolve("../d", from: "src/lib/index.ts", paths: paths), "src/d.ts")
        XCTAssertNil(resolve("react", from: "src/a.ts", paths: paths))
    }

    func testResolvesTsconfigPathAliasesAndBaseUrl() throws {
        let config = "{\n  // aliases\n  \"compilerOptions\": { \"baseUrl\": \".\", \"paths\": { \"@lib/*\": [\"src/lib/*\"] }, },\n}\n"
        try config.write(to: root.appendingPathComponent("tsconfig.json"), atomically: true, encoding: .utf8)
        let paths: Set<String> = ["src/app.ts", "src/lib/util.ts"]
        XCTAssertEqual(resolve("@lib/util", from: "src/app.ts", paths: paths), "src/lib/util.ts")
        XCTAssertEqual(resolve("src/lib/util", from: "src/app.ts", paths: paths), "src/lib/util.ts")
    }

    func testResolvesPythonAbsoluteRelativeAndSrcLayouts() {
        let paths: Set<String> = ["pkg/__init__.py", "pkg/a.py", "pkg/sub/b.py", "src/lib/c.py"]
        XCTAssertEqual(resolve("pkg.a", from: "pkg/sub/b.py", paths: paths), "pkg/a.py")
        XCTAssertEqual(resolve("..a", from: "pkg/sub/b.py", paths: paths), "pkg/a.py")
        XCTAssertEqual(resolve("pkg", from: "pkg/a.py", paths: paths), "pkg/__init__.py")
        XCTAssertEqual(resolve("lib.c", from: "pkg/a.py", paths: paths), "src/lib/c.py")
        XCTAssertNil(resolve("os.path", from: "pkg/a.py", paths: paths))
    }

    func testResolvesGoImportsUnderTheModulePath() throws {
        try "module example.com/app\n\ngo 1.22\n".write(to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        let paths: Set<String> = ["main.go", "internal/db/db.go"]
        XCTAssertEqual(resolve("example.com/app/internal/db", from: "main.go", paths: paths), "go:internal/db")
        XCTAssertNil(resolve("fmt", from: "main.go", paths: paths))
    }

    func testFactsStoreRoundTripsAndInvalidatesOnContentChange() throws {
        let store = JSONFactsStore(repoRoot: root)
        try store.save([facts("a.ts", ["./b"])])
        let reopened = JSONFactsStore(repoRoot: root)
        XCTAssertEqual(reopened.cachedFacts(path: "a.ts", contentHash: "h")?.module.imports.first?.specifier, "./b")
        XCTAssertNil(reopened.cachedFacts(path: "a.ts", contentHash: "changed"))
    }

    func testFactsStoreKeepsOtherExistingFilesAndDropsDeletedOnes() throws {
        try "x".write(to: root.appendingPathComponent("kept.ts"), atomically: true, encoding: .utf8)
        try JSONFactsStore(repoRoot: root).save([facts("kept.ts", []), facts("deleted.ts", [])])
        try JSONFactsStore(repoRoot: root).save([facts("new.ts", [])])
        let store = JSONFactsStore(repoRoot: root)
        XCTAssertNotNil(store.cachedFacts(path: "kept.ts", contentHash: "h"))
        XCTAssertNotNil(store.cachedFacts(path: "new.ts", contentHash: "h"))
        XCTAssertNil(store.cachedFacts(path: "deleted.ts", contentHash: "h"))
    }

    func testFactsStoreIgnoresACacheFromAnotherVersion() throws {
        let cache = root.appendingPathComponent(".bouncer-cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try #"{"version": 999, "files": []}"#.write(to: cache.appendingPathComponent("facts.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(JSONFactsStore(repoRoot: root).cachedFacts(path: "a.ts", contentHash: "h"))
    }
}

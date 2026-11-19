import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class MonorepoResolutionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("monorepo-\(UUID().uuidString)")
        try write("tsconfig.base.json", """
            { "compilerOptions": { "baseUrl": ".", "paths": { "@shared/*": ["packages/shared/src/*"] } } }
            """)
        try write("packages/app/tsconfig.json", """
            {
              // the app's own alias, on top of the shared base
              "extends": "../../tsconfig.base.json",
              "compilerOptions": { "baseUrl": ".", "paths": { "~/*": ["./src/*"], "@shared/*": ["../shared/src/*"] }, },
            }
            """)
        try write("packages/ui/package.json", """
            { "name": "@acme/ui", "main": "dist/index.js",
              "exports": { ".": { "import": "./dist/index.js" }, "./button": "./src/button.tsx" } }
            """)
        try write("packages/legacy/tsconfig.json", #"{ "extends": "../../tsconfig.base.json" }"#)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ text: String) throws {
        let url = RepoPath.url(path, in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private let paths: Set<String> = [
        "packages/app/src/main.ts", "packages/app/src/util.ts", "packages/ui/src/index.ts",
        "packages/ui/src/button.tsx", "packages/shared/src/math.ts", "packages/legacy/src/old.ts"
    ]

    private func resolve(_ specifier: String, from path: String) -> String? {
        ImportResolvers(paths: paths, repoRoot: root).resolver(for: path)?.resolve(specifier, from: path)
    }

    func testUsesTheNearestTsconfigsOwnAliases() {
        XCTAssertEqual(resolve("~/util", from: "packages/app/src/main.ts"), "packages/app/src/util.ts")
        XCTAssertEqual(resolve("@shared/math", from: "packages/app/src/main.ts"), "packages/shared/src/math.ts")
    }

    func testInheritsAliasesThroughExtends() {
        XCTAssertEqual(resolve("@shared/math", from: "packages/legacy/src/old.ts"), "packages/shared/src/math.ts")
        XCTAssertNil(resolve("~/util", from: "packages/legacy/src/old.ts"))
    }

    func testResolvesWorkspacePackagesToTheirSourceEntryAndSubpaths() {
        XCTAssertEqual(resolve("@acme/ui", from: "packages/app/src/main.ts"), "packages/ui/src/index.ts")
        XCTAssertEqual(resolve("@acme/ui/button", from: "packages/app/src/main.ts"), "packages/ui/src/button.tsx")
        XCTAssertNil(resolve("@acme/other", from: "packages/app/src/main.ts"))
        XCTAssertNil(resolve("react", from: "packages/app/src/main.ts"))
    }

    func testFindsCyclesAcrossWorkspacePackages() {
        let facts = [
            FileFacts(path: "packages/app/src/main.ts", contentHash: "h", module: ModuleFacts(imports: [ImportFact(specifier: "@acme/ui", line: 1)])),
            FileFacts(path: "packages/ui/src/index.ts", contentHash: "h", module: ModuleFacts(imports: [ImportFact(specifier: "../../app/src/main", line: 2)]))
        ]
        let context = AnalysisContext(repoRoot: root, ruleSettings: [:])
        let found = ProjectRules().findings(for: facts, targets: [], context: context).filter { $0.ruleID == "import-cycle" }
        XCTAssertEqual(found.map(\.message), ["Import cycle: packages/app/src/main.ts → packages/ui/src/index.ts → packages/app/src/main.ts."])
    }
}

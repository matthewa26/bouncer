import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class DependencyRulesTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/nonexistent-repo")

    private func facts(_ path: String, _ imports: [(String, [String])] = [], exports: [String] = []) -> FileFacts {
        let importFacts = imports.enumerated().map { ImportFact(specifier: $0.element.0, line: $0.offset + 1, names: $0.element.1) }
        let exportFacts = exports.enumerated().map { ExportFact(name: $0.element, line: $0.offset + 1) }
        return FileFacts(path: path, contentHash: "h", module: ModuleFacts(imports: importFacts, exports: exportFacts))
    }

    private func findings(
        _ ruleID: String, _ files: [FileFacts], params: [String: RuleParameterValue] = [:], configured: Bool = false
    ) -> [Finding] {
        let settings = configured || !params.isEmpty
            ? [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: params))] : [:]
        let context = AnalysisContext(repoRoot: root, ruleSettings: settings)
        return ProjectRules().findings(for: files, targets: [], context: context).filter { $0.ruleID == ruleID }
    }

    private func paths(_ found: [Finding]) -> [String] {
        found.map { "\(RepoPath.relative($0.filePath, to: root)):\($0.line)" }
    }

    func testFlagsImportsFromALowerLayerIntoAHigherOne() {
        let files = [
            facts("src/ui/view.ts", [("../core/model", ["Model"])]),
            facts("src/core/model.ts", [("../ui/view", ["View"])], exports: ["Model"])
        ]
        let found = findings("layer-violation", files, params: ["layers": .stringList(["src/ui/**", "src/core/**"])])
        XCTAssertEqual(paths(found), ["src/core/model.ts:1"])
    }

    func testLayerViolationDoesNothingWithoutLayers() {
        XCTAssertTrue(findings("layer-violation", [facts("a.ts", [("./b", [])]), facts("b.ts")]).isEmpty)
    }

    func testFlagsNamedExportsNothingImports() {
        let files = [
            facts("src/util.ts", exports: ["used", "unused", "default"]),
            facts("src/app.ts", [("./util", ["used"])]),
            facts("index.ts", exports: ["entry"]),
            facts("src/types.d.ts", exports: ["Shape"])
        ]
        XCTAssertEqual(findings("unused-export", files).map(\.message), [
            "Export \"unused\" isn't imported anywhere in the project."
        ])
    }

    func testNamespaceImportsAndConfiguredEntryPointsCountAsUsed() {
        let files = [
            facts("src/a.ts", exports: ["x"]), facts("src/b.ts", [("./a", ["*"])]),
            facts("pages/home.tsx", exports: ["getStaticProps"])
        ]
        XCTAssertTrue(findings("unused-export", files, params: ["entryPoints": .stringList(["pages/**"])]).isEmpty)
    }

    func testFlagsHighFanOutAndHubs() {
        let leaves = (0..<3).map { facts("leaf\($0).ts") }
        let hub = facts("hub.ts")
        let fan = facts("fan.ts", (0..<3).map { ("./leaf\($0)", ["*"]) })
        let users = (0..<3).map { facts("user\($0).ts", [("./hub", ["*"])]) }
        let files = leaves + [hub, fan] + users
        XCTAssertEqual(paths(findings("high-fan-out", files, params: ["maxDependencies": .int(2)])), ["fan.ts:1"])
        XCTAssertEqual(paths(findings("hub-module", files, params: ["maxDependents": .int(2)])), ["hub.ts:1"])
    }

    func testFlagsAStableModuleDependingOnAnUnstableOne() {
        let files = [
            facts("stable.ts", [("./volatile", ["*"])]),
            facts("a.ts", [("./stable", ["*"])]), facts("b.ts", [("./stable", ["*"])]), facts("c.ts", [("./stable", ["*"])]),
            facts("volatile.ts", [("./x", ["*"]), ("./y", ["*"])]), facts("x.ts"), facts("y.ts")
        ]
        let found = findings("unstable-dependency", files)
        XCTAssertEqual(paths(found), ["stable.ts:1"])
        XCTAssertEqual(found.first?.message, "stable.ts (instability 0.25) depends on volatile.ts (instability 0.67); depend on something at least as stable.")
    }

    func testMissingTestFileOnlyRunsWhenConfigured() {
        let files = [facts("src/cart.ts"), facts("src/cart.test.ts"), facts("src/price.ts"), facts("src/index.ts")]
        XCTAssertTrue(findings("missing-test-file", files).isEmpty)
        XCTAssertEqual(paths(findings("missing-test-file", files, configured: true)), ["src/price.ts:1"])
    }

    func testTestNameConventionsPerLanguage() {
        XCTAssertEqual(TestNames.candidates(for: "pkg/util.py"), ["test_util.py", "util_test.py"])
        XCTAssertEqual(TestNames.candidates(for: "db/store.go"), ["store_test.go"])
        XCTAssertEqual(TestNames.candidates(for: "Sources/App/Cart.swift"), ["CartTests.swift", "CartTest.swift"])
        XCTAssertTrue(TestNames.candidates(for: "Tests/AppTests/CartTests.swift").isEmpty)
    }
}

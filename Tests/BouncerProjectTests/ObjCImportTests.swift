import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class ObjCImportTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func facts(_ path: String, _ imports: [String]) -> FileFacts {
        FileFacts(path: path, contentHash: "h", module: ModuleFacts(imports: imports.enumerated().map {
            ImportFact(specifier: $0.element, line: $0.offset + 1)
        }))
    }

    private func resolve(_ specifier: String, from path: String, paths: Set<String>) -> String? {
        ImportResolvers(paths: paths, repoRoot: root).resolver(for: path)?.resolve(specifier, from: path)
    }

    private func findings(_ files: [FileFacts], rule: String, settings: [String: RuleSettings] = [:]) -> [Finding] {
        let context = AnalysisContext(repoRoot: root, ruleSettings: settings)
        return ProjectRules().findings(for: files, targets: [], context: context).filter { $0.ruleID == rule }
    }

    func testResolvesQuotedHeadersBesideTheFileThenByUniqueName() {
        let paths: Set<String> = ["App/A.m", "App/A.h", "App/Sub/B.h", "Lib/C.h", "Lib/Dup.h", "Other/Dup.h"]
        XCTAssertEqual(resolve("A.h", from: "App/A.m", paths: paths), "App/A")
        XCTAssertEqual(resolve("Sub/B.h", from: "App/A.m", paths: paths), "App/Sub/B")
        XCTAssertEqual(resolve("C.h", from: "App/A.m", paths: paths), "Lib/C")
        XCTAssertNil(resolve("Dup.h", from: "App/A.m", paths: paths))
        XCTAssertNil(resolve("Missing.h", from: "App/A.m", paths: paths))
    }

    func testResolvesFrameworkHeadersAndModulesOnlyWhenTheProjectHoldsThem() {
        let paths: Set<String> = ["App/A.m", "Kit/Kit.h", "Kit/Button.h"]
        XCTAssertEqual(resolve("<Kit/Button.h>", from: "App/A.m", paths: paths), "Kit/Button")
        XCTAssertEqual(resolve("@import Kit", from: "App/A.m", paths: paths), "Kit/Kit")
        XCTAssertEqual(resolve("@import Kit.Buttons", from: "App/A.m", paths: paths), "Kit/Kit")
        XCTAssertNil(resolve("<UIKit/UIKit.h>", from: "App/A.m", paths: paths))
        XCTAssertNil(resolve("@import Foundation", from: "App/A.m", paths: paths))
        XCTAssertNil(resolve("<stdio.h>", from: "App/A.m", paths: paths))
    }

    func testLinksObjectiveCAndSwiftThroughTheGeneratedAndBridgingHeaders() {
        let files = [
            facts("App/Legacy.m", ["Legacy.h", "App-Swift.h"]), facts("App/Legacy.h", []),
            facts("App/App-Bridging-Header.h", ["Legacy.h"]), facts("App/Model.swift", [])
        ]
        let index = ProjectIndex(facts: files, resolvers: ImportResolvers(paths: Set(files.map(\.path)), repoRoot: root))
        XCTAssertEqual(index.nodeOfFile["App/App-Bridging-Header.h"], "swift:App")
        XCTAssertEqual(index.nodeOfFile["App/Model.swift"], "swift:App")
        XCTAssertEqual(index.edges.map { "\($0.from) -> \($0.to)" }.sorted(),
                       ["App/Legacy -> swift:App", "swift:App -> App/Legacy"])
    }

    func testReportsACycleBetweenTwoHeaderAndImplementationPairs() {
        let files = [
            facts("Src/A.h", []), facts("Src/A.m", ["A.h", "B.h"]),
            facts("Src/B.h", []), facts("Src/B.m", ["B.h", "A.h"]), facts("Src/C.m", ["A.h"])
        ]
        XCTAssertEqual(findings(files, rule: "import-cycle").map(\.message), ["Import cycle: Src/A → Src/B → Src/A."])
    }

    func testCountsFanOutOverResolvedImports() {
        let files = [facts("A.m", ["B.h", "C.h", "D.h", "<UIKit/UIKit.h>"]), facts("B.h", []), facts("C.h", []),
                     facts("D.h", [])]
        let limit = ["high-fan-out": RuleSettings(enabled: true, severity: .warning,
                                                  parameters: RuleParameters(values: ["maxDependencies": .int(2)]))]
        XCTAssertEqual(findings(files, rule: "high-fan-out", settings: limit).map(\.message),
                       ["A depends on 3 project modules, over the 2 limit."])
    }
}

import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class RustImportTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/repo")

    override func tearDownWithError() throws {
        if root.path != "/repo" { try FileManager.default.removeItem(at: root) }
    }

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

    /// Writes manifests into a fresh temporary repository.
    private func makeRepo(_ manifests: [String: String]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rust-\(UUID().uuidString)")
        for (path, text) in manifests {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private let crate: Set<String> = [
        "src/lib.rs", "src/walk.rs", "src/walk/entry.rs", "src/error/mod.rs", "src/error/kind.rs", "src/main.rs",
        "src/bin/tool.rs", "tests/it.rs", "tests/common/mod.rs"
    ]

    private func declared(_ name: String, in path: String, paths: Set<String>) -> String? {
        RustImportResolver(paths: paths, repoRoot: root).declaredFile(Substring(name), in: path)
    }

    func testFindsModFilesBesideRootsAndModRsAndUnderNonRootFiles() {
        XCTAssertEqual(declared("walk", in: "src/lib.rs", paths: crate), "src/walk.rs")
        XCTAssertEqual(declared("error", in: "src/lib.rs", paths: crate), "src/error/mod.rs")
        XCTAssertEqual(declared("entry", in: "src/walk.rs", paths: crate), "src/walk/entry.rs")
        XCTAssertEqual(declared("kind", in: "src/error/mod.rs", paths: crate), "src/error/kind.rs")
        XCTAssertEqual(declared("common", in: "tests/it.rs", paths: crate), "tests/common/mod.rs")
        XCTAssertNil(declared("missing", in: "src/lib.rs", paths: crate))
        let unitTests: Set<String> = ["src/lib.rs", "src/tests/mod.rs", "src/tests/util.rs", "src/tests/walk.rs"]
        XCTAssertEqual(declared("util", in: "src/tests/mod.rs", paths: unitTests), "src/tests/util.rs")
        XCTAssertEqual(resolve("crate::tests::util::Dir", from: "src/tests/walk.rs", paths: unitTests),
                       "src/tests/util.rs")
    }

    func testOnlyACrateRootsModDeclarationsAreEdges() {
        XCTAssertEqual(resolve("mod walk", from: "src/lib.rs", paths: crate), "src/walk.rs")
        XCTAssertEqual(resolve("mod common", from: "tests/it.rs", paths: crate), "tests/common/mod.rs")
        XCTAssertNil(resolve("mod entry", from: "src/walk.rs", paths: crate))
        XCTAssertNil(resolve("mod kind", from: "src/error/mod.rs", paths: crate))
    }

    func testResolvesUsePathsToTheDeepestModuleFile() {
        XCTAssertEqual(resolve("crate::walk::entry::Entry", from: "src/error/kind.rs", paths: crate), "src/walk/entry.rs")
        XCTAssertEqual(resolve("crate::walk::WalkDir", from: "src/error/kind.rs", paths: crate), "src/walk.rs")
        XCTAssertEqual(resolve("crate::error::kind", from: "src/walk.rs", paths: crate), "src/error/kind.rs")
        XCTAssertEqual(resolve("super::kind::Kind", from: "src/walk/entry.rs", paths: crate), nil)
        XCTAssertEqual(resolve("super::super::error::Error", from: "src/walk/entry.rs", paths: crate),
                       "src/error/mod.rs")
        XCTAssertEqual(resolve("self::entry::Entry", from: "src/walk.rs", paths: crate), "src/walk/entry.rs")
        XCTAssertEqual(resolve("entry::Entry", from: "src/walk.rs", paths: crate), "src/walk/entry.rs")
        XCTAssertNil(resolve("std::fs::File", from: "src/walk.rs", paths: crate))
        XCTAssertNil(resolve("serde::Serialize", from: "src/walk.rs", paths: crate))
    }

    func testSkipsUsesOfTheImportersOwnAncestors() {
        XCTAssertNil(resolve("crate::Result", from: "src/walk.rs", paths: crate))
        XCTAssertNil(resolve("super::Walker", from: "src/walk/entry.rs", paths: crate))
        XCTAssertNil(resolve("crate::walk::Walker", from: "src/walk/entry.rs", paths: crate))
        XCTAssertNil(resolve("self::tests::super::helper", from: "src/walk.rs", paths: crate))
    }

    func testReportsACycleBetweenSiblingModules() {
        let files = [
            facts("src/lib.rs", ["mod a", "mod b"]), facts("src/a.rs", ["crate::b::Bee", "crate::Shared"]),
            facts("src/b.rs", ["crate::a::Ay"])
        ]
        XCTAssertEqual(findings(files, rule: "import-cycle").map(\.message), ["Import cycle: src/a.rs → src/b.rs → src/a.rs."])
    }

    func testCountsFanOutOverModAndUseEdges() {
        let files = [facts("src/lib.rs", ["mod a", "mod b", "crate::c::Sea", "std::fs"]), facts("src/a.rs", []),
                     facts("src/b.rs", []), facts("src/c.rs", [])]
        let limit = ["high-fan-out": RuleSettings(enabled: true, severity: .warning,
                                                  parameters: RuleParameters(values: ["maxDependencies": .int(2)]))]
        XCTAssertEqual(findings(files, rule: "high-fan-out", settings: limit).map(\.message),
                       ["src/lib.rs depends on 3 project modules, over the 2 limit."])
    }

    func testResolvesOtherWorkspaceMembersByCrateName() throws {
        try makeRepo([
            "Cargo.toml": """
                [workspace]
                # Every crate under crates/, and the app.
                members = [
                    "crates/*",  # libraries
                    "app",
                ]
                """,
            "crates/walk-core/Cargo.toml": "[package]\nname = \"walk-core\"\nversion = \"0.1.0\"\n",
            "crates/extra/Cargo.toml": "[package]\nname = \"extra\"\n\n[lib]\nname = 'extra_lib'\n",
            "app/Cargo.toml": "[package]\nname = \"app\"\n",
            "vendor/other/Cargo.toml": "[package]\nname = \"other\"\n"
        ])
        let paths: Set<String> = [
            "crates/walk-core/src/lib.rs", "crates/walk-core/src/dent.rs", "crates/extra/src/lib.rs",
            "app/src/main.rs", "vendor/other/src/lib.rs"
        ]
        XCTAssertEqual(resolve("walk_core::dent::DirEntry", from: "app/src/main.rs", paths: paths),
                       "crates/walk-core/src/dent.rs")
        XCTAssertEqual(resolve("walk_core::WalkDir", from: "app/src/main.rs", paths: paths),
                       "crates/walk-core/src/lib.rs")
        XCTAssertEqual(resolve("extra_lib::Thing", from: "app/src/main.rs", paths: paths), "crates/extra/src/lib.rs")
        XCTAssertNil(resolve("other::Thing", from: "app/src/main.rs", paths: paths))
    }

    func testReadsCargoManifestSectionsArraysAndComments() {
        let manifest = CargoManifest(text: """
            [package]
            name = "demo" # the crate
            description = "has a # inside"

            [workspace]
            members = ["a", 'b']
            exclude = [
              "c",
            ]
            """)
        XCTAssertEqual(manifest.values("name", in: "package"), ["demo"])
        XCTAssertEqual(manifest.values("description", in: "package"), ["has a # inside"])
        XCTAssertEqual(manifest.values("members", in: "workspace"), ["a", "b"])
        XCTAssertEqual(manifest.values("exclude", in: "workspace"), ["c"])
        XCTAssertEqual(manifest.values("name", in: "lib"), [])
    }
}

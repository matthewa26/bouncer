import XCTest
import Foundation
import BouncerCore
@testable import BouncerProject

final class PHPImportTests: XCTestCase {
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

    /// Writes files into a fresh temporary repository.
    private func makeRepo(_ files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("php-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static let composer = #"""
        {
          "name": "acme/app",
          "require": { "php": ">=8.2", "vendor/lib": "^1.0" },
          "autoload": {
            "psr-4": { "App\\": "src/", "App\\Legacy\\": ["lib/legacy/", "./old"] },
            "files": ["src/helpers.php"]
          },
          "autoload-dev": { "psr-4": { "App\\Tests\\": "tests/" } }
        }
        """#

    private let project: Set<String> = [
        "src/Models/User.php", "src/Models/Post.php", "src/Http/Controller.php", "src/Support.php",
        "src/helpers.php", "lib/legacy/Report.php", "old/Mailer.php", "tests/Models/UserTest.php",
        "public/index.php", "bootstrap/app.php", "config/db.php"
    ]

    func testResolvesUseNamesThroughPSR4ByLongestPrefix() throws {
        try makeRepo(["composer.json": Self.composer])
        let from = "src/Http/Controller.php"
        XCTAssertEqual(resolve("App\\Models\\User", from: from, paths: project), "src/Models/User.php")
        XCTAssertEqual(resolve("App\\Legacy\\Report", from: from, paths: project), "lib/legacy/Report.php")
        XCTAssertEqual(resolve("App\\Legacy\\Mailer", from: from, paths: project), "old/Mailer.php")
        XCTAssertEqual(resolve("App\\Tests\\Models\\UserTest", from: from, paths: project),
                       "tests/Models/UserTest.php")
        XCTAssertNil(resolve("App\\Models\\Missing", from: from, paths: project))
        XCTAssertNil(resolve("Vendor\\Lib\\Client", from: from, paths: project))
        XCTAssertNil(resolve("Symfony\\Component\\Console\\Command", from: "templates/page.phtml", paths: project))
    }

    func testResolvesFunctionAndConstUsesOnlyToAnExistingNamespaceFile() throws {
        try makeRepo(["composer.json": Self.composer])
        let from = "src/Http/Controller.php"
        XCTAssertEqual(resolve("function App\\Support\\helper", from: from, paths: project), "src/Support.php")
        XCTAssertEqual(resolve("const App\\Support\\LIMIT", from: from, paths: project), "src/Support.php")
        XCTAssertNil(resolve("function App\\Helpers\\format", from: from, paths: project))
        XCTAssertNil(resolve("function strlen", from: from, paths: project))
    }

    func testResolvesLiteralRequiresRelativeToTheFileThenTheRoot() throws {
        try makeRepo(["composer.json": Self.composer])
        XCTAssertEqual(resolve("require __DIR__/../bootstrap/app.php", from: "public/index.php", paths: project),
                       "bootstrap/app.php")
        XCTAssertEqual(resolve("require ../config/db.php", from: "bootstrap/app.php", paths: project), "config/db.php")
        XCTAssertEqual(resolve("require config/db.php", from: "public/index.php", paths: project), "config/db.php")
        XCTAssertNil(resolve("require __DIR__/missing.php", from: "public/index.php", paths: project))
        XCTAssertNil(resolve("require /etc/config.php", from: "public/index.php", paths: project))
    }

    func testAMissingOrMalformedComposerManifestAddsNoUseEdges() throws {
        try makeRepo(["composer.json": "{ \"autoload\": { \"psr-4\": "])
        XCTAssertNil(resolve("App\\Models\\User", from: "src/Http/Controller.php", paths: project))
        XCTAssertEqual(resolve("require __DIR__/Post.php", from: "src/Models/User.php", paths: project),
                       "src/Models/Post.php")
        try makeRepo([:])
        XCTAssertNil(resolve("App\\Models\\User", from: "src/Http/Controller.php", paths: project))
    }

    func testReportsAnImportCycleThroughUseEdges() throws {
        try makeRepo(["composer.json": Self.composer])
        let files = [
            facts("src/Models/User.php", ["App\\Models\\Post", "Vendor\\Lib\\Client"]),
            facts("src/Models/Post.php", ["App\\Models\\User"]), facts("src/Http/Controller.php", ["App\\Models\\User"])
        ]
        XCTAssertEqual(findings(files, rule: "import-cycle").map(\.message),
                       ["Import cycle: src/Models/Post.php → src/Models/User.php → src/Models/Post.php."])
    }

    func testCountsFanOutOverUseAndRequireEdges() throws {
        try makeRepo(["composer.json": Self.composer])
        let files = [
            facts("src/Http/Controller.php", [
                "App\\Models\\User", "App\\Models\\Post", "require __DIR__/../../config/db.php", "Vendor\\Lib\\Client"
            ]),
            facts("src/Models/User.php", []), facts("src/Models/Post.php", []), facts("config/db.php", [])
        ]
        let limit = ["high-fan-out": RuleSettings(enabled: true, severity: .warning,
                                                  parameters: RuleParameters(values: ["maxDependencies": .int(2)]))]
        XCTAssertEqual(findings(files, rule: "high-fan-out", settings: limit).map(\.message),
                       ["src/Http/Controller.php depends on 3 project modules, over the 2 limit."])
    }

    func testReadsComposerPrefixesAndPackageRequirements() throws {
        let manifest = try XCTUnwrap(ComposerManifest(text: Self.composer))
        XCTAssertEqual(manifest.prefixes.map(\.namespace), ["App\\Legacy\\", "App\\Tests\\", "App\\"])
        XCTAssertEqual(manifest.prefixes.first?.directories, ["lib/legacy", "old"])
        XCTAssertEqual(manifest.dependencies, ["vendor/lib"])
        XCTAssertNil(ComposerManifest(text: "[]"))
        XCTAssertEqual(ComposerManifest(text: "{}")?.prefixes, [])
    }
}

import XCTest
import Foundation
import BouncerCore
import BouncerGit
@testable import BouncerProject

/// Builds structure facts tersely for the design rule tests.
private enum Make {
    static func type(
        _ name: String, _ kind: TypeKind = .class, line: Int = 1, supers: [String] = [], fields: [String] = [],
        methods: [String] = [], refused: [String] = [], empty: [String] = []
    ) -> TypeFact {
        TypeFact(name: name, line: line, kind: kind, members: TypeMembers(
            supertypes: supers, fields: fields, methods: methods, refused: refused, empty: empty
        ))
    }

    static func file(
        _ path: String, types: [TypeFact] = [], functions: [FunctionFact] = [], switches: [SwitchFact] = [],
        imports: [String] = [], exports: [ExportFact] = [], references: [String] = []
    ) -> FileFacts {
        let module = ModuleFacts(
            imports: imports.map { ImportFact(specifier: $0, line: 1) }, exports: exports, references: references,
            structure: StructureFacts(types: types, functions: functions, switches: switches)
        )
        return FileFacts(path: path, contentHash: "h", module: module)
    }
}

final class DesignRulesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("design-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ path: String, _ contents: String) throws {
        let url = RepoPath.url(path, in: root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func findings(
        _ ruleID: String, _ files: [FileFacts], params: [String: RuleParameterValue] = [:], configured: Bool = false
    ) -> [Finding] {
        let settings = configured || !params.isEmpty
            ? [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: params))] : [:]
        let context = AnalysisContext(repoRoot: root, ruleSettings: settings)
        return ProjectRules().findings(for: files, targets: [], context: context).filter { $0.ruleID == ruleID }
    }

    private func places(_ found: [Finding]) -> [String] {
        found.map { "\(RepoPath.relative($0.filePath, to: root)):\($0.line)" }
    }

    // MARK: deep-inheritance and many-subclasses

    func testFlagsClassesDeeperThanTheLimitCountingOnlyProjectAncestors() {
        let chain = ["A", "B", "C", "D", "E", "F"]
        let types = chain.enumerated().map { offset, name in
            Make.type(name, line: offset + 1, supers: offset == 0 ? ["NSObject"] : [chain[offset - 1], "Codable"])
        }
        let found = findings("deep-inheritance", [Make.file("Sources/M/a.swift", types: types)])
        XCTAssertEqual(places(found), ["Sources/M/a.swift:6"])
        XCTAssertEqual(found.first?.message, "Class \"F\" is 5 levels deep in the project's inheritance tree "
            + "(F → E → D → C → B → A), over the 4 limit; prefer composition over more subclassing.")
        XCTAssertTrue(findings("deep-inheritance", [Make.file("a.swift", types: types)], params: ["maxDepth": .int(5)]).isEmpty)
    }

    func testOnlyTheFirstSwiftSupertypeCanBeASuperclassButPythonAllowsSeveral() {
        let swift = Make.file("a.swift", types: [Make.type("Base"), Make.type("P", .protocol), Make.type("X", supers: ["P", "Base"])])
        XCTAssertEqual(TypeHierarchy(index: index([swift])).types.map { TypeHierarchy(index: index([swift])).depth(of: $0) }, [0, 0, 0])
        let python = Make.file("a.py", types: [Make.type("A"), Make.type("B"), Make.type("C", supers: ["A", "B"]), Make.type("D", supers: ["C"])])
        let hierarchy = TypeHierarchy(index: index([python]))
        XCTAssertEqual(hierarchy.types.map { hierarchy.depth(of: $0) }, [0, 0, 1, 2])
        XCTAssertEqual(hierarchy.children[hierarchy.types[0].id]?.map(\.name), ["C"])
    }

    func testManySubclassesRunsOnlyWhenConfigured() {
        let types = [Make.type("Base")] + (1...3).map { Make.type("Sub\($0)", line: $0 + 1, supers: ["Base"]) }
        let files = [Make.file("src/a.ts", types: types)]
        XCTAssertTrue(findings("many-subclasses", files).isEmpty)
        let found = findings("many-subclasses", files, params: ["maxChildren": .int(2)])
        XCTAssertEqual(found.map(\.message), ["Class \"Base\" has 3 direct subclasses, over the 2 limit "
            + "(Sub1, Sub2, Sub3); a change to it ripples into all of them."])
    }

    // MARK: refused-bequest

    func testFlagsSubclassesThatOverrideOnlyToThrowOrDoNothing() {
        let base = Make.type("Store", methods: ["save", "load", "close"])
        let sub = Make.type("ReadOnlyStore", line: 5, supers: ["Store"], methods: ["save", "close", "extra"],
                            refused: ["save"], empty: ["close", "extra"])
        let found = findings("refused-bequest", [Make.file("src/store.ts", types: [base, sub])])
        XCTAssertEqual(places(found), ["src/store.ts:5"])
        XCTAssertEqual(found.first?.message, "\"ReadOnlyStore\" overrides save(), close() only to throw or do nothing; "
            + "it refuses what it inherits, so it can't stand in for its parent. Use composition or split the parent.")
    }

    func testRefusedBequestSkipsAbstractParentsTestsAndExternalNoOps() {
        let abstract = Make.type("Shape", .abstractClass, methods: ["area"], refused: ["area"])
        let concrete = Make.type("Blob", line: 4, supers: ["Shape"], methods: ["area"], refused: ["area"])
        let swiftExternal = Make.type("View", line: 9, supers: ["UIView"], methods: ["layout", "draw"], refused: ["draw"], empty: ["layout"])
        let mock = Make.type("MockStore", supers: ["Store"], methods: ["save"], refused: ["save"])
        let files = [
            Make.file("a.py", types: [abstract, concrete]), Make.file("Sources/A/View.swift", types: [swiftExternal]),
            Make.file("Tests/AT/Mocks.swift", types: [mock]), Make.file("Sources/A/Store.swift", types: [Make.type("Store", methods: ["save"])])
        ]
        let found = findings("refused-bequest", files)
        XCTAssertEqual(places(found), ["Sources/A/View.swift:9"])
        XCTAssertTrue(found.first?.message.hasPrefix("\"View\" overrides draw() only") == true)
    }

    // MARK: parallel-inheritance

    func testFlagsHierarchiesWhoseSubtypesPairUpByName() {
        let shapes = [Make.type("Shape", .protocol)] + ["Circle", "Square", "Triangle"].map { Make.type($0 + "Shape", .struct, supers: ["Shape"]) }
        let renderers = [Make.type("Renderer")] + ["Circle", "Square", "Triangle", "Star"].map { Make.type($0 + "Renderer", supers: ["Renderer"]) }
        let found = findings("parallel-inheritance", [Make.file("Sources/A/Shapes.swift", types: shapes), Make.file("Sources/A/Renderers.swift", types: renderers)])
        XCTAssertEqual(places(found), ["Sources/A/Renderers.swift:1"])
        XCTAssertEqual(found.first?.message, "\"Renderer\" and \"Shape\" (Sources/A/Shapes.swift) are parallel hierarchies: "
            + "3 of their subtypes pair up by name (Circle, Square, Triangle), so each new case needs a class in both; "
            + "merge them or move the varying part into one.")
    }

    func testTypesConformingToTwoProtocolsAreNotParallelHierarchies() {
        let types = [Make.type("Readable", .protocol), Make.type("Writable", .protocol)]
            + ["A", "B", "C"].map { Make.type($0, .struct, supers: ["Readable", "Writable"]) }
        XCTAssertTrue(findings("parallel-inheritance", [Make.file("a.swift", types: types)]).isEmpty)
    }

    func testStemsUseWholeCamelCaseWords() {
        XCTAssertEqual(WordAffix.commonSuffix(["HTTPRequestHandler", "FileHandler", "Handler"]), "Handler")
        XCTAssertEqual(WordAffix.commonPrefix(["NodeKind", "NodeValue"]), "Node")
        XCTAssertEqual(WordAffix.commonSuffix(["Circle", "Square"]), "")
    }

    // MARK: main-sequence-distance

    func testFlagsAConcreteModuleEverythingDependsOn() {
        let core = (1...3).map { Make.file("Sources/Core/T\($0).swift", types: [Make.type("T\($0)", .struct)]) }
        let users = ["App", "CLI"].map { Make.file("Sources/\($0)/main.swift", types: [Make.type($0, .protocol)], imports: ["Core"]) }
        XCTAssertTrue(findings("main-sequence-distance", core + users).isEmpty)
        let found = findings("main-sequence-distance", core + users, params: ["minTypes": .int(3)])
        XCTAssertEqual(places(found), ["Sources/Core/T1.swift:1"])
        XCTAssertEqual(found.first?.message, "Core has abstractness 0.00 and instability 0.00, a distance of 1.00 from "
            + "the main sequence (over 0.70): it's concrete and depended on, so every change ripples outward (the zone of pain).")
    }

    func testMeasuresTypeScriptFoldersByTheirImportsBetweenFolders() {
        let files = [
            Make.file("src/api/a.ts", types: [Make.type("A"), Make.type("B", .interface)], imports: ["../ui/v"]),
            Make.file("src/ui/v.ts", types: [Make.type("V")])
        ]
        let metrics = UnitGraph(index: index(files)).metrics(minTypes: 1)
        XCTAssertEqual(metrics.map(\.unit), ["dir:src/api", "dir:src/ui"])
        XCTAssertEqual(metrics.map(\.distance), [0.5, 1])
    }

    // MARK: data-clump

    func testFlagsTheSameParametersInSeveralFunctionsAcrossFiles() {
        let clump = ["start:Int", "end:Int", "file:String"]
        let files = [
            Make.file("Sources/A/a.swift", functions: [FunctionFact(name: "highlight", line: 3, parameters: clump + ["color:Color"]),
                                                     FunctionFact(name: "select", line: 9, parameters: clump)]),
            Make.file("Sources/B/b.swift", types: [Make.type("Span", .struct, line: 1, fields: clump)],
                      functions: [FunctionFact(name: "copy", line: 2, parameters: clump.reversed()),
                                  FunctionFact(name: "select", line: 7, parameters: clump)])
        ]
        XCTAssertTrue(findings("data-clump", files).isEmpty, "a type holds them and only three functions pass them")
        let more = files + [Make.file("Sources/C/c.swift", functions: [FunctionFact(name: "cut", line: 4, parameters: clump)])]
        let found = findings("data-clump", more)
        XCTAssertEqual(places(found), ["Sources/A/a.swift:3"])
        XCTAssertEqual(found.first?.message, "end: Int, file: String, start: Int appear together in 5 functions and types "
            + "across 3 files (highlight(), select(), Span, copy(), cut()); group them into one type.")
    }

    func testDataClumpsNeedMatchingTypesAndCountOverloadsOnce() {
        let files = (1...4).map { number in
            Make.file("src/f\(number).ts", functions: [FunctionFact(name: "same", line: 1, parameters: ["a:number", "b:number", "c:number"])])
        } + [Make.file("src/g.ts", functions: [FunctionFact(name: "other", line: 1, parameters: ["a:string", "b:number", "c:number"])])]
        XCTAssertTrue(findings("data-clump", files).isEmpty)
        XCTAssertEqual(ClumpFinder.combinations(["a", "b", "c", "d"], size: 3).count, 4)
    }

    // MARK: repeated-switch

    func testFlagsTheSameSubjectSwitchedWithSharedCasesAcrossFiles() {
        let files = (1...3).map { number in
            Make.file("src/f\(number).ts", switches: [SwitchFact(subject: "shape.kind", line: number, cases: ["\"circle\"", "\"square\""])])
        } + [Make.file("src/f4.ts", switches: [SwitchFact(subject: "shape.kind", line: 9, cases: ["\"x\"", "\"y\""])]),
             Make.file("src/x.test.ts", switches: [SwitchFact(subject: "shape.kind", line: 1, cases: ["\"circle\"", "\"square\""])])]
        let found = findings("repeated-switch", files)
        XCTAssertEqual(places(found), ["src/f1.ts:1"])
        XCTAssertEqual(found.first?.message, "`switch shape.kind` with the same cases appears 3 times across 3 files "
            + "(src/f1.ts:1, src/f2.ts:2, src/f3.ts:3); each new case must be added everywhere. Move the varying "
            + "behavior into the type (polymorphism) or one lookup table.")
        XCTAssertTrue(findings("repeated-switch", files, params: ["ignoreSubjects": .stringList(["shape.kind"])]).isEmpty)
    }

    func testSwitchesOnOneSubjectWithDifferentCasesAreNotRepeated() {
        let files = (1...3).map { number in
            Make.file("a\(number).swift", switches: [SwitchFact(subject: "node.kind", line: 1, cases: [".a\(number)", ".b\(number)"])])
        }
        XCTAssertTrue(findings("repeated-switch", files).isEmpty)
    }

    // MARK: single-implementation-interface

    func testFlagsAProtocolWithOneImplementationAndNoTestDouble() {
        let files = [
            Make.file("Sources/A/Store.swift", types: [Make.type("Store", .protocol, line: 2), Make.type("DiskStore", .struct, line: 5, supers: ["Store"])]),
            Make.file("Sources/A/Clock.swift", types: [Make.type("Clock", .protocol), Make.type("SystemClock", .struct, supers: ["Clock"])]),
            Make.file("Tests/AT/ClockTests.swift", types: [Make.type("FakeClock", .struct, supers: ["Clock"])]),
            Make.file("Sources/A/Shape.swift", types: [Make.type("Shape", .protocol), Make.type("Circle", .struct), Make.type("Circle", .extension, supers: ["Shape"]),
                                                       Make.type("String", .extension, supers: ["Shape"])]),
            Make.file("Sources/A/API.swift", types: [Make.type("Plugin", .protocol, line: 3), Make.type("Only", .class, supers: ["Plugin"])],
                      exports: [ExportFact(name: "Plugin", line: 3)])
        ]
        XCTAssertTrue(findings("single-implementation-interface", files).isEmpty)
        let found = findings("single-implementation-interface", files, configured: true)
        XCTAssertEqual(places(found), ["Sources/A/Store.swift:2"])
        XCTAssertEqual(found.first?.message, "Protocol \"Store\" has one implementation, \"DiskStore\" "
            + "(Sources/A/Store.swift), and no test double; use the type directly until a second implementation needs the abstraction.")
        let all = findings("single-implementation-interface", files, params: ["includePublic": .bool(true)])
        XCTAssertEqual(places(all), ["Sources/A/API.swift:3", "Sources/A/Store.swift:2"])
    }

    func testRefinedProtocolsCountTheirImplementationsAndDataShapesAreSkipped() {
        let files = [
            Make.file("src/a.ts", types: [
                Make.type("Base", .interface), Make.type("Named", .interface, supers: ["Base"]),
                Make.type("One", supers: ["Named"]), Make.type("Two", supers: ["Base"]),
                Make.type("Props", .interface, fields: ["title:string"]), Make.type("Widget", supers: ["Props"])
            ])
        ]
        let found = findings("single-implementation-interface", files, configured: true)
        XCTAssertEqual(found.map { String($0.message.prefix(18)) }, ["Interface \"Named\" "])
    }

    // MARK: inconsistent-terminology

    func testFlagsTheMinorityVerbPerModule() {
        let functions = ["fetchUser", "fetchOrder", "getInvoice", "loadCart", "loadCart", "createUser", "Shop.init", "getter"]
        let files = [
            Make.file("src/shop/api.ts", functions: functions.enumerated().map { FunctionFact(name: $0.element, line: $0.offset + 1) }),
            Make.file("src/other/x.ts", functions: [FunctionFact(name: "getX", line: 1)])
        ]
        XCTAssertTrue(findings("inconsistent-terminology", files).isEmpty)
        let found = findings("inconsistent-terminology", files, configured: true)
        XCTAssertEqual(places(found), ["src/shop/api.ts:3", "src/shop/api.ts:4"])
        XCTAssertEqual(found.first?.message, "src/shop/ names 2 functions \"fetch…\" but 1 \"get…\" (getInvoice); "
            + "pick one verb for the same action.")
        XCTAssertEqual(VerbUses.verb(of: "get_user"), "get")
        XCTAssertEqual(VerbUses.verb(of: "NewServer"), "new")
    }

    // MARK: unused-dependency

    func testFlagsSwiftPackagesAndProductsNoTargetUses() throws {
        try write("Package.swift", """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(
                name: "Demo",
                dependencies: [
                    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
                    .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
                    .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"), // .product(name: "X", package: "unused")
                    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
                    .package(url: "https://github.com/acme/unused.git", from: "1.0.0")
                ],
                targets: [
                    .executableTarget(name: "CLI", dependencies: [
                        "Core", .product(name: "ArgumentParser", package: "swift-argument-parser"), "Yams"
                    ]),
                    .target(name: "Core", dependencies: [
                        .product(name: "SwiftSyntax", package: "swift-syntax"),
                        .product(name: "SwiftParser", package: "swift-syntax")
                    ]),
                    .testTarget(name: "CoreTests", dependencies: ["Core", .product(name: "SwiftParser", package: "swift-syntax")])
                ]
            )
            """)
        let files = [
            Make.file("Package.swift", imports: ["PackageDescription"]),
            Make.file("Sources/CLI/main.swift", imports: ["ArgumentParser", "Core"]),
            Make.file("Sources/Core/a.swift", imports: ["SwiftSyntax"])
        ]
        let found = findings("unused-dependency", files)
        XCTAssertEqual(places(found), ["Package.swift:10", "Package.swift:18"])
        XCTAssertEqual(found.map(\.message), [
            "Dependency \"unused\" isn't used by any code in the package; remove it from the manifest.",
            "Target \"Core\" depends on product \"SwiftParser\", but none of its files import it; remove the dependency."
        ])
        XCTAssertTrue(findings("unused-dependency", files, params: ["ignore": .stringList(["unused", "SwiftParser"])]).isEmpty)
    }

    func testFlagsPackageJSONDependenciesNoFileImports() throws {
        try write("package.json", #"{"name": "root", "workspaces": ["packages/*"], "dependencies": {"lodash": "4", "left-pad": "1"}}"#)
        try write("packages/app/package.json", """
            {
              "name": "@acme/app",
              "scripts": { "build": "tsc -p . && next build" },
              "dependencies": {
                "react": "18", "@acme/ui": "*", "@types/node": "20", "next": "14", "typescript": "5",
                "prettier-config-acme": "1", "chalk": "5", "react-dom": "18"
              },
              "peerDependencies": { "react-dom": "18" },
              "prettier": "prettier-config-acme"
            }
            """)
        let files = [
            Make.file("packages/app/src/main.tsx", imports: ["react", "@acme/ui/button"]),
            Make.file("packages/ui/src/index.ts", imports: ["lodash/merge"])
        ]
        let found = findings("unused-dependency", files)
        XCTAssertEqual(places(found), ["package.json:1", "packages/app/package.json:6"])
        XCTAssertEqual(found.map { String($0.message.prefix(20)) }, ["Dependency \"left-pad", "Dependency \"chalk\" i"])
    }

    func testFlagsGoRequirementsNoPackageImports() throws {
        try write("go.mod", """
            module example.com/app

            go 1.22

            require github.com/spf13/cobra v1.8.0

            require (
                github.com/stretchr/testify v1.9.0
                golang.org/x/sync v0.7.0
                github.com/davecgh/go-spew v1.1.1 // indirect
            )
            """)
        let files = [
            Make.file("cmd/main.go", imports: ["github.com/spf13/cobra", "example.com/app/internal"]),
            Make.file("internal/x_test.go", imports: ["github.com/stretchr/testify/require"])
        ]
        let found = findings("unused-dependency", files)
        XCTAssertEqual(places(found), ["go.mod:9"])
        XCTAssertEqual(found.first?.message, "Module \"golang.org/x/sync\" is required but no package in the module imports it; run `go mod tidy`.")
    }

    func testParsesManifestCallsWithoutCommentsOrNestedTargets() {
        let manifest = SwiftPackageManifest(path: "sub/Package.swift", repoRoot: URL(fileURLWithPath: "/repo"), text: """
            let package = Package(name: "P", dependencies: [.package(name: "Old", url: "x", from: "1.0.0"), .package(path: "../Local"), .package(path: "..")],
              targets: [.target(name: "A", dependencies: [.target(name: "B")], path: "Custom/A"), /* .target(name: "C") */ .plugin(name: "Gen", capability: .buildTool())])
            """)
        XCTAssertEqual(manifest.packages.map(\.name), ["Old", "Local", "repo"])
        XCTAssertEqual(manifest.targets.map(\.name), ["A", "Gen"])
        XCTAssertEqual(manifest.targets.map(\.directory), ["sub/Custom/A", "sub/Plugins/Gen"])
    }

    // MARK: missing-readme

    func testFlagsPackagesAndTargetsWithoutAReadme() throws {
        try write("Package.swift", "")
        try write("README.md", "")
        try write("Sources/Documented/README.md", "")
        try write("Sources/Catalog/Catalog.docc/Root.md", "")
        try write("packages/web/package.json", "{}")
        try write("svc/go.mod", "module x\n")
        try write("svc/readme.txt", "")
        let files = ["Package.swift", "Sources/Documented/a.swift", "Sources/Catalog/a.swift", "Sources/Bare/b.swift", "Sources/Bare/a.swift",
                     "Tests/BareTests/t.swift", "packages/web/src/index.ts", "svc/main.go"].map { Make.file($0) }
        XCTAssertTrue(findings("missing-readme", files).isEmpty)
        let found = findings("missing-readme", files, configured: true)
        XCTAssertEqual(places(found), ["packages/web/package.json:1", "Sources/Bare/a.swift:1"])
        XCTAssertEqual(found.last?.message, "Target Sources/Bare/ has no README; add one saying what it's for and how to use it.")
        let withTests = findings("missing-readme", files, params: ["includeTests": .bool(true)])
        XCTAssertEqual(places(withTests).count, 3)
    }

    // MARK: Cache

    func testFactsStoreRoundTripsStructureFacts() throws {
        let stored = Make.file("a.ts", types: [Make.type("A", .abstractClass, supers: ["B"], fields: ["x:number"], methods: ["m"], empty: ["m"])],
                               functions: [FunctionFact(name: "f", line: 2, parameters: ["a", "b:string"])],
                               switches: [SwitchFact(subject: "a.kind", line: 3, cases: ["\"x\""])])
        try JSONFactsStore(repoRoot: root).save([stored])
        XCTAssertEqual(JSONFactsStore(repoRoot: root).cachedFacts(path: "a.ts", contentHash: "h"), stored)
        let text = try String(contentsOf: root.appendingPathComponent(".bouncer-cache/facts.json"), encoding: .utf8)
        XCTAssertTrue(text.contains("\"version\":4"))
        XCTAssertFalse(text.contains("refused"), "empty lists are left out")
    }

    private func index(_ files: [FileFacts]) -> ProjectIndex {
        ProjectIndex(facts: files, resolvers: ImportResolvers(paths: Set(files.map(\.path)), repoRoot: root))
    }
}

/// A base branch whose files are fixed, for `public-api-growth`.
private struct BaseFiles: ChangeSource {
    var base: (ref: String, commit: String)? = ("main", "0123456789abcdef")
    var files: [String: String] = [:]
    func stagedChanges(in repoRoot: URL) -> [GitFileChange]? { [] }
    func mergeBase(of refs: [String], in repoRoot: URL) -> (ref: String, commit: String)? { base }
    func contents(of path: String, at commit: String, in repoRoot: URL) -> String? { files[path] }
}

/// Parses each line `name` of a file as a public symbol, or `func Name` as a Go function.
private struct LineFacts: ModuleFactsParsing {
    func moduleFacts(in file: SourceFile) -> ModuleFacts? {
        let lines = file.lines.enumerated().filter { !$0.element.isEmpty }
        if file.path.pathExtension == "go" {
            let functions = lines.map { FunctionFact(name: String($0.element), line: $0.offset + 1) }
            return ModuleFacts(imports: [], structure: StructureFacts(functions: functions))
        }
        return ModuleFacts(imports: [], exports: lines.map { ExportFact(name: String($0.element), line: $0.offset + 1) })
    }
}

final class PublicAPIGrowthTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/repo")

    private func findings(_ files: [SourceFile], source: ChangeSource, enabled: Bool = true) -> [Finding] {
        let settings = enabled ? ["public-api-growth": RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: [:]))] : [:]
        return PublicAPIGrowthRule(parser: LineFacts())
            .evaluate(files, source: source, context: AnalysisContext(repoRoot: root, ruleSettings: settings))
    }

    private func file(_ path: String, _ contents: String) -> SourceFile {
        SourceFile(path: root.appendingPathComponent(path), language: .typescript, contents: contents)
    }

    func testFlagsSymbolsDeclaredMoreOftenThanAtTheBase() {
        let source = BaseFiles(files: ["src/a.ts": "load\nsave\n", "pkg/a.go": "Run\nhelper\n"])
        let found = findings([file("src/a.ts", "load\nsave\nsave\nfetch\n"), file("pkg/a.go", "Run\nhelper\nStop\nstop\n")], source: source)
        XCTAssertEqual(found.map { "\(RepoPath.relative($0.filePath, to: root)):\($0.line)" }, ["src/a.ts:3", "src/a.ts:4", "pkg/a.go:3"])
        XCTAssertEqual(found.first?.message, "New public symbol \"save\" isn't in main (0123456); make sure growing the API is intended.")
    }

    func testReportsANewFileOnceAndSkipsTestsWithoutABaseOrUnlessConfigured() {
        let source = BaseFiles()
        let found = findings([file("src/new.ts", "a\nb\n"), file("src/new.test.ts", "c\n")], source: source)
        XCTAssertEqual(found.map(\.message), ["New file adds 2 public symbols not at main (0123456): a, b."])
        XCTAssertTrue(findings([file("src/new.ts", "a\n")], source: BaseFiles(base: nil)).isEmpty)
        XCTAssertTrue(findings([file("src/new.ts", "a\n")], source: source, enabled: false).isEmpty)
    }

    func testChangeRulesRunItWhenTheMeasurerParsesFacts() {
        let rules = ChangeRules(source: BaseFiles(), measurer: AnalyzerFunctionMeasurer(analyzers: [:]), checksStagedDiff: false)
        let settings = ["public-api-growth": RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: [:]))]
        XCTAssertTrue(rules.findings(for: [file("a.ts", "x\n")], context: AnalysisContext(repoRoot: root, ruleSettings: settings)).isEmpty)
    }
}

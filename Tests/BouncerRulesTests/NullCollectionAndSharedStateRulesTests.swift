import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

/// Return-type, enum-style, and shared-state text rules: null-collection-return, ts-prefer-union-type,
/// shared-mutable-state.
final class NullCollectionAndSharedStateRulesTests: XCTestCase {
    func lines(_ contents: String, _ language: Language, rule: String, path: String = "/repo/src/a",
               enabling: Bool = false, parameters: [String: RuleParameterValue] = [:]) -> [Int] {
        RuleTestSupport.findings(contents, language, rule: rule, path: path, enabling: enabling,
                                 parameters: parameters).map(\.line)
    }

    // MARK: null-collection-return

    func testFlagsSwiftOptionalCollectionsReturningNil() {
        let source = """
            func names(in list: [String]) -> [String]? {
                guard !list.isEmpty else { return nil }
                return list
            }
            public static func index(
                of values: [Int]
            ) throws -> [String: Int]? {
                if values.isEmpty {
                    return nil
                }
                return [:].merging([("a", 1)]) { $1 }
            }
            func tags() async -> Set<String>? {
                return nil
            }
            """
        XCTAssertEqual(lines(source, .swift, rule: "null-collection-return", enabling: true), [1, 7, 13])
        XCTAssertTrue(lines(source, .swift, rule: "null-collection-return").isEmpty, "opt-in")
    }

    func testSkipsFunctionsWhoseDocsGiveNullAMeaning() {
        let swift = """
            /// Loads the names.
            ///
            /// - Returns: The names, or `nil` if the store isn't open.
            @discardableResult
            func names() -> [String]? {
                return nil
            }
            """
        XCTAssertTrue(lines(swift, .swift, rule: "null-collection-return", enabling: true).isEmpty)
        let python = "def names(rows) -> Optional[List[str]]:\n    \"\"\"Names, or None when unloaded.\"\"\"\n"
            + "    return None\n"
        XCTAssertTrue(lines(python, .python, rule: "null-collection-return", enabling: true).isEmpty)
        let script = "/** @returns the ids, or null before loading */\nfunction ids(): string[] | null {\n  return null;\n}\n"
        XCTAssertTrue(lines(script, .typescript, rule: "null-collection-return", enabling: true).isEmpty)
    }

    func testSkipsSwiftNilInClosuresEmptyReturnsAndNonCollections() {
        let source = """
            func names(in list: [String?]) -> [String]? {
                let mapped = list.compactMap { name -> String? in
                    guard let name else { return nil }
                    return name
                }
                return mapped
            }
            func parse(_ text: String) -> [Int]? {
                if text.isEmpty { return [] }
                guard text.first != "x" else { return nil }
                return [1]
            }
            func first(_ list: [Int]) -> Int? {
                return nil
            }
            subscript(key: String) -> [Int]? {
                return nil
            }
            protocol Source {
                func items() -> [Int]?
            }
            """
        XCTAssertTrue(lines(source, .swift, rule: "null-collection-return", enabling: true).isEmpty)
        let flagged = "func items() -> [Int]? {\n    return nil\n}\n"
        XCTAssertTrue(lines(flagged, .swift, rule: "null-collection-return", path: "/repo/Tests/ATests.swift",
                            enabling: true).isEmpty)
    }

    func testFlagsTypeScriptNullableCollections() {
        let source = """
            export function ids(rows: Row[]): string[] | null {
              if (!rows.length) return null;
              return rows.map((row) => row.id);
            }
            class Cache {
              lookup(key: string): Map<string, number> | undefined {
                if (!key) {
                  return undefined;
                }
                return this.map;
              }
            }
            const load = async (url: string): Promise<string[] | null> => {
              return null;
            };
            """
        XCTAssertEqual(lines(source, .typescript, rule: "null-collection-return", enabling: true), [1, 6])
    }

    func testSkipsTypeScriptCallbacksAndNonCollections() {
        let source = """
            function find(rows: Row[]): Row | null {
              return null;
            }
            function pick(rows: Row[]): Row[] | null {
              const first = rows.find((row) => { if (row.ok) { return null; } return row; });
              return rows.filter((row) => row.ok);
            }
            function maybe(rows: Row[]): Row[] | null {
              if (!rows) return null;
              return [];
            }
            """
        XCTAssertTrue(lines(source, .typescript, rule: "null-collection-return", enabling: true).isEmpty)
        XCTAssertTrue(lines("function f(): string[] | null {\n  return null;\n}\n", .javascript,
                            rule: "null-collection-return", enabling: true).isEmpty)
    }

    func testFlagsPythonOptionalCollectionsReturningNone() {
        let source = """
            def names(rows) -> Optional[List[str]]:
                if not rows:
                    return None
                return [r.name for r in rows]

            def index(
                rows,
            ) -> dict[str, int] | None:
                def key(row):
                    return None
                return {key(r): 1 for r in rows}

            def tags(rows) -> list[str] | None:
                for row in rows:
                    if row.bad:
                        return None
                return [row.tag for row in rows]
            """
        XCTAssertEqual(lines(source, .python, rule: "null-collection-return", enabling: true), [1, 13])
    }

    func testSkipsPythonEmptyReturnsAndNonCollections() {
        let source = """
            def names(rows) -> Optional[List[str]]:
                if rows is None:
                    return None
                if not rows:
                    return []
                return [r.name for r in rows]

            def first(rows) -> Optional[str]:
                return None
            """
        XCTAssertTrue(lines(source, .python, rule: "null-collection-return", enabling: true).isEmpty)
    }

    func testFlagsJavaCollectionMethodsReturningNull() {
        let source = """
            public List<String> names(List<Row> rows) {
                if (rows.isEmpty()) {
                    return null;
                }
                return rows.stream().map(Row::name).collect(Collectors.toList());
            }
            private Map<String, Integer> index() { return null; }
            String[] parts(String text) {
                return null;
            }
            List<String> abstractNames();
            public List<String> safe(List<Row> rows) {
                if (rows == null) return null;
                return Collections.emptyList();
            }
            public String name() {
                return null;
            }
            """
        XCTAssertEqual(lines(source, .java, rule: "null-collection-return", enabling: true), [1, 7, 8])
    }

    func testSkipsGo() {
        let source = "func names(rows []Row) []string {\n\tif len(rows) == 0 {\n\t\treturn nil\n\t}\n\treturn nil\n}\n"
        XCTAssertTrue(lines(source, .go, rule: "null-collection-return", enabling: true).isEmpty)
    }

    // MARK: ts-prefer-union-type

    func testFlagsStringAndImplicitEnumsWhenEnabled() {
        let source = """
            export enum Mode {
              Read = 'read',
              Write = "write", // trailing comment
            }
            enum Direction { Up, Down, Left, Right }
            enum Level {
              /** Lowest. */
              Low,
              High,
            }
            """
        XCTAssertEqual(lines(source, .typescript, rule: "ts-prefer-union-type", enabling: true), [1, 5, 6])
        XCTAssertTrue(lines(source, .typescript, rule: "ts-prefer-union-type").isEmpty, "opt-in")
    }

    func testSkipsConstNumericNamespacedAndIteratedEnums() {
        let source = """
            const enum Fast { A = 'a', B = 'b' }
            declare enum Ambient { A, B }
            enum Flags { None = 0, Read = 1 << 0, Write = 1 << 1 }
            enum Mixed { A = 1, B }
            enum Color { Red = 'red', Green = 'green' }
            namespace Color {
              export function parse(text: string): Color { return text as Color; }
            }
            enum Size { Small = 'small', Large = 'large' }
            const sizes = Object.values(Size);
            """
        XCTAssertTrue(lines(source, .typescript, rule: "ts-prefer-union-type", enabling: true).isEmpty)
        let enumText = "enum Mode { Read = 'read' }\n"
        XCTAssertTrue(lines(enumText, .typescript, rule: "ts-prefer-union-type", path: "/repo/src/a.d.ts",
                            enabling: true).isEmpty)
        XCTAssertTrue(lines(enumText, .javascript, rule: "ts-prefer-union-type", enabling: true).isEmpty)
    }

    // MARK: shared-mutable-state

    func testFlagsSwiftGlobalAndStaticVars() {
        let source = """
            var counter = 0
            public private(set) var registry: [String: Int] = [:]
            enum Config {
                static var verbose = false
                static let name = "x"
                static var computed: Int { 1 }
                @MainActor static var ui = 0
                nonisolated(unsafe) static var escape = 0
            }
            struct Cache {
                static var shared: Cache = {
                    Cache()
                }()
                var instance = 0
                func f() {
                    var local = 0
                    local += 1
                }
            }
            """
        XCTAssertEqual(lines(source, .swift, rule: "shared-mutable-state"), [1, 2, 4, 11])
    }

    func testSkipsIsolatedOrGuardedSwiftState() {
        let isolated = """
            actor Store {
                static var count = 0
            }
            @MainActor
            final class Model {
                static var current = 0
            }
            @TaskLocal static var trace: String?
            protocol Named {
                static var name: String { get }
            }
            """
        XCTAssertTrue(lines(isolated, .swift, rule: "shared-mutable-state").isEmpty)
        let locked = "import os\nlet lock = OSAllocatedUnfairLock()\nvar counter = 0\n"
        XCTAssertTrue(lines(locked, .swift, rule: "shared-mutable-state").isEmpty)
        XCTAssertTrue(lines("var counter = 0\n", .swift, rule: "shared-mutable-state", path: "/repo/Sources/App/main.swift")
            .isEmpty)
    }

    func testFlagsGoPackageVarsAssignedInFunctions() {
        let source = """
            package cache

            var hits int
            var (
            \tentries = map[string]string{}
            \tlimit   = 10
            )

            func init() {
            \tlimit = 20
            }

            func Put(key, value string) {
            \tentries[key] = value
            \thits++
            }

            func Get(limit int) int {
            \tlimit = 3
            \treturn limit
            }
            """
        XCTAssertEqual(lines(source, .go, rule: "shared-mutable-state"), [3, 5])
        let guarded = source.replacingOccurrences(of: "package cache\n", with: "package cache\n\nimport \"sync\"\n")
        XCTAssertTrue(lines(guarded, .go, rule: "shared-mutable-state").isEmpty)
        XCTAssertTrue(lines(source, .go, rule: "shared-mutable-state", path: "/repo/cache_test.go").isEmpty)
    }

    func testScriptAndPythonAreOptInThroughLanguages() {
        let script = """
            let token: string | null = null;
            let calls = 0;
            const limit = 3;
            export async function refresh() {
              token = await fetchToken();
            }
            function count(calls: number) {
              calls += 1;
            }
            """
        XCTAssertTrue(lines(script, .typescript, rule: "shared-mutable-state").isEmpty)
        let enabled: [String: RuleParameterValue] = ["languages": .stringList(["typescript", "javascript", "python"])]
        XCTAssertEqual(lines(script, .typescript, rule: "shared-mutable-state", parameters: enabled), [1])
        let sync = script.replacingOccurrences(of: "async ", with: "").replacingOccurrences(of: "await ", with: "")
        XCTAssertTrue(lines(sync, .javascript, rule: "shared-mutable-state", parameters: enabled).isEmpty)
        let python = "import threading\n\ncount = 0\n\ndef bump():\n    global count\n    count += 1\n"
        XCTAssertEqual(lines(python, .python, rule: "shared-mutable-state", parameters: enabled), [6])
        let locked = python + "lock = threading.Lock()\n"
        XCTAssertTrue(lines(locked, .python, rule: "shared-mutable-state", parameters: enabled).isEmpty)
        let single = python.replacingOccurrences(of: "import threading\n", with: "")
        XCTAssertTrue(lines(single, .python, rule: "shared-mutable-state", parameters: enabled).isEmpty)
    }
}

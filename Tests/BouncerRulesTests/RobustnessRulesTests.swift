import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

/// Error handling, concurrency, and resource rules: empty-catch (text), swift-precondition, go-unwrapped-error,
/// generic-error-message, resource-leak, fire-and-forget-task, go-unmanaged-goroutine.
final class RobustnessRulesTests: XCTestCase {
    func lines(_ contents: String, _ language: Language, rule: String, path: String = "/repo/src/a",
               enabling: Bool = false, parameters: [String: RuleParameterValue] = [:]) -> [Int] {
        RuleTestSupport.findings(contents, language, rule: rule, path: path, enabling: enabling,
                                 parameters: parameters).map(\.line)
    }

    // MARK: empty-catch (text)

    func testFlagsEmptyCatchInJavaCppAndPowerShell() {
        let java = "try {\n  run();\n} catch (IOException e) {\n}\ntry { a(); } catch (Exception e) {}\n"
        XCTAssertEqual(lines(java, .java, rule: "empty-catch"), [3, 5])
        let cpp = "try {\n  f();\n} catch (...) {\n\n}\n"
        XCTAssertEqual(lines(cpp, .cpp, rule: "empty-catch"), [3])
        let ps = "try {\n  Get-Item x\n} catch [System.IO.IOException], [System.Exception] {\n}\ntry { a } catch { }\n"
        XCTAssertEqual(lines(ps, .powershell, rule: "empty-catch"), [3, 5])
        XCTAssertEqual(lines("try { x(); } catch (e: Exception) { }\n", .other("kt"), rule: "empty-catch"), [1])
    }

    func testSkipsCatchWithBodyOrCommentAndParsedLanguages() {
        let java = """
            try { run(); } catch (IOException e) {
                // nothing to clean up: the file is optional
            }
            try { run(); } catch (IOException e) { log.warn("x", e); }
            try { run(); } catch (IOException e) { /* expected */ }
            // } catch (Exception e) {}
            String s = "catch (x) {}";
            """
        XCTAssertTrue(lines(java, .java, rule: "empty-catch").isEmpty)
        XCTAssertTrue(lines("try { f() } catch (e) {}\n", .typescript, rule: "empty-catch").isEmpty)
        XCTAssertTrue(lines("try {\n  Get-Item x\n} catch {\n  Write-Warning $_\n}\n", .powershell,
                            rule: "empty-catch").isEmpty)
    }

    // MARK: swift-fatal-error and swift-precondition

    func testFatalErrorIsOnAndPreconditionIsOptIn() {
        let source = "fatalError(\"x\")\nprecondition(n > 0)\npreconditionFailure(\"y\")\nassert(n > 0)\n"
        XCTAssertEqual(lines(source, .swift, rule: "swift-fatal-error"), [1])
        XCTAssertTrue(lines(source, .swift, rule: "swift-precondition").isEmpty)
        XCTAssertEqual(lines(source, .swift, rule: "swift-precondition", enabling: true), [2, 3])
    }

    func testLibraryOnlySkipsExecutableCode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("crash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = root.appendingPathComponent("Sources/Tool"), lib = root.appendingPathComponent("Sources/Lib")
        let app = root.appendingPathComponent("Sources/App")
        for directory in [tool, lib, app] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "print(1)\n".write(to: tool.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "@main\nstruct App {}\n".write(to: app.appendingPathComponent("App.swift"), atomically: true, encoding: .utf8)
        let params: [String: RuleParameterValue] = ["libraryOnly": .bool(true)]
        let source = "func f() {\n    fatalError(\"x\")\n}\n"
        for (directory, expected) in [(tool, [Int]()), (app, []), (lib, [2])] {
            let path = directory.appendingPathComponent("Helpers.swift").path
            XCTAssertEqual(lines(source, .swift, rule: "swift-fatal-error", path: path, enabling: true,
                                 parameters: params), expected, directory.lastPathComponent)
        }
        XCTAssertEqual(lines(source, .swift, rule: "swift-fatal-error", path: lib.appendingPathComponent("H.swift").path),
                       [2])
    }

    func testLibraryOnlyReadsExecutableTargetsFromThePackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = root.appendingPathComponent("Sources/cli")
        try FileManager.default.createDirectory(at: cli, withIntermediateDirectories: true)
        try "let p = Package(targets: [.executableTarget(name: \"cli\")])\n"
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let path = cli.appendingPathComponent("Command.swift").path
        XCTAssertTrue(lines("precondition(x)\n", .swift, rule: "swift-precondition", path: path, enabling: true,
                            parameters: ["libraryOnly": .bool(true)]).isEmpty)
    }

    func testLibraryOnlyClimbsToAToolsEntryPointAndSkipsTests() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tool-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Tools/gen/DSL")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "@main struct Gen {}\n".write(to: root.appendingPathComponent("Tools/gen/Gen.swift"), atomically: true,
                                          encoding: .utf8)
        let params: [String: RuleParameterValue] = ["libraryOnly": .bool(true)]
        XCTAssertTrue(lines("fatalError()\n", .swift, rule: "swift-fatal-error",
                            path: nested.appendingPathComponent("Node.swift").path, parameters: params).isEmpty)
        XCTAssertTrue(lines("fatalError()\n", .swift, rule: "swift-fatal-error",
                            path: "/repo/Tests/LibTests/ATests.swift", parameters: params).isEmpty)
    }

    // MARK: go-unwrapped-error

    func testFlagsBareGoErrorReturns() {
        let source = """
            func load() (*Config, error) {
            \tdata, err := os.ReadFile(path)
            \tif err != nil {
            \t\treturn nil, err
            \t}
            \tif err := json.Unmarshal(data, &c); err != nil {
            \t\treturn nil, err
            \t}
            \tif err != nil { return err }
            \treturn c, nil
            }
            """
        XCTAssertEqual(lines(source, .go, rule: "go-unwrapped-error", path: "/repo/a.go", enabling: true), [3, 6, 9])
        XCTAssertTrue(lines(source, .go, rule: "go-unwrapped-error", path: "/repo/a.go").isEmpty)
    }

    func testSkipsWrappedOrHandledGoErrors() {
        let source = """
            \tif err != nil {
            \t\treturn fmt.Errorf("reading %s: %w", path, err)
            \t}
            \tif err != nil {
            \t\tlog.Print(err)
            \t\treturn err
            \t}
            \tif err != nil {
            \t\treturn errors.Wrap(err, "load")
            \t}
            \tif ok != nil {
            \t\treturn ok
            \t}
            """
        XCTAssertTrue(lines(source, .go, rule: "go-unwrapped-error", path: "/repo/a.go", enabling: true).isEmpty)
        let bare = "\tif err != nil {\n\t\treturn err\n\t}\n"
        XCTAssertTrue(lines(bare, .go, rule: "go-unwrapped-error", path: "/repo/a_test.go", enabling: true).isEmpty)
    }

    // MARK: generic-error-message

    func testFlagsGenericErrorMessages() {
        XCTAssertEqual(lines("throw new Error(\"Something went wrong\");\nreject(new Error('failed'))\n", .typescript,
                             rule: "generic-error-message"), [1, 2])
        XCTAssertEqual(lines("raise ValueError(\"invalid input\")\nraise Exception('')\n", .python,
                             rule: "generic-error-message"), [1, 2])
        XCTAssertEqual(lines("\treturn errors.New(\"error\")\n\treturn fmt.Errorf(\"operation failed\")\n", .go,
                             rule: "generic-error-message"), [1, 2])
        XCTAssertEqual(lines("throw new RuntimeException(\"Unexpected error\");\n", .java,
                             rule: "generic-error-message"), [1])
        XCTAssertEqual(lines("throw ValidationError(\"Invalid value\")\n", .swift, rule: "generic-error-message"), [1])
        XCTAssertEqual(lines("throw \"Failed\"\n", .powershell, rule: "generic-error-message"), [1])
    }

    func testSkipsSpecificOrInterpolatedErrorMessages() {
        let source = """
            throw new Error("Not implemented");
            throw new Error(`Failed to load ${path}`);
            throw new Error("Unknown option: " + name);
            throw new Error("Request timed out");
            // throw new Error("failed")
            """
        XCTAssertTrue(lines(source, .typescript, rule: "generic-error-message").isEmpty)
        XCTAssertTrue(lines("\treturn fmt.Errorf(\"failed: %w\", err)\n", .go, rule: "generic-error-message").isEmpty)
        XCTAssertTrue(lines("raise ValueError(f\"invalid {x}\")\n", .python, rule: "generic-error-message").isEmpty)
        XCTAssertTrue(lines("throw new Error(\"failed\")\n", .typescript, rule: "generic-error-message",
                            path: "/repo/src/a.test.ts").isEmpty)
    }

    // MARK: resource-leak

    func testFlagsUnclosedHandles() {
        let go = "func f() {\n\tf, err := os.Open(p)\n\tif err != nil {\n\t\treturn\n\t}\n\tuse(f)\n}\n"
        XCTAssertEqual(lines(go, .go, rule: "resource-leak"), [2])
        let python = "def f():\n    fh = open(path)\n    data = fh.read()\n    return data\n"
        XCTAssertEqual(lines(python, .python, rule: "resource-leak"), [2])
        let java = "void f() {\n  FileInputStream in = new FileInputStream(file);\n  in.read();\n}\n"
        XCTAssertEqual(lines(java, .java, rule: "resource-leak"), [2])
        let swift = "func f() {\n    let handle = FileHandle(forReadingAtPath: p)\n    _ = handle?.readDataToEndOfFile()\n}\n"
        XCTAssertEqual(lines(swift, .swift, rule: "resource-leak"), [2])
        XCTAssertEqual(lines("function f() {\n  const fd = fs.openSync(p, 'r');\n  read(fd);\n}\n", .javascript,
                             rule: "resource-leak"), [2])
        XCTAssertEqual(lines("void f() {\n  FILE *fp = fopen(p, \"r\");\n  fread(b, 1, 1, fp);\n}\n", .c,
                             rule: "resource-leak"), [2])
    }

    func testSkipsClosedOrHandedOffHandles() {
        let go = """
            func f() (*os.File, error) {
            \tf, err := os.Open(p)
            \tif err != nil {
            \t\treturn nil, err
            \t}
            \tdefer f.Close()
            \tg, err := os.Create(q)
            \treturn g, err
            }
            """
        XCTAssertTrue(lines(go, .go, rule: "resource-leak").isEmpty)
        let python = "def f():\n    fh = open(path)\n    try:\n        fh.read()\n    finally:\n        fh.close()\n"
        XCTAssertTrue(lines(python, .python, rule: "resource-leak").isEmpty)
        XCTAssertTrue(lines("with open(p) as fh:\n    fh.read()\nself.log = open(p)\n", .python,
                            rule: "resource-leak").isEmpty)
        let java = "try (FileInputStream in = new FileInputStream(f)) {\n  in.read();\n}\n"
        XCTAssertTrue(lines(java, .java, rule: "resource-leak").isEmpty)
        let swift = "func f() {\n    let h = FileHandle(forReadingAtPath: p)\n    defer { try? h?.close() }\n}\n"
        XCTAssertTrue(lines(swift, .swift, rule: "resource-leak").isEmpty)
        XCTAssertTrue(lines("def lines(p):\n    fh = open(p)\n    yield fh\n", .python, rule: "resource-leak").isEmpty)
        let readOnly = "def f(p):\n    fh = open(p)\n    return fh.read()\n"
        XCTAssertEqual(lines(readOnly, .python, rule: "resource-leak"), [2])
        XCTAssertTrue(lines("void f() {\n  FILE *fp = fopen(p, \"r\");\n  fclose(fp);\n}\n", .c,
                            rule: "resource-leak").isEmpty)
    }

    // MARK: fire-and-forget-task

    func testFlagsForgottenTasksWhenEnabled() {
        let source = """
            func load() {
                Task {
                    await model.refresh()
                }
                Button("Go") { Task { await go() } }
                _ = Task.detached(priority: .background) { await work() }
            }
            """
        XCTAssertEqual(lines(source, .swift, rule: "fire-and-forget-task", enabling: true), [2, 5, 6])
        XCTAssertTrue(lines(source, .swift, rule: "fire-and-forget-task").isEmpty)
    }

    func testSkipsStoredOrCancellationAwareTasks() {
        let source = """
            loadTask = Task { await model.refresh() }
            let t = Task { await x() }
            return Task { await y() }
            .task { await model.refresh() }
            Task {
                while !Task.isCancelled { await tick() }
            }
            Task {
                try Task.checkCancellation()
            }
            """
        XCTAssertTrue(lines(source, .swift, rule: "fire-and-forget-task", enabling: true).isEmpty)
    }

    // MARK: go-unmanaged-goroutine

    func testFlagsGoroutinesWithNoCoordination() {
        let source = """
            func notify(users []User) {
            \tfor _, u := range users {
            \t\tgo send(u)
            \t}
            }

            func start(s *Server) {
            \tgo func() {
            \t\ts.run()
            \t}()
            }
            """
        XCTAssertEqual(lines(source, .go, rule: "go-unmanaged-goroutine"), [3, 8])
    }

    func testDoesNotBorrowCoordinationFromCodeAfterTheFunction() {
        let source = """
            func fire() {
            \tgo doWork()
            }

            var mu sync.Mutex

            func shutdown(ctx context.Context) {}
            """
        XCTAssertEqual(lines(source, .go, rule: "go-unmanaged-goroutine"), [2])
    }

    func testSkipsGoroutinesWithContextWaitGroupOrChannel() {
        let source = """
            func a(ctx context.Context) {
            \tgo worker(ctx)
            }

            func b(items []int) {
            \tvar wg sync.WaitGroup
            \tfor _, i := range items {
            \t\twg.Add(1)
            \t\tgo func(i int) { defer wg.Done(); work(i) }(i)
            \t}
            \twg.Wait()
            }

            func c() <-chan int {
            \tout := make(chan int)
            \tgo func() { out <- 1 }()
            \treturn out
            }

            func d(x interface{}) {
            \tdone := make(chan struct{})
            \tgo func() { close(done) }()
            }
            """
        XCTAssertTrue(lines(source, .go, rule: "go-unmanaged-goroutine").isEmpty)
    }
}

/// Builds the text rules for a language and runs one of them, for the wave of text rules tested here.
enum RuleTestSupport {
    static func findings(_ contents: String, _ language: Language, rule: String, path: String, enabling: Bool,
                         parameters: [String: RuleParameterValue]) -> [Finding] {
        let file = SourceFile(path: URL(fileURLWithPath: path), language: language, contents: contents)
        let settings = RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: parameters))
        let configured = enabling || !parameters.isEmpty ? [rule: settings] : [:]
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: configured)
        return TextRules.make(profile: LanguageProfiles.profile(for: language))
            .filter { $0.id == rule }
            .flatMap { $0.evaluate(file: file, context: context) }
    }
}

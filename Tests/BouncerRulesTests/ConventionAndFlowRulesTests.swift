import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

/// Test-hygiene, debug-leftover, convention, and data-flow security rules: test-sleep, test-network-call,
/// test-real-clock, c-debug-print, cpp-debug-print, powershell-debug-leftover, missing-file-header, abbreviation,
/// forbidden-import, path-traversal, logged-secret.
final class ConventionAndFlowRulesTests: XCTestCase {
    func lines(_ contents: String, _ language: Language, rule: String, path: String = "/repo/src/a",
               enabling: Bool = false, parameters: [String: RuleParameterValue] = [:]) -> [Int] {
        RuleTestSupport.findings(contents, language, rule: rule, path: path, enabling: enabling,
                                 parameters: parameters).map(\.line)
    }

    // MARK: test-sleep, test-network-call, test-real-clock

    func testFlagsSleepsInTestFilesOnly() {
        let swift = "func testA() async throws {\n    try await Task.sleep(nanoseconds: 1_000)\n    sleep(1)\n}\n"
        XCTAssertEqual(lines(swift, .swift, rule: "test-sleep", path: "/repo/Tests/ATests.swift"), [2, 3])
        XCTAssertTrue(lines(swift, .swift, rule: "test-sleep", path: "/repo/Sources/A.swift").isEmpty)
        let python = "import time\ndef test_a():\n    time.sleep(0.5)\n    await asyncio.sleep(0)\n"
        XCTAssertEqual(lines(python, .python, rule: "test-sleep", path: "/repo/tests/test_a.py"), [3])
        XCTAssertEqual(lines("\ttime.Sleep(100 * time.Millisecond)\n", .go, rule: "test-sleep",
                             path: "/repo/a_test.go"), [1])
        let script = "await new Promise((r) => setTimeout(r, 200));\nsetTimeout(done, 0);\n"
        XCTAssertEqual(lines(script, .typescript, rule: "test-sleep", path: "/repo/src/a.test.ts"), [1])
    }

    func testSkipsSleepsWithFakeTimersOrMocks() {
        let script = "jest.useFakeTimers();\nawait new Promise((r) => setTimeout(r, 200));\n"
        XCTAssertTrue(lines(script, .typescript, rule: "test-sleep", path: "/repo/src/a.test.ts").isEmpty)
        let python = "@patch(\"time.sleep\")\ndef test_a(sleep):\n    time.sleep(5)\n"
        XCTAssertTrue(lines(python, .python, rule: "test-sleep", path: "/repo/tests/test_a.py").isEmpty)
        let declared = "func sleep(_ n: Int) {}\n// sleep(1)\nlet s = \"sleep(1)\"\n"
        XCTAssertTrue(lines(declared, .swift, rule: "test-sleep", path: "/repo/Tests/ATests.swift").isEmpty)
    }

    func testFlagsRealNetworkCallsInTests() {
        let script = "const r = await fetch('https://api.github.com/users');\nawait fetch('http://localhost:3000');\n"
        XCTAssertEqual(lines(script, .typescript, rule: "test-network-call", path: "/repo/src/a.spec.ts"), [1])
        XCTAssertEqual(lines("    r = requests.get(\"https://example.org/x\")\n", .python, rule: "test-network-call",
                             path: "/repo/tests/test_a.py"), [1])
        XCTAssertEqual(lines("\tresp, _ := http.Get(\"https://golang.org\")\n\thttp.Get(srv.URL)\n", .go,
                             rule: "test-network-call", path: "/repo/a_test.go"), [1])
        XCTAssertEqual(lines("let (d, _) = try await URLSession.shared.data(from: url)\n", .swift,
                             rule: "test-network-call", path: "/repo/Tests/ATests.swift"), [1])
        let mocked = "import nock from 'nock';\nawait fetch('https://api.github.com');\n"
        XCTAssertTrue(lines(mocked, .typescript, rule: "test-network-call", path: "/repo/src/a.test.ts").isEmpty)
    }

    func testRealClockIsOptIn() {
        let source = "let now = Date()\nlet t = Date.now\n"
        let path = "/repo/Tests/ATests.swift"
        XCTAssertTrue(lines(source, .swift, rule: "test-real-clock", path: path).isEmpty)
        XCTAssertEqual(lines(source, .swift, rule: "test-real-clock", path: path, enabling: true), [1, 2])
        XCTAssertEqual(lines("\tstart := time.Now()\n", .go, rule: "test-real-clock", path: "/repo/a_test.go",
                             enabling: true), [1])
        let frozen = "@freeze_time(\"2020-01-01\")\ndef test_a():\n    datetime.now()\n"
        XCTAssertTrue(lines(frozen, .python, rule: "test-real-clock", path: "/repo/tests/test_a.py",
                            enabling: true).isEmpty)
    }

    // MARK: debug leftovers

    func testFlagsCAndCppDebugOutput() {
        let c = "printf(\"DEBUG: x=%d\\n\", x);\nfprintf(stderr, \"here\\n\");\nprintf(\"Done: %d\\n\", n);\n"
            + "fprintf(stderr, \"error: %s\\n\", msg);\n"
        XCTAssertEqual(lines(c, .c, rule: "c-debug-print"), [1, 2])
        let cpp = "std::cerr << \"[DBG] size \" << n;\nstd::cout << \"Result: \" << r;\nprintf(\"debug: %d\", x);\n"
        XCTAssertEqual(lines(cpp, .cpp, rule: "cpp-debug-print"), [1, 3])
    }

    func testFlagsPowerShellDebugLeftovers() {
        let source = "Set-PSDebug -Trace 1\n$DebugPreference = 'Continue'\nWrite-Host \"DEBUG: $x\"\n"
            + "Set-PSDebug -Off\nWrite-Host \"Debugging tips\"\nWrite-Debug \"x\"\nWait-Debugger\n"
        XCTAssertEqual(lines(source, .powershell, rule: "powershell-debug-leftover"), [1, 2, 3, 7])
    }

    // MARK: missing-file-header

    func testMissingFileHeaderIsOptIn() {
        let bare = "import Foundation\n\nstruct A {}\n"
        XCTAssertTrue(lines(bare, .swift, rule: "missing-file-header").isEmpty)
        XCTAssertEqual(lines(bare, .swift, rule: "missing-file-header", enabling: true), [1])
        let documented = "/// A thing.\nstruct A {}\n"
        XCTAssertEqual(lines(documented, .swift, rule: "missing-file-header", enabling: true), [1])
    }

    func testAcceptsHeadersAndChecksThePattern() {
        let header = "// Copyright 2026 Acme. MIT License.\n\nimport Foundation\n"
        XCTAssertTrue(lines(header, .swift, rule: "missing-file-header", enabling: true).isEmpty)
        XCTAssertTrue(lines("#!/bin/bash\n# Deploys the app.\nset -e\n", .bash, rule: "missing-file-header",
                            enabling: true).isEmpty)
        XCTAssertTrue(lines("\"\"\"Utilities.\"\"\"\nimport os\n", .python, rule: "missing-file-header",
                            enabling: true).isEmpty)
        XCTAssertTrue(lines("// Package x does y.\npackage x\n", .go, rule: "missing-file-header",
                            enabling: true).isEmpty)
        let params: [String: RuleParameterValue] = ["pattern": .string("SPDX-License-Identifier")]
        XCTAssertEqual(lines(header, .swift, rule: "missing-file-header", parameters: params), [1])
        let spdx = "// SPDX-License-Identifier: MIT\nimport Foundation\n"
        XCTAssertTrue(lines(spdx, .swift, rule: "missing-file-header", parameters: params).isEmpty)
    }

    // MARK: abbreviation

    func testFlagsAbbreviatedDeclarations() {
        let source = "let usrMgr = UserManager()\nfunc calcTotal() {}\nlet userManager = x\n// let btn = 1\n"
            + "let s = \"let cfg = 1\"\n"
        XCTAssertTrue(lines(source, .swift, rule: "abbreviation").isEmpty)
        XCTAssertEqual(lines(source, .swift, rule: "abbreviation", enabling: true), [1, 2])
        XCTAssertEqual(lines("btn_cnt = 3\n", .python, rule: "abbreviation", enabling: true), [1])
    }

    func testAbbreviationIdiomsAndParameters() {
        XCTAssertTrue(lines("\tctx, req := a, b\n\tmsg := \"x\"\n", .go, rule: "abbreviation", enabling: true).isEmpty)
        XCTAssertEqual(lines("let ctx = makeContext()\n", .swift, rule: "abbreviation", enabling: true), [1])
        let allow: [String: RuleParameterValue] = ["allow": .stringList(["expr", "decl"])]
        XCTAssertTrue(lines("let exprDecl = x\n", .swift, rule: "abbreviation", parameters: allow).isEmpty)
        let deny: [String: RuleParameterValue] = ["deny": .stringList(["svr=server", "foo"])]
        let found = RuleTestSupport.findings("let svrName = x\n", .swift, rule: "abbreviation", path: "/repo/a",
                                             enabling: true, parameters: deny)
        XCTAssertEqual(found.first?.message, "'svrName' uses the abbreviation 'svr'; spell it out ('server').")
    }

    // MARK: forbidden-import

    func testForbiddenImportsByPath() {
        let params: [String: RuleParameterValue] = ["deny": .stringList(["Sources/Domain/**=UIKit, Alamofire", "lodash"])]
        let swift = "import Foundation\nimport UIKit\nimport struct Alamofire.Session\n"
        XCTAssertEqual(lines(swift, .swift, rule: "forbidden-import", path: "/repo/Sources/Domain/User.swift",
                             parameters: params), [2, 3])
        XCTAssertTrue(lines(swift, .swift, rule: "forbidden-import", path: "/repo/Sources/App/View.swift",
                            parameters: params).isEmpty)
        XCTAssertEqual(lines("import fp from 'lodash/fp';\nimport x from 'lodasher';\n", .typescript,
                             rule: "forbidden-import", path: "/repo/web/a.ts", parameters: params), [1])
        XCTAssertTrue(lines(swift, .swift, rule: "forbidden-import", path: "/repo/Sources/Domain/User.swift").isEmpty)
    }

    func testAllowListedImports() {
        let params: [String: RuleParameterValue] = ["allow": .stringList(["core/**=os, typing, core.*"])]
        let python = "import os\nimport requests\nfrom core.models import User\nfrom typing import Any\n"
        XCTAssertEqual(lines(python, .python, rule: "forbidden-import", path: "/repo/core/a.py", parameters: params),
                       [2])
        let java = "import java.util.List;\nimport org.springframework.web.Bean;\n"
        let deny: [String: RuleParameterValue] = ["deny": .stringList(["org.springframework*"])]
        XCTAssertEqual(lines(java, .java, rule: "forbidden-import", path: "/repo/A.java", parameters: deny), [2])
        XCTAssertEqual(lines("\"net/http\"\nimport (\n\tnet \"net/http\"\n)\n", .go, rule: "forbidden-import",
                             path: "/repo/a.go", parameters: ["deny": .stringList(["net/http"])]), [3])
    }

    // MARK: path-traversal

    func testFlagsRequestInputInFilePaths() {
        let script = """
            app.get('/f/:name', (req, res) => res.sendFile(path.join(ROOT, req.params.name)));
            const { file } = req.query;
            const data = fs.readFileSync(path.join(dir, file));
            """
        XCTAssertEqual(lines(script, .javascript, rule: "path-traversal"), [1, 3])
        let python = """
            @app.route("/files/<filename>")
            def download(filename):
                return send_file(os.path.join(UPLOADS, filename))
            name = request.args.get("name")
            with open(os.path.join(BASE, name)) as fh:
                pass
            """
        XCTAssertEqual(lines(python, .python, rule: "path-traversal"), [3, 5])
        let go = "\tname := r.URL.Query().Get(\"f\")\n\tf, err := os.Open(filepath.Join(root, name))\n"
        XCTAssertEqual(lines(go, .go, rule: "path-traversal"), [2])
    }

    func testSkipsSanitizedOrUnrelatedPaths() {
        let script = """
            const name = path.basename(req.params.name);
            res.sendFile(path.join(ROOT, name));
            res.sendFile(path.join(ROOT, 'index.html'));
            const id = parseInt(req.query.id, 10);
            fs.readFileSync(path.join(dir, `${id}.json`));
            """
        XCTAssertTrue(lines(script, .javascript, rule: "path-traversal").isEmpty)
        let python = "name = secure_filename(request.args['f'])\nopen(os.path.join(BASE, name))\n"
        XCTAssertTrue(lines(python, .python, rule: "path-traversal").isEmpty)
        let farAway = "name = request.args['f']\n" + String(repeating: "x = 1\n", count: 12) + "open(name)\n"
        XCTAssertTrue(lines(farAway, .python, rule: "path-traversal").isEmpty)
        let reassigned = "let name = req.query.name;\nname = ALLOWED.has(name) ? name : 'home';\n"
            + "res.sendFile(path.join(VIEWS, name));\n"
        XCTAssertTrue(lines(reassigned, .typescript, rule: "path-traversal").isEmpty)
    }

    func testNetworkCallsSkipOnlyInterceptingMocks() {
        let local = "srv := httptest.NewServer(h)\n\tresp, _ := http.Get(\"https://golang.org\")\n"
        XCTAssertEqual(lines(local, .go, rule: "test-network-call", path: "/repo/a_test.go"), [2])
        let intercepted = "gock.New(\"https://golang.org\")\n\tresp, _ := http.Get(\"https://golang.org\")\n"
        XCTAssertTrue(lines(intercepted, .go, rule: "test-network-call", path: "/repo/a_test.go").isEmpty)
    }

    func testTextAndDataFilesAreSkipped() {
        let fixture = "try { x() } catch (e) {}\nconsole.log(password)\n"
        XCTAssertTrue(lines(fixture, .other("txt"), rule: "empty-catch").isEmpty)
        XCTAssertTrue(lines(fixture, .other("txt"), rule: "logged-secret").isEmpty)
        XCTAssertEqual(lines("println!(\"{}\", password);\n", .other("rs"), rule: "logged-secret"), [1])
        XCTAssertTrue(lines("let objCSelector = x\n", .swift, rule: "abbreviation", enabling: true).isEmpty)
    }

    // MARK: logged-secret

    func testFlagsLoggedSecrets() {
        let script = "console.log('login', user, password);\nlogger.info(`token=${accessToken}`);\n"
        XCTAssertEqual(lines(script, .typescript, rule: "logged-secret"), [1, 2])
        XCTAssertEqual(lines("logging.debug(f\"key {api_key}\")\nprint(client_secret)\n", .python,
                             rule: "logged-secret"), [1, 2])
        XCTAssertEqual(lines("\tlog.Printf(\"auth %s\", authToken)\n", .go, rule: "logged-secret"), [1])
        XCTAssertEqual(lines("logger.info(\"pw: \\(user.password)\")\n", .swift, rule: "logged-secret"), [1])
        XCTAssertEqual(lines("Write-Host \"Password is $Password\"\n", .powershell, rule: "logged-secret"), [1])
    }

    func testSkipsMentionsThatDontLogTheSecret() {
        let script = """
            console.log("Enter your password");
            console.log('token count', tokenCount, passwordField);
            console.log('has token', token.length, !!authToken);
            logger.info(redact(password));
            console.log({ password: '***' });
            console.log(validatePassword(input));
            console.log('tokens', token);
            """
        XCTAssertTrue(lines(script, .typescript, rule: "logged-secret").isEmpty)
        XCTAssertTrue(lines("print(len(password))\nlog.info(\"secret set: %s\", secret is not None)\n", .python,
                            rule: "logged-secret").isEmpty)
        XCTAssertTrue(lines("console.log(password);\n", .typescript, rule: "logged-secret",
                            path: "/repo/src/a.test.ts").isEmpty)
    }
}

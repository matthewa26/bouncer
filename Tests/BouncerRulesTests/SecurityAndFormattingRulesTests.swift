import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class SecurityAndFormattingRulesTests: XCTestCase {
    private let defaults = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    private func findings(
        _ contents: String, _ language: Language, rule: String, path: String = "/repo/src/a", enabling: Bool = false
    ) -> [Finding] {
        let file = SourceFile(path: URL(fileURLWithPath: path), language: language, contents: contents)
        let settings = enabling ? [rule: RuleSettings(enabled: true, severity: .warning, parameters: .empty)] : [:]
        let context = enabling ? AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings) : defaults
        return TextRules.make(profile: LanguageProfiles.profile(for: language))
            .filter { $0.id == rule }
            .flatMap { $0.evaluate(file: file, context: context) }
    }

    private func lines(_ contents: String, _ language: Language, rule: String, path: String = "/repo/src/a",
                       enabling: Bool = false) -> [Int] {
        findings(contents, language, rule: rule, path: path, enabling: enabling).map(\.line)
    }

    // MARK: swift-shell-injection

    func testFlagsSwiftShellWithInterpolatedCommand() {
        let source = """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "git log \\(ref)"]
            """
        XCTAssertEqual(lines(source, .swift, rule: "swift-shell-injection"), [3])
    }

    func testFlagsSwiftEnvShellAndMultiLineArguments() {
        let env = """
            let task = Process()
            task.arguments = ["bash", "-c", "rm -rf \\(dir)"]
            """
        XCTAssertEqual(lines(env, .swift, rule: "swift-shell-injection"), [2])
        let multiLine = """
            let process = Process()
            process.launchPath = "/bin/sh"
            process.arguments = [
                "-c",
                "echo \\(name)"
            ]
            """
        XCTAssertEqual(lines(multiLine, .swift, rule: "swift-shell-injection"), [4])
    }

    func testSkipsSwiftShellWithoutInterpolationOrShell() {
        let literal = "let p = Process()\np.executableURL = URL(fileURLWithPath: \"/bin/sh\")\np.arguments = [\"-c\", \"ls -la\"]\n"
        XCTAssertTrue(lines(literal, .swift, rule: "swift-shell-injection").isEmpty)
        let variable = "let p = Process()\np.executableURL = URL(fileURLWithPath: \"/bin/sh\")\np.arguments = [\"-c\", command]\n"
        XCTAssertTrue(lines(variable, .swift, rule: "swift-shell-injection").isEmpty)
        let python = "let p = Process()\np.executableURL = URL(fileURLWithPath: \"/usr/bin/python3\")\np.arguments = [\"-c\", \"print(\\(x))\"]\n"
        XCTAssertTrue(lines(python, .swift, rule: "swift-shell-injection").isEmpty)
        let noProcess = "let args = [\"sh\", \"-c\", \"echo \\(x)\"]\n"
        XCTAssertTrue(lines(noProcess, .swift, rule: "swift-shell-injection").isEmpty)
    }

    // MARK: insecure-random

    func testFlagsMathRandomForTokensAndIds() {
        let source = """
            const token = Math.random().toString(16).slice(2);
            const id = Math.random().toString(36).substring(2, 9);
            this.sessionId = Math.floor(Math.random() * 1e9);
            const opts = { nonce: Math.random() };
            """
        XCTAssertEqual(lines(source, .typescript, rule: "insecure-random"), [1, 2, 3, 4])
    }

    func testFlagsMathRandomInsideATokenFunction() {
        let source = """
            function generatePassword(length) {
              let out = "";
              for (let i = 0; i < length; i++) out += chars[Math.floor(Math.random() * chars.length)];
              return out;
            }
            """
        XCTAssertEqual(lines(source, .javascript, rule: "insecure-random"), [3])
    }

    func testSkipsMathRandomForGamesAnimationsAndTests() {
        let source = """
            const width = Math.random() * 100;
            const delay = Math.random() * 500;
            if (Math.random() < 0.5) flip();
            function randomColor() { return "#" + Math.floor(Math.random() * 16777215).toString(16); }
            // const token = Math.random();
            """
        XCTAssertTrue(lines(source, .typescript, rule: "insecure-random").isEmpty)
        let test = "const token = Math.random().toString(36);\n"
        XCTAssertTrue(lines(test, .typescript, rule: "insecure-random", path: "/repo/src/auth.test.ts").isEmpty)
    }

    func testFlagsPythonRandomAndGoMathRandOnlyWithTheirImports() {
        let python = "import random\nsecret_key = ''.join(random.choice(letters) for _ in range(32))\nx = random.random()\n"
        XCTAssertEqual(lines(python, .python, rule: "insecure-random"), [2])
        let noImport = "secret_key = random.choice(letters)\n"
        XCTAssertTrue(lines(noImport, .python, rule: "insecure-random").isEmpty)
        let go = "import \"math/rand\"\n\nfunc f() {\n\tsessionID := rand.Int63()\n}\n"
        XCTAssertEqual(lines(go, .go, rule: "insecure-random"), [4])
        let crypto = "import (\n\t\"crypto/rand\"\n\tmrand \"math/rand\"\n)\n\ntoken := rand.Read(b)\n"
        XCTAssertTrue(lines(crypto, .go, rule: "insecure-random").isEmpty)
    }

    func testSensitiveNamesSplitOnWordBoundaries() {
        XCTAssertTrue(InsecureRandomRule.isSensitive("requestId"))
        XCTAssertTrue(InsecureRandomRule.isSensitive("csrf_token"))
        XCTAssertTrue(InsecureRandomRule.isSensitive("apiKey"))
        XCTAssertFalse(InsecureRandomRule.isSensitive("width"))
        XCTAssertFalse(InsecureRandomRule.isSensitive("idle"))
        XCTAssertFalse(InsecureRandomRule.isSensitive("key"))
    }

    // MARK: hardcoded-ip

    func testFlagsHardcodedAddressesInStrings() {
        let source = """
            const host = "10.0.4.12";
            fetch("http://52.14.7.3:8080/api");
            DB_HOST = '192.168.1.20'
            """
        XCTAssertEqual(lines(source, .typescript, rule: "hardcoded-ip"), [1, 2, 3])
        XCTAssertEqual(lines("DB_HOST = '192.168.1.20'\n", .python, rule: "hardcoded-ip"), [1])
    }

    func testSkipsConventionalAddressesVersionsAndComments() {
        let source = """
            listen("127.0.0.1"); bind("0.0.0.0");
            const mask = "255.255.255.0"; const mdns = "224.0.0.251";
            const doc = "192.0.2.10"; const meta = "169.254.169.254";
            const version = "1.2.3.4";
            const ua = "Chrome/120.0.6099.71 Safari/1.2.3.4";
            const padded = "01.02.03.04";
            // see 10.0.0.1 for the old server
            const oid = "1.3.6.1.4.1";
            const n = 10.0;
            """
        XCTAssertTrue(lines(source, .typescript, rule: "hardcoded-ip").isEmpty)
    }

    func testSkipsHardcodedAddressesInTestsOtherFilesAndAllowedPrefixes() {
        let line = "host = \"10.1.2.3\"\n"
        XCTAssertTrue(lines(line, .python, rule: "hardcoded-ip", path: "/repo/tests/test_net.py").isEmpty)
        XCTAssertTrue(lines(line, .other("yaml"), rule: "hardcoded-ip").isEmpty)
        let parameters = RuleParameters(values: ["allow": .stringList(["10."])])
        let settings = ["hardcoded-ip": RuleSettings(enabled: true, severity: .warning, parameters: parameters)]
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.py"), language: .python, contents: line)
        XCTAssertTrue(HardcodedIPRule(profile: LanguageProfiles.profile(for: .python)).evaluate(file: file, context: context).isEmpty)
    }

    // MARK: inconsistent-indent

    func testFlagsABlockIndentedByADifferentWidth() {
        let source = """
            func a() {
                one()
            }
            func b() {
                two()
            }
            func c() {
              three()
            }
            """
        let found = findings(source, .swift, rule: "inconsistent-indent")
        XCTAssertEqual(found.map(\.line), [8])
        XCTAssertTrue(found.first?.message.contains("indents by 4") ?? false)
    }

    func testFlagsPythonAndShellBlocks() {
        let python = "def a():\n    x = 1\n\ndef b():\n    y = 2\n\ndef c():\n  z = 3\n"
        XCTAssertEqual(lines(python, .python, rule: "inconsistent-indent"), [8])
        let shell = "if a; then\n  b\nfi\nfor x in y; do\n  c\ndone\nif d; then\n    e\nfi\n"
        XCTAssertEqual(lines(shell, .bash, rule: "inconsistent-indent"), [8])
    }

    func testSkipsContinuationAlignmentStringsAndCommentsWhenMeasuringIndent() {
        let source = """
            func a(first: Int,
                   second: Int) {
                one()
            }
            if a,
               b {
                two()
            }
            let s = \"\"\"
              text {
                 more
              \"\"\"
            func c() {
                /*
                  comment {
                     body
                */
                three()
            }
            """
        XCTAssertTrue(lines(source, .swift, rule: "inconsistent-indent").isEmpty)
    }

    func testSkipsBlocksInsideOpenBracketsAndRawSwiftStrings() {
        let source = """
            func a() {
              one()
            }
            func b() {
              let x = items.compactMap({
                  $0
              })
            }
            func c() {
              let s = ###\"\"\"
                _ = #\"\"\"\"#
                {
                      inner
                \"\"\"###
              three()
            }
            """
        XCTAssertTrue(lines(source, .swift, rule: "inconsistent-indent").isEmpty)
    }

    func testSkipsGoTabsAndTooFewBlocks() {
        XCTAssertTrue(lines("func a() {\n\tb()\n}\nfunc c() {\n  d()\n}\n", .go, rule: "inconsistent-indent").isEmpty)
        XCTAssertTrue(lines("func a() {\n    b()\n}\nfunc c() {\n  d()\n}\n", .swift, rule: "inconsistent-indent").isEmpty)
        let template = "const a = () => {\n  b();\n};\nconst c = () => {\n  d();\n};\nconst t = `\n  x {\n      y\n`;\n"
        XCTAssertTrue(lines(template, .typescript, rule: "inconsistent-indent").isEmpty)
    }

    // MARK: duplicate-import

    func testFlagsDuplicateImportsPerLanguage() {
        XCTAssertEqual(lines("import Foundation\nimport os\n@testable import Foundation\n", .swift, rule: "duplicate-import"), [3])
        let script = "import { a } from 'lib';\nimport type { B } from 'lib';\nimport {\n  c,\n} from \"lib\";\n"
        XCTAssertEqual(lines(script, .typescript, rule: "duplicate-import"), [3])
        XCTAssertEqual(lines("import os\nfrom x import (\n    a,  # first\n    b,\n)\nfrom x import b\nimport os\n",
                             .python, rule: "duplicate-import"), [6, 7])
        XCTAssertEqual(lines("import (\n\t\"fmt\"\n\t\"os\"\n\t\"fmt\"\n)\n", .go, rule: "duplicate-import"), [4])
    }

    func testSkipsLegitimateRepeatedImports() {
        let swift = "#if canImport(Darwin)\nimport Foundation\n#else\nimport Foundation\n#endif\n"
        XCTAssertTrue(lines(swift, .swift, rule: "duplicate-import").isEmpty)
        let python = "import os\n\ndef f():\n    import os\n\ntry:\n    import json\nexcept ImportError:\n    import json\n"
        XCTAssertTrue(lines(python, .python, rule: "duplicate-import").isEmpty)
        let script = "import * as path from 'path';\nimport { join } from 'path';\nconst x = import('path');\n"
        XCTAssertTrue(lines(script, .javascript, rule: "duplicate-import").isEmpty)
        let docs = "let s = \"\"\"\nimport Foo\nimport Foo\n\"\"\"\n"
        XCTAssertTrue(lines(docs, .swift, rule: "duplicate-import").isEmpty)
    }

    // MARK: unsorted-imports

    func testUnsortedImportsIsOptIn() {
        XCTAssertTrue(lines("import b\nimport a\n", .python, rule: "unsorted-imports").isEmpty)
        XCTAssertEqual(lines("import b\nimport a\n", .python, rule: "unsorted-imports", enabling: true), [2])
    }

    func testFlagsTheFirstOutOfOrderImportPerGroup() {
        let swift = "import Foundation\n@testable import BouncerCore\nimport XCTest\n\nimport Zed\nimport Alpha\n"
        let found = findings(swift, .swift, rule: "unsorted-imports", enabling: true)
        XCTAssertEqual(found.map(\.line), [2, 6])
        XCTAssertEqual(found.first?.message, "Imports aren't sorted: 'BouncerCore' should come before 'Foundation'.")
    }

    func testAcceptsConventionalSortedGroups() {
        let swift = "import ArgumentParser\n@testable import BouncerCore\nimport Foundation\n"
        XCTAssertTrue(lines(swift, .swift, rule: "unsorted-imports", enabling: true).isEmpty)
        let script = """
            import fs from 'fs';
            import axios from 'axios';
            import React from 'react';
            import { util } from '@/lib/util';
            import { b } from '../b';
            import { a } from './a';
            import './styles.css';
            import { z } from './z';
            """
        XCTAssertTrue(lines(script, .typescript, rule: "unsorted-imports", enabling: true).isEmpty)
        let isort = "import os\nimport sys\nfrom abc import ABC\nfrom typing import Any\nfrom . import local\n"
        XCTAssertTrue(lines(isort, .python, rule: "unsorted-imports", enabling: true).isEmpty)
        let byModule = "from abc import ABC\nimport os\nfrom typing import Any\n"
        XCTAssertTrue(lines(byModule, .python, rule: "unsorted-imports", enabling: true).isEmpty)
        XCTAssertTrue(lines("import (\n\t\"os\"\n\t\"fmt\"\n)\n", .go, rule: "unsorted-imports", enabling: true).isEmpty)
    }

    func testFlagsUnsortedScriptAndPythonImports() {
        let script = "import { z } from 'zod';\nimport { a } from 'axios';\n"
        XCTAssertEqual(lines(script, .typescript, rule: "unsorted-imports", enabling: true), [2])
        let python = "import sys\nimport os\n"
        XCTAssertEqual(lines(python, .python, rule: "unsorted-imports", enabling: true), [2])
    }
}

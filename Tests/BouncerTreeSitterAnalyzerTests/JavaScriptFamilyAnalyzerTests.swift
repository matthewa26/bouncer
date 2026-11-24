import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class JavaScriptFamilyAnalyzerTests: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    private func findings(
        _ contents: String, file name: String = "a.ts", spec: TreeSitterLanguageSpec = .typescript,
        context: AnalysisContext? = nil
    ) throws -> [Finding] {
        let language = Language.from(fileExtension: URL(fileURLWithPath: name).pathExtension)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec).analyze(file: file, context: context ?? self.context)
    }

    private func undocumentedNames(_ found: [Finding]) -> Set<String> {
        Set(found.filter { $0.ruleID == "missing-documentation" }.compactMap { $0.message.split(separator: "\"").dropFirst().first.map(String.init) })
    }

    private func strict(_ ruleID: String, _ params: [String: RuleParameterValue]) -> AnalysisContext {
        let settings = RuleSettings(enabled: true, severity: .error, parameters: RuleParameters(values: params))
        return AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [ruleID: settings])
    }

    func testFlagsAnExportedFunctionWithNoJSDoc() throws {
        XCTAssertEqual(undocumentedNames(try findings("export function load() {}\n")), ["load"])
    }

    func testJSDocAboveAnExportedArrowFunctionDocumentsIt() throws {
        let contents = "/** Loads it. */\nexport const load = async () => {};\n"
        XCTAssertEqual(undocumentedNames(try findings(contents)), [])
    }

    func testAPlainLineCommentIsNotJSDoc() throws {
        XCTAssertEqual(undocumentedNames(try findings("// Loads it.\nexport function load() {}\n")), ["load"])
    }

    func testUnexportedFunctionsAreNotPublicByDefault() throws {
        XCTAssertEqual(undocumentedNames(try findings("function helper() {}\nconst other = () => {};\n")), [])
    }

    func testClassMemberVisibilityFollowsModifiers() throws {
        let contents = """
            /** A service. */
            export class Service {
              load() {}
              handler = () => {};
              private secret() {}
              protected guarded() {}
              #hidden() {}
            }
            """
        XCTAssertEqual(undocumentedNames(try findings(contents)), ["load", "handler"])
    }

    func testAnonymousCallbacksAreNeverFlaggedForDocumentation() throws {
        let all = strict("missing-documentation", ["scope": .string("all")])
        let contents = "/** Doubles. */\nexport function double(xs: number[]) { return xs.map((x) => x * 2); }\n"
        XCTAssertEqual(undocumentedNames(try findings(contents, context: all)), [])
    }

    func testMemberAssignmentNamesTheFunctionByItsLastComponent() throws {
        let all = strict("missing-documentation", ["scope": .string("all")])
        XCTAssertEqual(undocumentedNames(try findings("module.exports.load = function () {};\n", context: all)), ["load"])
    }

    func testFlagsSnakeCaseFunctionsAndLowercaseClasses() throws {
        let found = try findings("function load_user() {}\nclass service {}\nfunction Component() {}\n")
        let named = found.filter { $0.ruleID == "naming-convention" }.map(\.line)
        XCTAssertEqual(named, [1, 2])
    }

    func testLeavesObjectKeysHoldingFunctionsToTheirOwnContract() throws {
        let contents = """
            const routes = {
              "GET /users": () => 1,
              user_created: (id) => id,
              [Symbol.iterator]: () => 2,
              OnSave: function () {},
            };
            const load_user = () => 3;

            """
        let named = try findings(contents).filter { $0.ruleID == "naming-convention" }.map(\.line)
        XCTAssertEqual(named, [7])
    }

    func testNamesAFunctionByItsWholeObjectKey() throws {
        let all = strict("missing-documentation", ["scope": .string("all")])
        let contents = "const events = { \"user.created\": function () {}, 'on-save': () => {} };\n"
        XCTAssertEqual(undocumentedNames(try findings(contents, context: all)), ["user.created", "on-save"])
    }

    func testCountsTernariesAndLogicalOperatorsTowardComplexity() throws {
        let contents = "function f(a, b) { return a && b ? a : b ?? a; }\n"
        let found = try findings(contents, context: strict("cyclomatic-complexity", ["max": .int(3)]))
        XCTAssertTrue(found.contains { $0.ruleID == "cyclomatic-complexity" && $0.message.contains("complexity 4") })
    }

    func testCountsRequireCallsAsImports() throws {
        let contents = "import a from \"a\";\nconst b = require(\"b\");\n"
        let found = try findings(contents, context: strict("high-coupling", ["maxImports": .int(1)]))
        XCTAssertTrue(found.contains { $0.ruleID == "high-coupling" && $0.message.contains("imports 2") })
    }

    func testFlagsAnOverBranchedSwitchIgnoringDefault() throws {
        let contents = "function f(x) { switch (x) { case 1: break; case 2: break; default: break; } }\n"
        let found = try findings(contents, context: strict("switch-on-type-smell", ["maxBranches": .int(1)]))
        XCTAssertTrue(found.contains { $0.ruleID == "switch-on-type-smell" && $0.message.contains("2 branches") })
    }

    func testFlagsAGodClass() throws {
        let contents = "import a from \"a\";\nimport b from \"b\";\nclass Big { one() {} two() {} three() {} }\n"
        let params: [String: RuleParameterValue] = ["maxMembers": .int(2), "maxImportsForGodClass": .int(1)]
        XCTAssertTrue(try findings(contents, context: strict("god-class", params)).contains { $0.ruleID == "god-class" })
    }

    func testParsesTSXWithTheTSXGrammar() throws {
        let contents = "/** A button. */\nexport const Button = () => <button className=\"b\">Go</button>;\nexport function Card() { return <div />; }\n"
        XCTAssertEqual(undocumentedNames(try findings(contents, file: "a.tsx")), ["Card"])
    }

    func testParsesJSXWithTheJavaScriptGrammar() throws {
        let contents = "export function Card() { return <div className=\"c\" />; }\n"
        XCTAssertEqual(undocumentedNames(try findings(contents, file: "a.jsx", spec: .javascript)), ["Card"])
    }

    func testRecognizesModuleTypeScriptExtensions() {
        XCTAssertEqual(Language.from(fileExtension: "mts"), .typescript)
        XCTAssertEqual(Language.from(fileExtension: "cts"), .typescript)
    }
}

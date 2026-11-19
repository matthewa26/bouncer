import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class DesignSmellFindingsTests: XCTestCase {
    private func findings(
        _ types: [CollectedType], file name: String = "a.swift", language: Language = .swift,
        settings: [String: RuleSettings]
    ) -> [Finding] {
        let summary = DeclarationSummary(functions: [], types: types, switches: [], importCount: 0)
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: "")
        return DeclarationFindings.designSmellFindings(summary, file: file, context: context)
            + DeclarationFindings.godClass(summary, file: file, context: context)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    private func type(_ name: String, design: TypeDesign, structure: TypeStructure? = nil) -> CollectedType {
        CollectedType(name: name, memberCount: 1, startLine: 1, endLine: 2, structure: structure, design: design)
    }

    func testCouplingDropsEachLanguagesLibraryTypes() {
        let design = TypeDesign(referencedTypes: ["Promise", "Map", "Order", "Cart", "String"], methods: [], fields: [])
        let settings = setting("coupling-between-objects", ["max": .int(1)])
        XCTAssertEqual(findings([type("A", design: design)], file: "a.ts", language: .typescript, settings: settings)
            .map(\.message), ["Type \"A\" is coupled to 2 other types (CBO), over the 1 limit."])
        XCTAssertEqual(findings([type("A", design: design)], settings: settings).map(\.message),
                       ["Type \"A\" is coupled to 4 other types (CBO), over the 1 limit."])
    }

    func testForeignDataCountsDistinctMembersPerObject() {
        let methods = [
            MethodDesign(name: "a", line: 1, foreignData: ["order": ["total", "items"], "user": ["total"]]),
            MethodDesign(name: "b", line: 2, foreignData: ["order": ["total"]])
        ]
        XCTAssertEqual(TypeDesign(referencedTypes: [], methods: methods, fields: []).foreignDataAccesses, 3)
    }

    func testLanzaMarinescuFormulaNeedsAllThreeConditions() {
        let structure = TypeStructure(
            methods: [.init(name: "a", references: ["x"]), .init(name: "b", references: ["y"])],
            fieldNames: ["x", "y"], methodComplexities: [30, 20], isPlain: true
        )
        let foreign = (1...6).map { "m\($0)" }
        let design = TypeDesign(
            referencedTypes: [], methods: [MethodDesign(name: "a", line: 1, foreignData: ["o": Set(foreign)])], fields: []
        )
        let formula = setting("god-class", ["formula": .string("lanza-marinescu")])
        XCTAssertEqual(findings([type("Hub", design: design, structure: structure)], settings: formula).count, 1)
        let cohesive = setting("god-class", ["formula": .string("lanza-marinescu"), "minTCC": .double(0)])
        XCTAssertEqual(findings([type("Hub", design: design, structure: structure)], settings: cohesive), [])
        XCTAssertEqual(findings([type("HubTests", design: design, structure: structure)], settings: formula), [])
    }

    func testTemporaryFieldNeedsOneUserWhoseFirstUseIsATopLevelAssignment() {
        let field = FieldDeclaration(name: "tmp", line: 3, isTemporaryCandidate: true)
        let local = [FieldAccess(field: "tmp", kind: .assign, isTopLevel: true), FieldAccess(field: "tmp", kind: .read)]
        let nested = [FieldAccess(field: "tmp", kind: .assign), FieldAccess(field: "tmp", kind: .read)]
        let flagged = TypeDesign(referencedTypes: [], methods: [MethodDesign(name: "run", line: 4, fieldAccesses: local)],
                                 fields: [field])
        let conditional = TypeDesign(referencedTypes: [], methods: [MethodDesign(name: "run", line: 4, fieldAccesses: nested)],
                                     fields: [field])
        let shared = TypeDesign(referencedTypes: [], methods: [
            MethodDesign(name: "run", line: 4, fieldAccesses: local),
            MethodDesign(name: "init", line: 2, kind: .initializer, fieldAccesses: [FieldAccess(field: "tmp", kind: .read)])
        ], fields: [field])
        let settings = setting("temporary-field")
        XCTAssertEqual(findings([type("A", design: flagged)], settings: settings).count, 1)
        XCTAssertEqual(findings([type("A", design: conditional)], settings: settings), [])
        XCTAssertEqual(findings([type("A", design: shared)], settings: settings), [])
        XCTAssertEqual(findings([type("A", design: flagged)], file: "Tests/ATests.swift", settings: settings), [])
    }

    func testVocabularyNormalizesStateAndRecognizesGettersAndLibraryAccessors() {
        XCTAssertEqual(DesignVocabulary.stateName(of: "getBalance"), "balance")
        XCTAssertEqual(DesignVocabulary.stateName(of: "set_balance"), "balance")
        XCTAssertEqual(DesignVocabulary.stateName(of: "isOpen"), "open")
        XCTAssertEqual(DesignVocabulary.stateName(of: "settings"), "settings")
        XCTAssertTrue(DesignVocabulary.isForeignData("total", isCalled: false))
        XCTAssertTrue(DesignVocabulary.isForeignData("getTotal", isCalled: true))
        XCTAssertFalse(DesignVocabulary.isForeignData("compute", isCalled: true))
        XCTAssertFalse(DesignVocabulary.isForeignData("count", isCalled: false))
        XCTAssertTrue(DesignVocabulary.isLibraryType("Promise", in: .typescript))
        XCTAssertTrue(DesignVocabulary.isLibraryType("KeyError", in: .python))
        XCTAssertFalse(DesignVocabulary.isLibraryType("Order", in: .swift))
    }
}

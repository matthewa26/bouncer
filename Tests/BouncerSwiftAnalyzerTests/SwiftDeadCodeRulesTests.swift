import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftDeadCodeRulesTests: XCTestCase {
    private let parameterOn = ["unused-parameter": RuleSettings(enabled: true, severity: .warning, parameters: .empty)]

    private func messages(
        of ruleID: String, in contents: String, settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: contents)
        return try SwiftSyntaxAnalyzer().analyze(file: file, context: context)
            .filter { $0.ruleID == ruleID }.map { "\($0.line): \($0.message)" }
    }

    // MARK: unused-private-symbol

    func testFlagsUnusedPrivateFunctionsPropertiesAndTypes() throws {
        let contents = """
            struct Box {
                private let unusedField = 1
                private let usedField = 2
                private func helper() {}
                private func recursive() { recursive() }
                func run() -> Int { usedField }
            }
            private struct Orphan {}
            fileprivate enum Used { case a }
            let x: Used = .a
            private typealias Alias = Int
            """
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: contents), [
            "2: Private property \"unusedField\" is never used in this file.",
            "4: Private function \"helper\" is never used in this file.",
            "5: Private function \"recursive\" is never used in this file.",
            "8: Private type \"Orphan\" is never used in this file.",
            "11: Private type alias \"Alias\" is never used in this file."
        ])
    }

    func testCountsMemberAccessKeyPathsSelectorsAndShorthandBindingsAsUses() throws {
        let contents = """
            final class Model {
                private static let shared = 1
                private var name: String? { nil }
                private func tapped() {}
                private var count: Int { 0 }
                private var flag: Bool? { nil }
                func go() {
                    _ = Model.shared
                    _ = \\Model.name
                    _ = #selector(tapped)
                    _ = "\\(self.count)"
                    if let flag { print(flag) }
                }
            }
            """
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: contents), [])
    }

    func testPrivateExtensionMembersArePrivateUnlessMarkedOtherwise() throws {
        let contents = """
            struct S {}
            private extension S {
                func hidden() {}
                internal func shown() {}
            }
            """
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: contents), [
            "3: Private function \"hidden\" is never used in this file."
        ])
    }

    func testSkipsLikelyWitnessesOverridesRuntimeHooksAndWrappers() throws {
        let contents = """
            import UIKit
            struct Item: Codable {
                private enum CodingKeys: String, CodingKey { case id }
                private func witness() {}
            }
            struct Later {}
            extension Later: Equatable { }
            extension Later { private func maybeWitness() {} }
            class View: UIView {
                @IBOutlet private var label: UILabel!
                @objc private func tap() {}
                @IBAction private func press(_ sender: Any) {}
                override private func layoutSubviews() {}
                private let observer = NSObject()
                @State private var wrapped = 0
                private func _reserved() {}
                private static func == (a: View, b: View) -> Bool { true }
            }
            @resultBuilder enum Builder { private static func buildBlock(_ parts: Int...) -> Int { 0 } }
            private(set) var readable = 0
            """
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: contents), [])
    }

    // MARK: unused-parameter

    func testUnusedParameterIsOffUnlessConfigured() throws {
        let contents = "func f(a: Int) -> Int { 1 }\n"
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents), [])
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents, settings: parameterOn), [
            "1: Parameter \"a\" of \"f\" is never used in its body."
        ])
    }

    func testFlagsUnusedParametersByInternalName() throws {
        let contents = """
            func f(label value: Int, other: Int, _ _skipped: Int, _: Int) -> Int { other }
            struct S {
                init(seed: Int, used: Int) { print(used) }
                func g(closure: Int) { _ = { [closure] in closure } }
                func h(optional: Int?) { if let optional { print(optional) } }
            }
            """
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents, settings: parameterOn), [
            "1: Parameter \"value\" of \"f\" is never used in its body.",
            "3: Parameter \"seed\" of \"init\" is never used in its body."
        ])
    }

    func testSkipsStubsOverridesConformancesAndProtocolExtensions() throws {
        let contents = """
            protocol P { func p(x: Int) }
            extension P { func p(x: Int) {} }
            func stub(a: Int) { fatalError("no") }
            func thrower(a: Int) throws { throw E.bad }
            func empty(a: Int) {}
            class Base { func m(a: Int) -> Int { a } }
            class Sub: Base { override func m(a: Int) -> Int { 1 } }
            struct Conforms: P { func p(x: Int) { print(1) } }
            struct Later {}
            extension Later: CustomStringConvertible { var description: String { "" } }
            extension Later { func witness(of value: Int) { print(1) } }
            final class Target { @objc func tapped(sender: Any) { print(1) } }
            enum E: Error { case bad }
            """
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents, settings: parameterOn), [])
    }
}

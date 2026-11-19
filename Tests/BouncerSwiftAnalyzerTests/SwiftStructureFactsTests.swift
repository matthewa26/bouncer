import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftStructureFactsTests: XCTestCase {
    private func structure(_ contents: String) throws -> StructureFacts {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/Sources/A/a.swift"), language: .swift, contents: contents)
        return try XCTUnwrap(SwiftSyntaxAnalyzer().moduleFacts(file: file)).structure
    }

    func testRecordsTypesWithSupertypesFieldsAndMethods() throws {
        let contents = """
            protocol Shape: AnyObject { func area() -> Double }
            class Base: NSObject, Shape {
                static var shared = Base()
                let id: Int
                var name: String = "" { didSet {} }
                var computed: Int { 1 }
                var inferred = [String: Int]()
                func area() -> Double { 0 }
                func render() { draw() }
            }
            final class Square: Base {
                override func area() -> Double { fatalError("unsupported") }
                override func render() {}
                override func layout() throws { throw Failure.no }
                func extra() {}
            }
            struct Point { var x: Double; var y: Double }
            enum Kind { case a }
            extension Point: Equatable, Swift.Hashable {}
            extension Point { func moved() {} }
            actor Cache {}
            """
        let facts = try structure(contents)
        XCTAssertEqual(facts.types.map(\.name), ["Shape", "Base", "Square", "Point", "Kind", "Point", "Cache"])
        XCTAssertEqual(facts.types.map(\.kind), [.protocol, .class, .class, .struct, .enum, .extension, .other])
        let base = facts.types[1], square = facts.types[2]
        XCTAssertEqual(base.supertypes, ["NSObject", "Shape"])
        XCTAssertEqual(base.fields, ["id:Int", "name:String", "inferred"])
        XCTAssertEqual(base.methods, ["area", "render"])
        XCTAssertEqual(base.refused, [])
        XCTAssertEqual(square.refused, ["area", "layout"])
        XCTAssertEqual(square.empty, ["render"])
        XCTAssertEqual(facts.types[3].fields, ["x:Double", "y:Double"])
        XCTAssertEqual(facts.types[3].methods, [])
        XCTAssertEqual(facts.types[5].supertypes, ["Equatable", "Hashable"])
    }

    func testRecordsFunctionsInitializersAndSwitchSubjects() throws {
        let contents = """
            struct Parser {
                init(text: String, _ offset: Int, at index: Int) {}
                func parse(node: Node) -> Int {
                    switch node.kind { default: break }
                    switch self.kind { default: break }
                    switch self { default: break }
                    switch (a, b) { default: break }
                    return 0
                }
            }
            extension Parser { init() {} }
            func free(lhs: [String: Int], rhs: inout Int) {}
            """
        let facts = try structure(contents)
        let functions = facts.functions.map { "\($0.name)(\($0.parameters.joined(separator: ",")))" }
        XCTAssertEqual(functions, [
            "Parser.init(text:String,offset:Int,index:Int)", "parse(node:Node)", "Parser.init()",
            "free(lhs:[String:Int],rhs:Int)"
        ])
        XCTAssertEqual(facts.switches.map(\.subject), ["node.kind", "kind"])
        XCTAssertEqual(facts.switches.map(\.line), [4, 5])
    }

    func testCacheRoundTripLeavesOutEmptyLists() throws {
        let facts = try XCTUnwrap(SwiftSyntaxAnalyzer().moduleFacts(file: SourceFile(
            path: URL(fileURLWithPath: "/repo/a.swift"), language: .swift, contents: "struct A {}\nfunc f() {}\n"
        )))
        let data = try JSONEncoder().encode(facts)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("supertypes"))
        XCTAssertFalse(json.contains("switches"))
        XCTAssertEqual(try JSONDecoder().decode(ModuleFacts.self, from: data), facts)
    }
}

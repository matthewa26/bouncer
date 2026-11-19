import XCTest
import Foundation
import BouncerCore
@testable import BouncerSwiftAnalyzer

final class SwiftModuleFactsTests: XCTestCase {
    private func facts(_ contents: String) throws -> ModuleFacts {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/Sources/A/a.swift"), language: .swift, contents: contents)
        return try XCTUnwrap(SwiftSyntaxAnalyzer().moduleFacts(file: file))
    }

    func testRecordsPublicDeclarationsAndSkipsWhatOutsideCodeCalls() throws {
        let contents = """
            import Foundation
            public struct Store {
                public var items: [String] = []
                var hidden = 0
                public func load() {}
                public static func + (a: Store, b: Store) -> Store { a }
            }
            open class Base { open func render() {} }
            final class Sub: Base { public override func render() {} }
            public protocol Shape { func area() -> Double }
            public extension Store { func count() -> Int { 0 }; private func secret() {} }
            @objc public class Bridge: NSObject {}
            @main public struct App { public static func main() {} }
            """
        let names = try facts(contents).exports.map(\.name)
        XCTAssertEqual(names, ["Store", "items", "load", "Base", "render", "Shape", "count"])
    }

    func testRecordsReferencedNamesAndImports() throws {
        let module = try facts("import BouncerCore\nlet x: Finding? = nil\nlet y = Store().load()\n")
        XCTAssertEqual(module.imports.map(\.specifier), ["BouncerCore"])
        XCTAssertTrue(Set(module.references).isSuperset(of: ["Finding", "Store", "load"]))
    }
}

import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class StructureFactsTests: XCTestCase {
    private func structure(_ contents: String, spec: TreeSitterLanguageSpec, ext: String) throws -> StructureFacts {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/src/a.\(ext)"), language: spec.coreLanguage, contents: contents)
        return try XCTUnwrap(TreeSitterAnalyzer(spec: spec).moduleFacts(file: file)).structure
    }

    func testTypeScriptTypesFunctionsAndSwitches() throws {
        let contents = """
            interface Shape extends Base<number>, Other { area: number; name?: string; draw(): void }
            abstract class Animal { abstract speak(): void; move(meters: number) { this.go(meters) } }
            class Dog extends Animal implements Pet, ns.Walker {
              static count = 0
              name: string
              private legs = 4
              constructor(name: string, owner: Person) { super(); this.name = name }
              speak() { throw new Error("not supported") }
              wag() {}
              bark() { // nothing
              }
            }
            enum Color { Red }
            export function fetchUser(id: string, opts = {}, ...rest: any[]) {
              switch (action.type) { case "a": break }
              switch (this.kind) {}
            }
            const loadUser = async (id: string, { a }: X) => id
            """
        let facts = try structure(contents, spec: .typescript, ext: "ts")
        let shape = try XCTUnwrap(facts.types.first { $0.name == "Shape" })
        XCTAssertEqual(shape.kind, .interface)
        XCTAssertEqual(shape.supertypes, ["Base", "Other"])
        XCTAssertEqual(shape.fields, ["area:number", "name:string"])
        XCTAssertEqual(facts.types.first { $0.name == "Animal" }?.kind, .abstractClass)
        let dog = try XCTUnwrap(facts.types.first { $0.name == "Dog" })
        XCTAssertEqual(dog.kind, .class)
        XCTAssertEqual(dog.supertypes, ["Animal", "Pet", "Walker"])
        XCTAssertEqual(dog.fields, ["name:string", "legs"])
        XCTAssertEqual(dog.methods, ["speak", "wag", "bark"])
        XCTAssertEqual(dog.refused, ["speak"])
        XCTAssertEqual(dog.empty, ["wag", "bark"])
        XCTAssertEqual(facts.types.first { $0.name == "Color" }?.kind, .enum)
        let functions = facts.functions.map { "\($0.name)(\($0.parameters.joined(separator: ",")))" }
        XCTAssertEqual(functions, [
            "move(meters:number)", "Dog.init(name:string,owner:Person)", "speak()", "wag()", "bark()",
            "fetchUser(id:string,opts)", "loadUser(id:string)"
        ])
        XCTAssertEqual(facts.switches.map(\.subject), ["action.type", "kind"])
    }

    func testJavaScriptClassHeritage() throws {
        let facts = try structure("class A extends B { m() { throw 1 } }\n", spec: .javascript, ext: "js")
        XCTAssertEqual(facts.types.first?.supertypes, ["B"])
        XCTAssertEqual(facts.types.first?.refused, ["m"])
    }

    func testPythonClassesAndFunctions() throws {
        let contents = """
            from abc import ABC, abstractmethod
            from typing import Protocol

            class Readable(Protocol):
                def read(self) -> str: ...

            class Base(ABC):
                @abstractmethod
                def run(self): pass

            class Point(Base, metaclass=Meta):
                x: int
                y: float = 0.0
                def __init__(self, x: int, y: float = 0.0, *args, **kwargs):
                    self.x = x
                def run(self):
                    \"\"\"Doc.\"\"\"
                    raise NotImplementedError
                def stop(self):
                    pass

            def handle(event, kind: str):
                match event.kind:
                    case "a": pass
                match a, b:
                    case _: pass
            """
        let facts = try structure(contents, spec: .python, ext: "py")
        XCTAssertEqual(facts.types.map(\.kind), [.protocol, .abstractClass, .class])
        let point = try XCTUnwrap(facts.types.last)
        XCTAssertEqual(point.supertypes, ["Base"])
        XCTAssertEqual(point.fields, ["x:int", "y:float"])
        XCTAssertEqual(point.methods, ["run", "stop"])
        XCTAssertEqual(point.refused, ["run"])
        XCTAssertEqual(point.empty, ["stop"])
        let functions = facts.functions.map { "\($0.name)(\($0.parameters.joined(separator: ",")))" }
        XCTAssertEqual(functions, [
            "read()", "run()", "Point.init(x:int,y:float)", "run()", "stop()", "handle(event,kind:str)"
        ])
        XCTAssertEqual(facts.switches.map(\.subject), ["event.kind"])
    }

    func testGoTypesFunctionsAndSwitches() throws {
        let contents = """
            package p

            type Server struct {
                Name, Host string
                Port int
                http.Handler
            }
            type Store interface { Get(id string) string }
            type Kind int

            func (s *Server) Get(id string, n, m int) string {
                switch s.Kind {
                }
                switch v := x.(type) {
                }
                switch {
                }
                return ""
            }
            """
        let facts = try structure(contents, spec: .go, ext: "go")
        XCTAssertEqual(facts.types.map(\.kind), [.struct, .interface, .other])
        XCTAssertEqual(facts.types.first?.fields, ["Name:string", "Host:string", "Port:int"])
        XCTAssertEqual(facts.functions.map(\.name), ["Get"])
        XCTAssertEqual(facts.functions.first?.parameters, ["id:string", "n:int", "m:int"])
        XCTAssertEqual(facts.switches.map(\.subject), ["s.Kind", "x.(type)"])
    }
}

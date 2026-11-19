import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class DesignFactsTests: XCTestCase {
    private func structure(_ contents: String, spec: TreeSitterLanguageSpec, ext: String) throws -> StructureFacts {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/src/a.\(ext)"), language: spec.coreLanguage, contents: contents)
        return try XCTUnwrap(TreeSitterAnalyzer(spec: spec).moduleFacts(file: file)).structure
    }

    func testTypeScriptRequirementsPreconditionsOwnersAndCollaborations() throws {
        let contents = """
            interface Repo { find(id: string): User; save(user: User): void; size: number }
            class Square extends Shape {
              private repo = new SqlRepo();
              private clock: Clock;
              constructor(private api: ApiClient, readonly name: string) { super(); this.cache = new Cache(); }
              area(scale: number): number {
                if (scale < 0) { throw new RangeError("negative"); }
                return scale * scale;
              }
              check(): void {
                if (this.closed) throw new Error("closed");
                this.run();
              }
              total(order: Order): number {
                const temp = new Formatter();
                return order.total + this.clock.now + this.api.base + temp.width + order.tax;
              }
            }
            function free(a: number): string { return ""; }
            """
        let facts = try structure(contents, spec: .typescript, ext: "ts")
        XCTAssertEqual(facts.types.first?.methods, ["find", "save"])
        let square = try XCTUnwrap(facts.types.first { $0.name == "Square" })
        XCTAssertEqual(square.guarded, ["area"])
        let owners = facts.functions.map { "\($0.owner ?? "-").\($0.name)->\($0.returns ?? "-")" }
        XCTAssertEqual(owners, ["Square.Square.init->-", "Square.area->number", "Square.check->void", "Square.total->number",
                                "-.free->string"])
        let collaboration = try XCTUnwrap(facts.collaborations.first)
        XCTAssertEqual(collaboration.owner, "Square")
        XCTAssertEqual(collaboration.constructs, ["Cache", "SqlRepo"])
        XCTAssertEqual(collaboration.uses, ["ApiClient.base", "Clock.now", "Formatter.width", "Order.tax", "Order.total"])
    }

    func testPythonPreconditionsOwnersAndCollaborations() throws {
        let contents = """
            class PostalScale(Scale):
                def __init__(self, client: "HttpClient"):
                    self.carrier = Courier()
                    self.client = client
                    self._log = []

                def weigh(self, grams: int) -> float:
                    \"\"\"Weighs.\"\"\"
                    if grams > 30000:
                        raise ValueError("too heavy")
                    return grams / 1000

                def tare(self):
                    assert self.ready
                    return 0

                def _check(self, grams):
                    if grams < 0:
                        raise ValueError()
                    return grams

                def ship(self, parcel: Parcel):
                    temp = Label()
                    parcel._status = "shipped"
                    return self.client.post(parcel.code) + self.carrier.rate + temp.text

                @staticmethod
                def unit(name: str) -> str:
                    return name
            """
        let facts = try structure(contents, spec: .python, ext: "py")
        let scale = try XCTUnwrap(facts.types.first)
        XCTAssertEqual(scale.guarded, ["weigh"])
        XCTAssertEqual(facts.functions.map { "\($0.owner ?? "-").\($0.name)->\($0.returns ?? "-")" }, [
            "PostalScale.PostalScale.init->-", "PostalScale.weigh->float", "PostalScale.tare->-",
            "PostalScale._check->-", "PostalScale.ship->-", "-.unit->str"
        ])
        let collaboration = try XCTUnwrap(facts.collaborations.first)
        XCTAssertEqual(collaboration.constructs, ["Courier"])
        XCTAssertEqual(collaboration.uses, ["Courier.rate", "HttpClient.post", "Label.text", "Parcel._status", "Parcel.code"])
    }

    func testGoMethodsNameTheirReceiverType() throws {
        let contents = """
            package store
            func (s *Store) Get(key string) (string, error) { return "", nil }
            func (s Store) Len() int { return 0 }
            func New() *Store { return nil }
            """
        let facts = try structure(contents, spec: .go, ext: "go")
        XCTAssertEqual(facts.functions.map { "\($0.owner ?? "-").\($0.name)->\($0.returns ?? "-")" },
                       ["Store.Get->(string,error)", "Store.Len->int", "-.New->*Store"])
    }
}

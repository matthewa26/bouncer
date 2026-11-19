import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class DesignSmellTests: XCTestCase {
    private func messages(
        of ruleID: String, in contents: String, file: String = "a.ts", settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let language = Language.from(fileExtension: URL(fileURLWithPath: file).pathExtension)
        let spec: TreeSitterLanguageSpec = [.python: .python, .go: .go, .javascript: .javascript][language] ?? .typescript
        let source = SourceFile(path: URL(fileURLWithPath: "/repo/\(file)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec).analyze(file: source, context: context)
            .filter { $0.ruleID == ruleID }.map(\.message)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    // MARK: coupling-between-objects and response-for-class

    func testCouplingAndResponseAcrossLanguages() throws {
        let typescript = """
            class Checkout<T> extends Base implements Payable {
              private cart: Cart;
              run(item: T): Promise<Receipt> {
                const rate = TaxTable.rate;
                this.log(rate);
                return new Receipt(Money.zero(), this.cart.total());
              }
              log(x: number): void { console.log(x); }
            }
            """
        let python = """
            class Checkout(Base):
                def run(self, item: Item) -> Optional[Receipt]:
                    rate = TaxTable.rate
                    return Receipt(MAX_RATE, rate)
            """
        let cbo = setting("coupling-between-objects", ["max": .int(1)])
        XCTAssertEqual(try messages(of: "coupling-between-objects", in: typescript), [])
        XCTAssertEqual(try messages(of: "coupling-between-objects", in: typescript, settings: cbo),
                       ["Type \"Checkout\" is coupled to 6 other types (CBO), over the 1 limit."])
        XCTAssertEqual(try messages(of: "coupling-between-objects", in: python, file: "a.py", settings: cbo),
                       ["Type \"Checkout\" is coupled to 4 other types (CBO), over the 1 limit."])
        XCTAssertEqual(try messages(of: "response-for-class", in: typescript, settings: setting("response-for-class", ["max": .int(3)])),
                       ["Type \"Checkout\" has response for a class (RFC) 4: 2 methods plus 2 distinct methods they call, "
                        + "over the 3 limit."])
    }

    // MARK: god-class formula

    func testLanzaMarinescuFormulaInPython() throws {
        let branches = (1...12).map { "        if v > \($0):\n            v += 1" }.joined(separator: "\n")
        let methods = (1...4).map { "    def m\($0)(self, o):\n        v = o.a\($0) + o.b\($0) + self.f\($0)\n\(branches)\n        return v" }
        let contents = "class Hub:\n" + methods.joined(separator: "\n") + "\n"
        let formula = setting("god-class", ["formula": .string("lanza-marinescu")])
        XCTAssertEqual(try messages(of: "god-class", in: contents, file: "a.py", settings: formula), [
            "Type \"Hub\" is a god class by the Lanza–Marinescu formula: WMC 52 (at least 47), ATFD 8 (at least 6), "
                + "and TCC 0.0% (under 33.3%)."
        ])
    }

    // MARK: feature-envy

    func testFeatureEnvyInTypeScriptAndPython() throws {
        let typescript = """
            class Printer {
              private header = "";
              summary(order: Order): string {
                return this.header + order.total + order.discount + order.shipping + order.items + order.customer;
              }
              copy(order: Order) {
                return new Receipt(order.total, order.discount, order.shipping, order.items, order.customer);
              }
              fromOrder(order: Order) { return order.total + order.discount + order.shipping + order.items + order.customer; }
            }
            """
        let python = """
            class Printer:
                def summary(self, order):
                    return order.total + order.discount + order.shipping + order.items + order.get_customer()
                def run(self, options):
                    return options.a + options.b + options.c + options.d + options.e
                def configure(self, process):
                    process.a = 1
                    process.b = 2
                    process.c = 3
                    process.d = 4
                    process.e = 5
            """
        let settings = setting("feature-envy")
        XCTAssertEqual(try messages(of: "feature-envy", in: typescript), [])
        XCTAssertEqual(try messages(of: "feature-envy", in: typescript, settings: settings), [
            "Method \"summary\" uses 5 members of \"order\" but 1 of its own type (feature envy); move it to "
                + "\"order\"'s type."
        ])
        XCTAssertEqual(try messages(of: "feature-envy", in: python, file: "a.py", settings: settings), [
            "Method \"summary\" uses 5 members of \"order\" but 0 of its own type (feature envy); move it to "
                + "\"order\"'s type."
        ])
    }

    // MARK: temporary-field

    func testTemporaryFieldInTypeScriptJavaScriptAndPython() throws {
        let typescript = """
            class Parser {
              private tokens: string[] = [];
              private scratch?: string[];
              shared?: number;
              words(): number {
                this.scratch = this.tokens.filter((t) => t.length > 0);
                return this.scratch.length;
              }
              other(): void { this.shared = 1; console.log(this.shared); }
            }
            """
        let python = """
            class Reader:
                def __init__(self):
                    self.ready = False
                def init(self, f):
                    self._size = f.read()
                    if self._size < 24:
                        raise ValueError()
                def cached(self):
                    if self._memo is None:
                        self._memo = 1
                    return self._memo

            class Child(Reader):
                def run(self):
                    self._tmp = 1
                    return self._tmp
            """
        XCTAssertEqual(try messages(of: "temporary-field", in: typescript), [
            "Field \"scratch\" of \"Parser\" is set and read only inside \"words\" (temporary field); "
                + "make it a local variable there."
        ])
        XCTAssertEqual(try messages(of: "temporary-field", in: python, file: "a.py"), [
            "Field \"_size\" of \"Reader\" is set and read only inside \"init\" (temporary field); "
                + "make it a local variable there."
        ])
        let javascript = "class A {\n  #tmp;\n  run() {\n    this.#tmp = 1;\n    return this.#tmp;\n  }\n}\n"
        XCTAssertEqual(try messages(of: "temporary-field", in: javascript, file: "a.js").count, 1)
    }

    // MARK: command-query-separation

    func testCommandQuerySeparationInTypeScriptAndPython() throws {
        let typescript = """
            class Cursor {
              private index = 0;
              private cache?: number[];
              resetTo(position: number): boolean { this.index = position; return this.index > 0; }
              next(): number { this.index++; return this.index; }
              rewind(): this { this.index = 0; return this; }
              clear(): void { this.index = 0; return; }
              store(x: number): boolean { this.index = x; return true; }
              values(): number[] { if (!this.cache) { this.cache = [this.index]; } return this.cache; }
              override toString(): string { this.index = 1; return ""; }
            }
            """
        let python = """
            class Cursor:
                def reset_to(self, position):
                    self.index = position
                    return self.index > 0
                def rewind(self):
                    self.index = 0
                    return self
                def metadata(self):
                    if not hasattr(self, "_metadata"):
                        self._metadata = load(self.index)
                    return self._metadata
                def __enter__(self):
                    self.open = True
                    return self.index
            """
        let settings = setting("command-query-separation")
        XCTAssertEqual(try messages(of: "command-query-separation", in: typescript), [])
        XCTAssertEqual(try messages(of: "command-query-separation", in: typescript, settings: settings), [
            "Method \"resetTo\" both changes \"index\" and returns a value (command–query separation); "
                + "split it into a command and a query."
        ])
        XCTAssertEqual(try messages(of: "command-query-separation", in: python, file: "a.py", settings: settings), [
            "Method \"reset_to\" both changes \"index\" and returns a value (command–query separation); "
                + "split it into a command and a query."
        ])
    }

    // MARK: tell-dont-ask

    func testTellDontAskAcrossLanguages() throws {
        let typescript = """
            function withdraw(amount: number, account: Account) {
              if (account.balance >= amount) { account.balance -= amount; }
              if (account.isOpen) { account.setBalance(0); }
              const local = new Account();
              if (local.balance > 0) { local.balance = 0; }
              items.forEach((item) => { if (item.done) { item.done = false; } });
            }
            """
        let python = """
            def withdraw(amount, account):
                if account.balance >= amount:
                    account.balance -= amount
                if not account.get_limit():
                    account.set_limit(10)
                local = Account()
                if local.balance > 0:
                    local.balance = 0
            """
        let go = """
            package p
            func (a *Account) Withdraw(amount int, other *Account) {
            \tif a.balance >= amount { a.balance -= amount }
            \tif other.balance >= amount { other.balance -= amount }
            }
            """
        let settings = setting("tell-dont-ask")
        XCTAssertEqual(try messages(of: "tell-dont-ask", in: typescript), [])
        XCTAssertEqual(try messages(of: "tell-dont-ask", in: typescript, settings: settings).count, 1)
        XCTAssertEqual(try messages(of: "tell-dont-ask", in: python, file: "a.py", settings: settings).count, 2)
        XCTAssertEqual(try messages(of: "tell-dont-ask", in: go, file: "a.go", settings: settings).count, 1)
    }

    // MARK: primitive-obsession

    func testPrimitiveObsessionAcrossLanguages() throws {
        let typescript = """
            class Bank {
              private accountId: string;
              transfer(fromId: string, toId: string, amount: number, currency: string): void {}
              open(email: string, limit = 3, note?: string): void {}
              constructor(a: string, b: string, c: number, d: number) {}
            }
            """
        let python = "def transfer(from_id: str, to_id: str, amount: float, currency: str, retries: int = 3):\n    pass\n"
        let go = "package p\nfunc Transfer(fromID, toID string, amount, fee int64) {}\nfunc Open(name string) {}\n"
        let settings = setting("primitive-obsession")
        XCTAssertEqual(try messages(of: "primitive-obsession", in: typescript), [])
        XCTAssertEqual(try messages(of: "primitive-obsession", in: typescript, settings: settings), [
            "Function \"transfer\" takes 4 string or number parameters (primitive obsession); group related ones into a type.",
            "Function \"open\" takes \"email\": string as plain primitives (primitive obsession); give it a domain type.",
            "Field \"accountId\" is a plain string (primitive obsession); give it a domain type."
        ])
        XCTAssertEqual(try messages(of: "primitive-obsession", in: python, file: "a.py", settings: settings), [
            "Function \"transfer\" takes 4 string or number parameters (primitive obsession); group related ones into a type."
        ])
        XCTAssertEqual(try messages(of: "primitive-obsession", in: go, file: "a.go", settings: settings), [
            "Function \"Transfer\" takes 4 string or number parameters (primitive obsession); group related ones into a type."
        ])
    }
}

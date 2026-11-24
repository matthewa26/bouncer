import XCTest
import BouncerCore
@testable import BouncerReporting

final class QuickFixDebugOutputTests: XCTestCase {
    private func removal(_ line: Int, of lines: [String]) -> QuickFix {
        QuickFix(startLine: line, removed: [lines[line - 1]], added: [])
    }

    // MARK: Statement removal

    func testDeletesAWholeDebugStatementInEachLanguage() {
        let cases: [(rule: String, file: String, line: Int, lines: [String])] = [
            ("js-console-log", "a.ts", 2, ["const order = create();", "console.log(\"order\", order);", "save(order);"]),
            ("js-console-log", "a.js", 2, ["{", "  debugger;", "}"]),
            ("python-debug-print", "a.py", 3, ["def load(id):", "    user = get(id)", "    print(user)", "    return user"]),
            ("swift-debug-print", "a.swift", 2, ["func load() {", "    print(\"Loaded \\(count)\")", "}"]),
            ("php-debug-output", "a.php", 3, ["<?php", "$order = find($id);", "var_dump($order);", "save($order);"]),
            ("php-debug-output", "a.php", 2, ["<?php", "\\dd($order); // remove", "save($order);"]),
            ("java-system-out", "A.java", 2, ["save(order);", "    System.out.println(\"Saved \" + order);", "}"]),
            ("rust-debug-print", "src/a.rs", 2, ["fn f() {", "    println!(\"{}\", total);", "}"])
        ]
        for (rule, file, line, lines) in cases {
            XCTAssertEqual(quickFix(rule, at: line, in: lines, file: file), removal(line, of: lines), rule)
        }
    }

    func testLeavesALineThatIsMoreThanTheCall() {
        XCTAssertNil(quickFix("js-console-log", at: 1, in: ["promise.then((x) => console.log(x));"]))
        XCTAssertNil(quickFix("js-console-log", at: 1, in: ["console.log(a); save(a);"]))
        XCTAssertNil(quickFix("python-debug-print", at: 1, in: ["print(user) if debug else None"], file: "a.py"))
        XCTAssertNil(quickFix("swift-debug-print", at: 1, in: ["let x = 1"], file: "a.swift"), "Changed since")
        XCTAssertNil(quickFix("php-debug-output", at: 2, in: ["<?php", "var_dump($order)"], file: "a.php"), "No ;")
        XCTAssertNil(quickFix("java-system-out", at: 1, in: ["log(System.out.println(\"x\"));"], file: "A.java"))
    }

    func testLeavesAMultiLineStatement() {
        XCTAssertNil(quickFix("js-console-log", at: 1, in: ["console.log(\"order\",", "  order);"]))
        XCTAssertNil(quickFix("python-debug-print", at: 1, in: ["print(\"\"\"", "text", "\"\"\")"], file: "a.py"))
        XCTAssertNil(quickFix("java-system-out", at: 1, in: ["System.out.println(\"a\"", "    + b);"], file: "A.java"))
    }

    func testLeavesAStatementWhoseRemovalChangesTheCodeAroundIt() {
        XCTAssertNil(quickFix("js-console-log", at: 2, in: ["if (debug)", "  console.log(state);", "run();"]),
                     "Unbraced if body")
        XCTAssertNil(quickFix("js-console-log", at: 2, in: ["} else", "  console.log(state);"]), "Unbraced else")
        XCTAssertNil(quickFix("js-console-log", at: 2, in: ["const f = (x) =>", "  console.log(x);"]), "Arrow body")
        XCTAssertNil(quickFix("python-debug-print", at: 2, in: ["if debug:", "    print(state)", "else:", "    run()"],
                              file: "a.py"), "Only statement in its block")
        XCTAssertNil(quickFix("swift-debug-print", at: 3,
                              in: ["switch x {", "case .a:", "    print(x)", "case .b:", "    run()", "}"],
                              file: "a.swift"), "Only statement in its case")
        XCTAssertNil(quickFix("js-console-log", at: 1, in: ["console.log(x)", "  .valueOf();"]), "Continues")
    }

    func testKeepsASiblingStatementAfterAColon() {
        let lines = ["if debug:", "    print(state)", "    dump(state)"]
        XCTAssertEqual(quickFix("python-debug-print", at: 2, in: lines, file: "a.py"), removal(2, of: lines))
    }

    func testIgnoresOtherLanguages() {
        XCTAssertNil(quickFix("python-debug-print", at: 1, in: ["print(x)"], file: "a.ts"))
        XCTAssertNil(quickFix("swift-debug-print", at: 1, in: ["print(x)"], file: "a.py"))
    }

    // MARK: Go

    func testGoPrintIsDeletedWhenEverythingStillCompiles() {
        let lines = ["package main", "", "import \"fmt\"", "", "func load(id string) User {", "\tuser := find(id)",
                     "\tfmt.Println(\"loaded\", user)", "\treturn user", "}", "", "func report() {",
                     "\tfmt.Printf(\"done\\n\")", "}"]
        XCTAssertEqual(quickFix("go-debug-print", at: 7, in: lines, file: "a.go"), removal(7, of: lines))
    }

    func testGoPrintStaysWhenItsImportOrALocalWouldBeUnused() {
        let onlyFmt = ["import \"fmt\"", "func f() {", "\tfmt.Println(\"here\")", "}"]
        XCTAssertNil(quickFix("go-debug-print", at: 3, in: onlyFmt, file: "a.go"), "fmt would be unused")
        let onlyUse = ["import \"fmt\"", "func f(id string) {", "\tuser := find(id)", "\tfmt.Println(user)", "}",
                       "func g() { fmt.Print() }"]
        XCTAssertNil(quickFix("go-debug-print", at: 4, in: onlyUse, file: "a.go"), "user would be unused")
        XCTAssertNil(quickFix("go-debug-print", at: 1, in: ["fmt.Println(x)", "fmt.Println(x)"], file: "a.go"),
                     "Not inside a function")
    }

    // MARK: Rust dbg!

    func testRustDbgIsUnwrappedAroundItsValue() {
        let lines = ["pub fn total(a: u64, b: u64) -> u64 {", "    let sum = dbg!(a + b);", "    dbg!(sum)", "}"]
        XCTAssertEqual(quickFix("rust-debug-print", at: 2, in: lines, file: "src/a.rs"),
                       QuickFix(startLine: 2, removed: ["    let sum = dbg!(a + b);"], added: ["    let sum = a + b;"]))
        XCTAssertEqual(quickFix("rust-debug-print", at: 3, in: lines, file: "src/a.rs")?.added, ["    sum"])
        XCTAssertEqual(quickFix("rust-debug-print", at: 1, in: ["call(dbg!(&x), y);"], file: "src/a.rs")?.added,
                       ["call(&x, y);"])
    }

    func testRustDbgStatementIsDeleted() {
        let lines = ["fn f() {", "    dbg!(&state);", "}"]
        XCTAssertEqual(quickFix("rust-debug-print", at: 2, in: lines, file: "src/a.rs"), removal(2, of: lines))
    }

    func testRustDbgStaysWhereUnwrappingIsAmbiguous() {
        XCTAssertNil(quickFix("rust-debug-print", at: 1, in: ["let x = dbg!(a + b) * 2;"], file: "src/a.rs"),
                     "Precedence")
        XCTAssertNil(quickFix("rust-debug-print", at: 1, in: ["let x = dbg!(a, b);"], file: "src/a.rs"), "A tuple")
        XCTAssertNil(quickFix("rust-debug-print", at: 1, in: ["let x = dbg!(dbg!(a));"], file: "src/a.rs"), "Two")
        XCTAssertNil(quickFix("rust-debug-print", at: 1, in: ["let x = dbg!();"], file: "src/a.rs"), "Empty")
        XCTAssertNil(quickFix("rust-debug-print", at: 1, in: ["let x = dbg!(", "    a);"], file: "src/a.rs"))
        XCTAssertNil(quickFix("rust-debug-print", at: 1, in: ["if a == dbg!(b) {"], file: "src/a.rs"), "Comparison")
    }
}

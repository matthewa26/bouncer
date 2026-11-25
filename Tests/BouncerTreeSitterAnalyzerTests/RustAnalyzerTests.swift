import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class RustAnalyzerTests: XCTestCase {
    private func findings(
        _ contents: String, file name: String = "src/lib.rs", settings: [String: RuleSettings] = [:]
    ) throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: .rust, contents: contents)
        return try TreeSitterAnalyzer(spec: .rust).analyze(file: file, context: context)
    }

    private func messages(
        of ruleID: String, in contents: String, file: String = "src/lib.rs", settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.message)
    }

    private func lines(
        of ruleID: String, in contents: String, file: String = "src/lib.rs", settings: [String: RuleSettings] = [:]
    ) throws -> [Int] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    private let widget = """
        use std::fmt;

        /// A widget.
        pub struct Widget {
            size: u32,
            name: String,
        }

        impl Widget {
            /// Configures the widget.
            pub fn configure(&mut self, size: u32, name: &str, animated: bool) -> Result<(), String> {
                if size > 0 {
                    for step in 0..size {
                        while animated && step > 0 {
                            break;
                        }
                    }
                }
                let parsed: u32 = name.parse().map_err(|_| String::from("bad"))?;
                self.size = parsed;
                Ok(())
            }

            fn layout(&self) -> u32 {
                return self.size * 30;
                self.size
            }
        }
        """

    // MARK: Language and dispatch

    func testMapsTheRsExtensionToRust() {
        XCTAssertEqual(Language.from(fileExtension: "rs"), .rust)
        XCTAssertEqual(Language.from(fileExtension: "RS", contents: ""), .rust)
    }

    // MARK: Shared rules over Rust

    func testCountsParametersWithoutSelfAndFlagsBooleanParameters() throws {
        let limit = setting("long-parameter-list", ["maxParameters": .int(2)])
        XCTAssertEqual(try messages(of: "long-parameter-list", in: widget, settings: limit),
                       ["Function \"configure\" has 3 parameters, over the 2 limit."])
        XCTAssertEqual(try messages(of: "boolean-parameter", in: widget),
                       ["Function \"configure\" has 1 boolean flag parameter(s), over the 0 limit."])
    }

    func testMeasuresLengthNestingAndCognitiveComplexity() throws {
        XCTAssertEqual(try lines(of: "long-function", in: widget, settings: setting("long-function", ["maxLines": .int(5)])),
                       [11])
        // if (1) + nested for (2) + nested while (3) + && run (1) = 7; `?` adds nothing.
        XCTAssertEqual(try messages(of: "cognitive-complexity", in: widget,
                                    settings: setting("cognitive-complexity", ["max": .int(1)])),
                       ["Function \"configure\" has cognitive complexity 7, over the 1 limit."])
        XCTAssertEqual(try messages(of: "nesting-depth", in: widget,
                                    settings: setting("nesting-depth", ["maxDepth": .int(2)])),
                       ["Function \"configure\" has control flow nested 3 deep, over the 2 limit."])
    }

    func testCountsMatchArmsAsBranchesAndCyclomaticComplexity() throws {
        let contents = """
            /// Names a code.
            pub fn name(code: u8, loud: bool) -> &'static str {
                match code {
                    0 => "zero",
                    1 if loud => "ONE",
                    1 => "one",
                    _ => "many",
                }
            }
            """
        XCTAssertEqual(try messages(of: "switch-on-type-smell", in: contents,
                                    settings: setting("switch-on-type-smell", ["maxBranches": .int(3)])),
                       ["Switch has 4 branches, over the 3-branch limit."])
        // 1 + four arms = 5.
        XCTAssertEqual(try messages(of: "cyclomatic-complexity", in: contents,
                                    settings: setting("cyclomatic-complexity", ["max": .int(4)])).count, 1)
        XCTAssertEqual(try messages(of: "cyclomatic-complexity", in: contents,
                                    settings: setting("cyclomatic-complexity", ["max": .int(5)])), [])
    }

    func testFlagsUnreachableCodeElseAfterReturnAndMagicNumbers() throws {
        XCTAssertEqual(try lines(of: "unreachable-code", in: widget), [26])
        XCTAssertEqual(try lines(of: "magic-number", in: widget), [25])
        let contents = """
            const LIMIT: u32 = 40;
            /// Checks.
            pub fn check(x: u32) -> u32 {
                let buffer = [0u8; 64];
                assert_eq!(x, 99);
                if x > LIMIT {
                    return 1;
                } else {
                    x + 7
                }
            }
            """
        XCTAssertEqual(try lines(of: "magic-number", in: contents), [9])
        XCTAssertEqual(try lines(of: "else-after-return", in: contents), [8])
    }

    func testRequiresDocsOnPublicFunctionsOnly() throws {
        let contents = """
            /// Documented.
            #[inline]
            pub fn documented() {}

            pub fn undocumented() {}

            pub(crate) fn internal() {}

            fn private() {}

            #[doc = "Documented by attribute."]
            pub fn attributed() {}

            pub fn inner() {
                //! Documented from inside.
            }

            /// A shape.
            pub trait Shape {
                fn area(&self) -> f64 { 0.0 }
            }

            impl std::fmt::Display for Point {
                fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result { Ok(()) }
            }
            """
        XCTAssertEqual(try lines(of: "missing-documentation", in: contents), [5, 20])
        let all = setting("missing-documentation", ["scope": .string("all")])
        XCTAssertEqual(try lines(of: "missing-documentation", in: contents, settings: all), [5, 7, 9, 20, 24])
    }

    func testChecksSnakeCaseFunctionsAndCamelCaseTypes() throws {
        let contents = """
            fn snake_case() {}
            fn camelCase() {}
            fn r#type() {}
            fn _unused() {}
            struct GoodName;
            struct bad_name { x: u8 }
            enum HTTPStatus { Ok }
            trait r#Trait {}
            """
        XCTAssertEqual(try messages(of: "naming-convention", in: contents), [
            "function \"camelCase\" doesn't match the expected naming convention.",
            "type \"bad_name\" doesn't match the expected naming convention."
        ])
    }

    func testCountsImplMethodsAsTheTypesMembers() throws {
        let limits = ["god-class": RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(
            values: ["maxMembers": .int(3), "maxImportsForGodClass": .int(0)]
        ))]
        XCTAssertEqual(try messages(of: "god-class", in: widget, settings: limits),
                       ["Type \"Widget\" has 4 members in a file with 1 imports."])
    }

    func testFindsTestsByAttributeAndCountsAssertMacrosAndShouldPanic() throws {
        let contents = """
            #[cfg(test)]
            mod tests {
                #[test]
                fn asserts() { assert_eq!(1 + 1, 2); }

                #[test]
                fn only_unwraps() { "1".parse::<u8>().unwrap(); }

                #[test]
                #[should_panic]
                fn panics() { boom(); }

                #[tokio::test]
                async fn async_without_assert() { run().await; }

                fn helper() {}
            }
            """
        XCTAssertEqual(try lines(of: "test-without-assertions", in: contents), [7, 14])
    }

    // MARK: Rust smells

    func testFlagsUnwrapAndExpectOutsideTests() throws {
        let contents = """
            /// Reads.
            pub fn read() -> u8 {
                let a = "1".parse::<u8>().unwrap();
                let b = "2".parse::<u8>().expect("number");
                let c = "3".parse::<u8>().unwrap_or(0);
                a + b + c
            }

            #[cfg(test)]
            mod tests {
                #[test]
                fn reads() { assert_eq!("1".parse::<u8>().unwrap(), 1); }
                fn helper() -> u8 { "1".parse().unwrap() }
            }

            #[test]
            fn top_level() { "1".parse::<u8>().unwrap(); }
            """
        XCTAssertEqual(try lines(of: "rust-unwrap", in: contents), [3, 4])
        XCTAssertEqual(try lines(of: "rust-unwrap", in: contents, file: "tests/it.rs"), [])
        XCTAssertEqual(try lines(of: "rust-unwrap", in: contents, file: "src/tests/util.rs"), [])
        XCTAssertEqual(try lines(of: "rust-unwrap", in: contents, file: "src/walk/tests.rs"), [])
        XCTAssertEqual(try lines(of: "rust-unwrap", in: "#![cfg(test)]\nfn f() { x.unwrap(); }\n"), [])
    }

    func testRequiresASafetyCommentOnUnsafeCode() throws {
        let contents = """
            /// Reads raw memory.
            ///
            /// # Safety
            ///
            /// `p` must be valid.
            pub unsafe fn documented(p: *const u8) -> u8 { *p }

            pub unsafe fn undocumented(p: *const u8) -> u8 { *p }

            fn blocks(p: *const u8) -> u8 {
                // SAFETY: `p` comes from a live reference.
                let a = unsafe { *p };
                let b = unsafe { *p };
                let c = unsafe {
                    // SAFETY: checked above.
                    *p
                };
                let d = unsafe { *p }; // SAFETY: same pointer.
                let e = [p].iter()
                    // SAFETY: each pointer is live.
                    .map(|q| unsafe { **q })
                    .sum::<u8>();
                a + b + c + d + e
            }

            unsafe impl Send for Handle {}

            // SAFETY: the handle is never shared mutably.
            unsafe impl Sync for Handle {}

            /// Vector operations.
            ///
            /// # Safety
            ///
            /// Callers must check for the CPU feature.
            pub unsafe trait Vector {
                unsafe fn splat(byte: u8) -> Self;
                unsafe fn and(self, other: Self) -> Self { self }
            }

            // SAFETY: SSE2 is checked at startup.
            unsafe impl Vector for Lane {
                unsafe fn splat(byte: u8) -> Self { Lane(byte) }
                unsafe fn and(self, other: Self) -> Self { self }
            }
            """
        XCTAssertEqual(try lines(of: "rust-unsafe-without-safety-comment", in: contents), [8, 13, 26])
    }

    func testFlagsTodoAndUnimplementedEverywhere() throws {
        let contents = """
            fn later() { todo!() }
            fn never() { unimplemented!("soon") }
            // todo!() in a comment isn't code.
            #[test]
            fn pending() { todo!() }
            """
        XCTAssertEqual(try lines(of: "rust-todo-macro", in: contents), [1, 2, 5])
    }

    func testFlagsPrintingInLibrariesButNotProgramsOrTestsAndDbgEverywhere() throws {
        let contents = """
            fn report(x: u8) {
                println!("{}", x);
                eprintln!("{}", x);
                dbg!(x);
            }
            #[test]
            fn shows() { println!("ok"); dbg!(1); }
            """
        XCTAssertEqual(try lines(of: "rust-debug-print", in: contents), [2, 3, 4, 7])
        XCTAssertEqual(try lines(of: "rust-debug-print", in: contents, file: "src/main.rs"), [4, 7])
        XCTAssertEqual(try lines(of: "rust-debug-print", in: contents, file: "src/bin/tool.rs"), [4, 7])
        XCTAssertEqual(try lines(of: "rust-debug-print", in: contents, file: "build.rs"), [4, 7])
        XCTAssertEqual(try lines(of: "rust-debug-print", in: contents, file: "tool/main.rs"), [4, 7])
        XCTAssertEqual(try lines(of: "rust-debug-print", in: contents + "fn main() {}\n", file: "src/cli.rs"), [4, 7])
    }

    func testFlagsPanicInLibraryCodeOnly() throws {
        let contents = """
            fn check(x: u8) { if x == 0 { panic!("zero"); } }
            #[cfg(test)]
            mod tests { fn boom() { panic!("test"); } }
            """
        XCTAssertEqual(try lines(of: "rust-panic", in: contents), [1])
        XCTAssertEqual(try lines(of: "rust-panic", in: contents, file: "src/main.rs"), [])
        XCTAssertEqual(try lines(of: "rust-panic", in: contents, file: "examples/demo.rs"), [])
    }

    func testFlagsShellCommandsBuiltWithFormatOrConcatenation() throws {
        let contents = """
            use std::process::Command;
            fn run(dir: &str) {
                Command::new("sh").arg("-c").arg(format!("ls {}", dir)).status();
                Command::new("/bin/bash")
                    .args(["-c", &("rm -rf ".to_owned() + dir)])
                    .status();
                Command::new("sh").arg("-c").arg("ls -la").status();
                Command::new("ls").arg(format!("{}", dir)).status();
                std::process::Command::new("cmd").arg("/C").arg(format!("dir {dir}")).status();
            }
            """
        XCTAssertEqual(try lines(of: "rust-shell-injection", in: contents), [3, 4, 9])
    }

    func testAppliesCrossLanguageSecurityPatterns() throws {
        let contents = """
            fn client() {
                let c = reqwest::Client::builder().danger_accept_invalid_certs(true).build();
                let q = format!("SELECT * FROM users WHERE id = {}", id);
                let url = "http://api.vendor.io/v1";
                let hash = md5::compute(b"x");
                let key = "AKIAABCDEFGHIJKLMNOP";
                let host = "192.168.1.20";
            }
            #[ignore]
            #[test]
            fn slow() {}
            """
        let ids = try findings(contents).map(\.ruleID)
        for rule in ["disabled-tls-verification", "sql-string-building", "insecure-http-url", "weak-crypto",
                     "skipped-test", "secret-looking-pattern", "hardcoded-ip"] {
            XCTAssertTrue(ids.contains(rule), rule)
        }
    }
}

final class RustModuleFactsTests: XCTestCase {
    private func specifiers(_ contents: String) throws -> [String] {
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/src/lib.rs"), language: .rust, contents: contents)
        return try TreeSitterAnalyzer(spec: .rust).moduleFacts(file: file)?.imports.map(\.specifier) ?? []
    }

    func testRecordsModDeclarationsAndExpandsUseLists() throws {
        let contents = """
            mod walk;
            pub(crate) mod error;
            mod inline {
                mod nested;
                use super::walk::Walker;
                use self::nested::Thing;
            }
            use crate::{walk::{self, WalkDir}, error::Error as E};
            use std::io::*;
            #[cfg(test)]
            mod tests {
                use super::*;
            }
            """
        XCTAssertEqual(try specifiers(contents), [
            "mod walk", "mod error", "mod inline::nested", "self::walk::Walker", "self::inline::nested::Thing",
            "crate::walk::self", "crate::walk::WalkDir", "crate::error::Error", "std::io", "self"
        ])
    }

    func testRecordsStructuresAndImplMethodOwners() throws {
        let contents = """
            pub struct Walker { root: PathBuf, depth: usize }
            pub trait Visit { fn visit(&self); }
            impl Walker<'_> {
                pub fn new(root: PathBuf, depth: usize) -> Self { Walker { root, depth } }
            }
            """
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/src/lib.rs"), language: .rust, contents: contents)
        let structure = try XCTUnwrap(try TreeSitterAnalyzer(spec: .rust).moduleFacts(file: file)?.structure)
        XCTAssertEqual(structure.types.map(\.name), ["Walker", "Visit"])
        XCTAssertEqual(structure.types.first?.fields, ["root:PathBuf", "depth:usize"])
        XCTAssertEqual(structure.types.last?.methods, ["visit"])
        XCTAssertEqual(structure.functions.map { "\($0.owner ?? "-").\($0.name)(\($0.parameters.joined(separator: ",")))" },
                       ["Walker.new(root,depth)"])
    }
}

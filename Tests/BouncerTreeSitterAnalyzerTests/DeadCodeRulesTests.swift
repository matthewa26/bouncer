import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class DeadCodeRulesTests: XCTestCase {
    private let parameterOn = ["unused-parameter": RuleSettings(enabled: true, severity: .warning, parameters: .empty)]

    private func messages(
        of ruleID: String, in contents: String, file name: String = "a.ts", settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let language = Language.from(fileExtension: URL(fileURLWithPath: name).pathExtension)
        let spec: TreeSitterLanguageSpec = [.python: .python, .go: .go, .javascript: .javascript][language] ?? .typescript
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec).analyze(file: file, context: context)
            .filter { $0.ruleID == ruleID }.map { "\($0.line): \($0.message)" }
    }

    // MARK: unused-private-symbol

    func testFlagsUnexportedTopLevelDeclarationsInAModule() throws {
        let contents = """
            import { x } from "./x";
            function unused() {}
            function recursive() { recursive(); }
            class Orphan {}
            const a = 1, b = a;
            let { destructured } = x;
            function used() {}
            export function api() { used(); }
            function _ignored() {}
            """
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: contents), [
            "2: Unexported function \"unused\" is never used in this file.",
            "3: Unexported function \"recursive\" is never used in this file.",
            "4: Unexported class \"Orphan\" is never used in this file.",
            "5: Unexported variable \"b\" is never used in this file."
        ])
    }

    func testCountsExportClausesDefaultExportsJSXTypesAndCommonJSAsUses() throws {
        let contents = """
            function a() {}
            class B {}
            const C = () => null;
            interface Shape { b: B }
            function d() {}
            const e = 1;
            export { a };
            export default C;
            const view = <C prop={d} />;
            module.exports = { e, view };
            """
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: contents, file: "a.tsx"), [])
    }

    func testSkipsScriptsAndDeclarationFiles() throws {
        let script = "function globalHelper() {}\n"
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: script, file: "a.js"), [])
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: "export {};\nfunction f() {}\n", file: "a.d.ts"), [])
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: script, file: "a.mjs"), [
            "1: Unexported function \"globalHelper\" is never used in this file."
        ])
    }

    func testFlagsOnlyUnderscoredModuleLevelPythonDefinitions() throws {
        let contents = """
            def public(): pass
            def _unused(): pass
            @decorator
            class _Hidden: pass
            def _used(): pass
            def __getattr__(name): pass
            def _listed(): pass
            __all__ = ["_listed"]
            class K:
                def _method(self): pass
            public(_used())
            """
        XCTAssertEqual(try messages(of: "unused-private-symbol", in: contents, file: "a.py"), [
            "2: Private function \"_unused\" is never used in this file.",
            "4: Private class \"_Hidden\" is never used in this file."
        ])
    }

    func testGoHasNoDeadCodeRulesSinceAPackageSpansFiles() throws {
        let contents = "package a\n\nimport \"fmt\"\n\nfunc helper(x int) {}\n"
        for rule in ["unused-private-symbol", "unused-import"] {
            XCTAssertEqual(try messages(of: rule, in: contents, file: "a.go"), [])
        }
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents, file: "a.go", settings: parameterOn), [])
    }

    // MARK: unused-import

    func testFlagsUnusedTypeScriptImportBindings() throws {
        let contents = """
            import Default, { used, unused as alias, Type } from "m";
            import * as ns from "n";
            import type { Only } from "t";
            import "side-effect";
            import { reexported } from "r";
            export { reexported };
            export * from "s";
            let v: Type = used();
            """
        XCTAssertEqual(try messages(of: "unused-import", in: contents), [
            "1: Import \"Default\" is never used in this file.",
            "1: Import \"alias\" is never used in this file.",
            "2: Import \"ns\" is never used in this file.",
            "3: Import \"Only\" is never used in this file."
        ])
    }

    func testJSXTypePositionsAndJSDocCountAsImportUses() throws {
        let contents = """
            import React from "react";
            import { Foo, Bar } from "./components";
            import { Props } from "./types";
            import { Doc } from "./doc";
            /** @param {Doc} d */
            export const view = (p: Props) => <Foo.Item><Bar /></Foo.Item>;
            """
        XCTAssertEqual(try messages(of: "unused-import", in: contents, file: "a.tsx"), [])
    }

    func testFlagsUnusedPythonImportsWithItsExemptions() throws {
        let contents = """
            from __future__ import annotations
            import os.path
            import sys as system
            import json
            from typing import TYPE_CHECKING, Optional
            from .models import Model, Unused
            from .star import *
            import readline  # noqa: F401
            from .api import exported
            __all__ = ["exported"]
            def f(x: "Optional[Model]") -> None:
                print(os.path.join("a"), TYPE_CHECKING)
            """
        XCTAssertEqual(try messages(of: "unused-import", in: contents, file: "a.py"), [
            "3: Import \"system\" is never used in this file.",
            "4: Import \"json\" is never used in this file.",
            "6: Import \"Unused\" is never used in this file."
        ])
        XCTAssertEqual(try messages(of: "unused-import", in: contents, file: "__init__.py"), [])
    }

    // MARK: unused-parameter

    func testUnusedParameterIsOffUnlessConfigured() throws {
        let contents = "export function f(a: number) { return 1; }\n"
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents), [])
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents, settings: parameterOn), [
            "1: Parameter \"a\" of \"f\" is never used in its body."
        ])
    }

    func testFlagsTypeScriptParametersAfterTheLastUsedOne() throws {
        let contents = """
            export const pick = (item, index, all) => index;
            export function g(a = 1, b = a, c?: string) { return b; }
            export function h({ x }, _skip, y) { return 1; }
            export const obj = { m(p) { return 0; } };
            """
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents, settings: parameterOn), [
            "1: Parameter \"all\" of \"pick\" is never used in its body.",
            "2: Parameter \"c\" of \"g\" is never used in its body.",
            "3: Parameter \"y\" of \"h\" is never used in its body.",
            "4: Parameter \"p\" of \"m\" is never used in its body."
        ])
    }

    func testSkipsTypeScriptSignaturesStubsOverridesAndParameterProperties() throws {
        let contents = """
            export function over(a: string): void;
            export function over(a: string, b?: number) { console.log(a, b); }
            declare function ambient(x: number): void;
            export abstract class Shape { abstract area(scale: number): number; }
            export interface I { m(x: number): void; }
            export class Impl implements I { m(x: number) { return 1; } }
            export class Sub extends Shape { area(scale: number) { return 1; } }
            export class Own { override z(q: number) { return 1; } constructor(private svc: number, readonly r: number) { this.go(); } go() {} }
            export function empty(a) {}
            export function fail(a) { throw new Error("no"); }
            export function variadic(a) { return arguments.length; }
            """
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents, settings: parameterOn), [])
    }

    func testFlagsPythonParametersWithItsExemptions() throws {
        let contents = """
            def f(used, unused, *args, _private=1, **kwargs):
                return used
            class Plain:
                def m(self, value):
                    return 1
                @classmethod
                def c(cls, value):
                    return value
                def __eq__(self, other):
                    return True
            class Child(Base):
                def m(self, value):
                    return 1
            def stub(a):
                \"\"\"Docs.\"\"\"
                ...
            def raises(a):
                raise NotImplementedError
            @abstractmethod
            def abstract(a):
                return 1
            def test_thing(fixture):
                assert True
            def dynamic(a):
                return locals()
            """
        XCTAssertEqual(try messages(of: "unused-parameter", in: contents, file: "a.py", settings: parameterOn), [
            "1: Parameter \"unused\" of \"f\" is never used in its body.",
            "4: Parameter \"value\" of \"m\" is never used in its body."
        ])
    }
}

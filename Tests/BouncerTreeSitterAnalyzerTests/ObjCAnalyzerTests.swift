import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class ObjCAnalyzerTests: XCTestCase {
    private func findings(
        _ contents: String, file name: String = "a.m", settings: [String: RuleSettings] = [:],
        fallback: LanguageAnalyzer? = nil
    ) throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let language = Language.from(fileExtension: URL(fileURLWithPath: name).pathExtension, contents: contents)
        let spec: TreeSitterLanguageSpec = language == .typescript ? .typescript : .objc
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: language, contents: contents)
        return try TreeSitterAnalyzer(spec: spec, fallback: fallback).analyze(file: file, context: context)
    }

    private func messages(
        of ruleID: String, in contents: String, file: String = "a.m", settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.message)
    }

    private func lines(of ruleID: String, in contents: String, settings: [String: RuleSettings] = [:]) throws -> [Int] {
        try findings(contents, settings: settings).filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    private let widget = """
        #import "Widget.h"

        @implementation Widget

        - (void)configureWithName:(NSString *)name size:(NSInteger)size animated:(BOOL)animated {
          if (size > 0) {
            for (NSInteger i = 0; i < size; i++) {
              while (animated && i > 0) {
                NSLog(@"step %ld", (long)i);
                break;
              }
            }
          }
          @try {
            [self layoutWithTimeout:30];
          } @catch (NSException *exception) {
          }
        }

        /// Lays out the widget.
        - (void)layoutWithTimeout:(NSInteger)timeout {
          return;
          [self setNeedsLayout];
        }

        @end
        """

    // MARK: Shared rules over Objective-C

    func testCountsSelectorArgumentsAsParametersAndNamesMethodsBySelector() throws {
        let limit = setting("long-parameter-list", ["maxParameters": .int(2)])
        XCTAssertEqual(try messages(of: "long-parameter-list", in: widget, settings: limit),
                       ["Function \"configureWithName:size:animated:\" has 3 parameters, over the 2 limit."])
        let flags = setting("boolean-parameter", ["maxBooleanParameters": .int(0)])
        XCTAssertEqual(try messages(of: "boolean-parameter", in: widget, settings: flags),
                       ["Function \"configureWithName:size:animated:\" has 1 boolean flag parameter(s), over the 0 limit."])
    }

    func testMeasuresLengthNestingAndCognitiveComplexityOfAMethod() throws {
        XCTAssertEqual(try lines(of: "long-function", in: widget, settings: setting("long-function", ["maxLines": .int(5)])),
                       [5])
        // if (1) + nested for (2) + nested while (3) + && run (1) + nested catch (1) = 8
        XCTAssertEqual(try messages(of: "cognitive-complexity", in: widget,
                                    settings: setting("cognitive-complexity", ["max": .int(1)])),
                       ["Function \"configureWithName:size:animated:\" has cognitive complexity 8, over the 1 limit."])
        XCTAssertEqual(try messages(of: "nesting-depth", in: widget,
                                    settings: setting("nesting-depth", ["maxDepth": .int(2)])).count, 1)
    }

    func testFlagsEmptyCatchUnreachableCodeMagicNumbersAndNSLog() throws {
        XCTAssertEqual(try lines(of: "empty-catch", in: widget), [16])
        XCTAssertEqual(try lines(of: "unreachable-code", in: widget), [23])
        XCTAssertEqual(try lines(of: "magic-number", in: widget), [15])
        XCTAssertEqual(try lines(of: "objc-debug-log", in: widget), [9])
    }

    func testRequiresADocCommentAboveEachMethodAndFunction() throws {
        let all = setting("missing-documentation", ["scope": .string("all")])
        XCTAssertEqual(try messages(of: "missing-documentation", in: widget, settings: all),
                       ["Function \"configureWithName:size:animated:\" has no doc comment above its declaration."])
        let contents = "/** Adds. */\nint add(int a, int b) { return a + b; }\nint sub(int a, int b) { return a - b; }\n"
        XCTAssertEqual(try lines(of: "missing-documentation", in: contents), [3])
    }

    func testTreatsMethodsAsInternalAndStaticFunctionsAsPrivateByDefault() throws {
        let contents = """
            @implementation A
            - (void)run { }
            @end
            static void helper(void) { }
            void Exported(void) { }
            """
        XCTAssertEqual(try lines(of: "missing-documentation", in: contents), [5])
    }

    func testFlagsNestedTernaryAndScoresBlocksAsClosures() throws {
        let contents = """
            /// Picks.
            int pick(int a, int b) {
              void (^log)(void) = ^{ if (a) { if (b) { return; } } };
              return a ? (b ? 1 : 2) : 0;
            }
            """
        XCTAssertEqual(try lines(of: "nested-ternary", in: contents), [4])
        // Block body: if (1, plus 1 for the block's nesting) + nested if (3) = 5; each ternary scores 1.
        XCTAssertEqual(try messages(of: "cognitive-complexity", in: contents,
                                    settings: setting("cognitive-complexity", ["max": .int(1)])),
                       ["Function \"pick\" has cognitive complexity 7, over the 1 limit."])
    }

    func testNamesClassesWithPrefixesAndCategoriesAndChecksMethodCase() throws {
        let contents = """
            @interface ABCWidget : NSObject
            @end
            @interface ABCWidget (Layout)
            @end
            @implementation ABCWidget
            - (void)Run_now:(int)a { }
            - (void)runNow:(int)a { }
            @end
            void CGThingMake(void) { }
            """
        XCTAssertEqual(try messages(of: "naming-convention", in: contents),
                       ["function \"Run_now:\" doesn't match the expected naming convention."])
    }

    func testAcceptsAcronymAndCategoryPrefixedSelectors() throws {
        let contents = """
            @implementation NSURL (Testing)
            - (void)URLWithStatusCode:(int)code { }
            - (void)af_setImageWithURL:(id)url { }
            - (void)HTTPMethod { }
            - (void)Lookup:(int)a { }
            @end
            """
        XCTAssertEqual(try messages(of: "naming-convention", in: contents),
                       ["function \"Lookup:\" doesn't match the expected naming convention."])
    }

    func testCountsXCTestExpectationsAsAssertions() throws {
        let contents = """
            @implementation WidgetTests
            - (void)testLoads {
                XCTestExpectation *done = [self expectationWithDescription:@"loaded"];
                [self.widget loadWithCompletion:^{ [done fulfill]; }];
                [self waitForExpectationsWithTimeout:1 handler:nil];
            }
            - (void)testDoesNotCrash {
                [self.widget load];
            }
            - (void)testDelegatesToAVerifyHelper {
                [self verifyWidgetLoads:self.widget];
            }
            @end
            """
        XCTAssertEqual(try lines(of: "test-without-assertions", in: contents), [7])
    }

    func testCountsMethodsAndMeasuresCohesionThroughSelfProperties() throws {
        let contents = """
            @implementation Split
            - (int)readA { return self.a; }
            - (void)bumpA { self.a = self.a + 1; }
            - (int)readB { return self.b; }
            - (void)bumpB { self.b = self.b + 1; }
            + (instancetype)shared { return nil; }
            @end
            """
        XCTAssertEqual(try messages(of: "too-many-methods", in: contents, settings: setting("too-many-methods", ["maxMethods": .int(4)])),
                       ["Type \"Split\" has 5 methods, over the 4 limit."])
        XCTAssertEqual(try messages(of: "lack-of-cohesion", in: contents, settings: setting("lack-of-cohesion", ["maxGroups": .int(1)])),
                       ["Type \"Split\" splits into 2 unrelated method groups (LCOM4), over 1."])
    }

    // MARK: Parity with TypeScript

    func testMatchesTypeScriptOnAnEquivalentFunction() throws {
        let objc = """
            /// Scores.
            int score(int a, int b, int c) {
              if (a > 0 && b > 0) {
                for (int i = 0; i < c; i++) {
                  if (i == b) { return i; }
                }
              } else if (c) {
                return c ? a : b;
              }
              return 0;
            }
            """
        let typescript = """
            /** Scores. */
            function score(a: number, b: number, c: number): number {
              if (a > 0 && b > 0) {
                for (let i = 0; i < c; i++) {
                  if (i == b) { return i; }
                }
              } else if (c) {
                return c ? a : b;
              }
              return 0;
            }
            """
        for ruleID in ["cognitive-complexity", "cyclomatic-complexity", "long-parameter-list", "too-many-returns"] {
            let limits = setting(ruleID, ["max": .int(1), "maxParameters": .int(1), "maxReturns": .int(1)])
            XCTAssertFalse(try messages(of: ruleID, in: objc, settings: limits).isEmpty, ruleID)
            XCTAssertEqual(try messages(of: ruleID, in: objc, settings: limits),
                           try messages(of: ruleID, in: typescript, file: "a.ts", settings: limits), ruleID)
        }
    }

    // MARK: Objective-C++ fallback

    private struct MarkerAnalyzer: LanguageAnalyzer {
        let supportedLanguage: BouncerCore.Language = .objc

        func analyze(file: SourceFile, context: AnalysisContext) throws -> [Finding] {
            [Finding(ruleID: "fallback", severity: .warning, filePath: file.path, line: 1, message: "heuristic")]
        }
    }

    func testFallsBackForObjectiveCPlusPlusThatTheGrammarCannotParse() throws {
        let contents = """
            #import "Foo.h"
            #include <vector>

            namespace geometry {
            template <typename T>
            class Point {
             public:
              Point(T x, T y) : x_(x), y_(y) {}
             private:
              T x_;
            };
            }

            @implementation Foo
            - (void)run {
              std::vector<int> values;
              auto p = geometry::Point<int>(1, 2);
            }
            @end
            """
        XCTAssertEqual(try findings(contents, file: "a.mm", fallback: MarkerAnalyzer()).map(\.ruleID), ["fallback"])
    }

    func testKeepsTheTreeForObjectiveCPlusPlusThatParses() throws {
        let contents = "#import \"Foo.h\"\n@implementation Foo\n- (void)run { NSLog(@\"x\"); }\n@end\n"
        let found = try findings(contents, file: "a.mm", fallback: MarkerAnalyzer()).map(\.ruleID)
        XCTAssertFalse(found.contains("fallback"))
        XCTAssertTrue(found.contains("objc-debug-log"))
    }

    // MARK: Module facts

    func testRecordsImportsAndDeclaredTypes() throws {
        let contents = """
            #import "Foo.h"
            #import <UIKit/UIKit.h>
            #import "App-Swift.h"
            @import Foundation;
            #include <stdio.h>
            @interface Foo : NSObject <NSCopying, Doer>
            @property (nonatomic, copy) NSString *name;
            - (void)runWith:(int)a;
            @end
            @protocol Doer <NSObject>
            @end
            """
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/Foo.h"), language: .objc, contents: contents)
        let facts = try XCTUnwrap(try TreeSitterAnalyzer(spec: .objc).moduleFacts(file: file))
        XCTAssertEqual(facts.imports.map(\.specifier),
                       ["Foo.h", "<UIKit/UIKit.h>", "App-Swift.h", "@import Foundation", "<stdio.h>"])
        let foo = try XCTUnwrap(facts.structure.types.first { $0.name == "Foo" })
        XCTAssertEqual(foo.supertypes, ["NSObject", "NSCopying", "Doer"])
        XCTAssertEqual(foo.fields, ["name"])
        XCTAssertEqual(foo.methods, ["runWith:"])
        XCTAssertEqual(facts.structure.types.first { $0.name == "Doer" }?.kind, .protocol)
    }
}

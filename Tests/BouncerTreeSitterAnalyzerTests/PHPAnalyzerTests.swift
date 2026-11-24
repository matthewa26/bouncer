import XCTest
import Foundation
import BouncerCore
import SwiftTreeSitter
@testable import BouncerTreeSitterAnalyzer

final class PHPAnalyzerTests: XCTestCase {
    private func findings(
        _ contents: String, file name: String = "src/Widget.php", settings: [String: RuleSettings] = [:]
    ) throws -> [Finding] {
        let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: settings)
        let file = SourceFile(path: URL(fileURLWithPath: "/repo/\(name)"), language: .php, contents: contents)
        return try TreeSitterAnalyzer(spec: .php).analyze(file: file, context: context)
    }

    private func messages(
        of ruleID: String, in contents: String, file: String = "src/Widget.php",
        settings: [String: RuleSettings] = [:]
    ) throws -> [String] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.message)
    }

    private func lines(
        of ruleID: String, in contents: String, file: String = "src/Widget.php",
        settings: [String: RuleSettings] = [:]
    ) throws -> [Int] {
        try findings(contents, file: file, settings: settings).filter { $0.ruleID == ruleID }.map(\.line)
    }

    private func setting(_ ruleID: String, _ values: [String: RuleParameterValue] = [:]) -> [String: RuleSettings] {
        [ruleID: RuleSettings(enabled: true, severity: .warning, parameters: RuleParameters(values: values))]
    }

    private let widget = """
        <?php
        namespace App;

        use App\\Contracts\\Shape;

        /** A widget. */
        final class Widget implements Shape
        {
            /** Configures the widget. */
            public function configure(int $size, string $name, bool $animated): void
            {
                if ($size > 0) {
                    foreach ($this->steps as $step) {
                        while ($animated && $step > 0) {
                            break;
                        }
                    }
                }
                $this->name = $name;
            }

            /** Lays out the widget. */
            private function layout(): int
            {
                return $this->size * 30;
                echo "never";
            }
        }
        """

    // MARK: Language and dispatch

    func testMapsThePHPAndPHTMLExtensionsToPHP() {
        XCTAssertEqual(Language.from(fileExtension: "php"), .php)
        XCTAssertEqual(Language.from(fileExtension: "phtml"), .php)
    }

    // MARK: Shared rules over PHP

    func testCountsParametersAndFlagsBooleanParameters() throws {
        let limit = setting("long-parameter-list", ["maxParameters": .int(2)])
        XCTAssertEqual(try messages(of: "long-parameter-list", in: widget, settings: limit),
                       ["Function \"configure\" has 3 parameters, over the 2 limit."])
        XCTAssertEqual(try messages(of: "long-parameter-list", in: widget), [])
        XCTAssertEqual(try messages(of: "boolean-parameter", in: widget),
                       ["Function \"configure\" has 1 boolean flag parameter(s), over the 0 limit."])
    }

    func testCountsPromotedAndVariadicParametersAndFlagDefaults() throws {
        let contents = """
            <?php
            /** A point. */
            class Point
            {
                /** Builds it. */
                public function __construct(private int $x, protected readonly int $y, bool $visible = true) {}

                /** Adds. */
                public function add(int ...$values): int { return 0; }

                /** Draws. */
                public function draw($color, $fill = false): void {}
            }
            """
        let limit = setting("long-parameter-list", ["maxParameters": .int(2)])
        XCTAssertEqual(try messages(of: "long-parameter-list", in: contents, settings: limit),
                       ["Function \"__construct\" has 3 parameters, over the 2 limit."])
        // A constructor stores flags rather than branching on them; `$fill = false` is a flag.
        XCTAssertEqual(try messages(of: "boolean-parameter", in: contents),
                       ["Function \"draw\" has 1 boolean flag parameter(s), over the 0 limit."])
    }

    func testMeasuresLengthNestingAndCognitiveComplexity() throws {
        XCTAssertEqual(try lines(of: "long-function", in: widget, settings: setting("long-function", ["maxLines": .int(5)])),
                       [10])
        XCTAssertEqual(try lines(of: "long-function", in: widget), [])
        // if (1) + nested foreach (2) + nested while (3) + && run (1) = 7.
        XCTAssertEqual(try messages(of: "cognitive-complexity", in: widget,
                                    settings: setting("cognitive-complexity", ["max": .int(1)])),
                       ["Function \"configure\" has cognitive complexity 7, over the 1 limit."])
        XCTAssertEqual(try messages(of: "cognitive-complexity", in: widget), [])
        XCTAssertEqual(try messages(of: "nesting-depth", in: widget,
                                    settings: setting("nesting-depth", ["maxDepth": .int(2)])),
                       ["Function \"configure\" has control flow nested 3 deep, over the 2 limit."])
        XCTAssertEqual(try messages(of: "nesting-depth", in: widget), [])
    }

    func testScoresElseIfLogicalKeywordsAndTernaries() throws {
        let contents = """
            <?php
            /** Grades. */
            function grade(int $n, $a, $b): string
            {
                if ($n > 90 and $a or $b) {
                    return 'A';
                } elseif ($n > 80) {
                    return 'B';
                } else if ($n > 70) {
                    return 'C';
                } else {
                    return $a ?: ($b ? 'D' : 'E');
                }
            }
            """
        // if (1) + `or` run (1) + `and` run (1) + elseif (1) + else (1) + the `else if`'s else (1), its `if`
        // scoring nothing, + two ternaries at nesting 1 (2 + 2) = 10.
        let cognitive = setting("cognitive-complexity", ["max": .int(1)])
        XCTAssertEqual(try messages(of: "cognitive-complexity", in: contents, settings: cognitive),
                       ["Function \"grade\" has cognitive complexity 10, over the 1 limit."])
        // 1 + if, elseif, if + and, or + two ternaries = 8.
        XCTAssertEqual(try messages(of: "cyclomatic-complexity", in: contents,
                                    settings: setting("cyclomatic-complexity", ["max": .int(7)])).count, 1)
        XCTAssertEqual(try messages(of: "cyclomatic-complexity", in: contents,
                                    settings: setting("cyclomatic-complexity", ["max": .int(8)])), [])
        XCTAssertEqual(try lines(of: "too-many-returns", in: contents, settings: setting("too-many-returns",
                                                                                     ["maxReturns": .int(3)])), [3])
        XCTAssertEqual(try lines(of: "too-many-returns", in: contents), [])
        XCTAssertEqual(try lines(of: "nested-ternary", in: contents), [12])
    }

    func testCountsMatchArmsAndSwitchCasesAsBranches() throws {
        let contents = """
            <?php
            /** Names a code. */
            function name(int $code): string
            {
                $label = match ($code) {
                    0 => 'zero',
                    1, 2 => 'few',
                    3 => 'three',
                    default => 'many',
                };
                switch ($code) {
                    case 0:
                        return $label;
                    case 1:
                    case 2:
                        break;
                    default:
                        return 'x';
                }
                return $label;
            }
            """
        let limit = setting("switch-on-type-smell", ["maxBranches": .int(2)])
        XCTAssertEqual(try messages(of: "switch-on-type-smell", in: contents, settings: limit),
                       ["Switch has 3 branches, over the 2-branch limit.",
                        "Switch has 3 branches, over the 2-branch limit."])
        XCTAssertEqual(try messages(of: "switch-on-type-smell", in: contents), [])
        // 1 + three arms + three cases = 7.
        XCTAssertEqual(try messages(of: "cyclomatic-complexity", in: contents,
                                    settings: setting("cyclomatic-complexity", ["max": .int(6)])).count, 1)
        XCTAssertEqual(try messages(of: "cyclomatic-complexity", in: contents,
                                    settings: setting("cyclomatic-complexity", ["max": .int(7)])), [])
    }

    func testFlagsUnreachableCodeElseAfterReturnAndMagicNumbers() throws {
        XCTAssertEqual(try lines(of: "unreachable-code", in: widget), [26])
        XCTAssertEqual(try lines(of: "magic-number", in: widget), [25])
        let contents = """
            <?php
            const LIMIT = 40;
            /** Checks. */
            function check(int $x, int $retries = 5): int
            {
                $timeout = 30;
                $options = ['timeout' => 60];
                if ($x > LIMIT) {
                    return 1;
                } else {
                    throw new \\Exception('no');
                    return $x + 7;
                }
            }
            """
        XCTAssertEqual(try lines(of: "magic-number", in: contents), [12])
        XCTAssertEqual(try lines(of: "else-after-return", in: contents), [10])
        XCTAssertEqual(try lines(of: "unreachable-code", in: contents), [12])
    }

    func testFlagsEmptyCatchButNotACommentedOne() throws {
        let contents = """
            <?php
            /** Loads. */
            function load(): void
            {
                try {
                    read();
                } catch (\\RuntimeException | \\LogicException $e) {
                } catch (\\Exception $e) {
                    // Nothing to clean up.
                } finally {
                    close();
                }
            }
            """
        XCTAssertEqual(try lines(of: "empty-catch", in: contents), [7])
    }

    func testRequiresDocBlocksOnPublicFunctionsAndAllowsAttributesBetween() throws {
        let contents = """
            <?php
            /**
             * Documented.
             */
            #[Pure]
            function documented() {}

            function undocumented() {}

            // A plain comment isn't a docblock.
            function commented() {}

            /** A service. */
            class Service
            {
                /** Runs. */
                #[Route('/run')]
                public function run() {}

                function implicitlyPublic() {}

                protected function guarded() {}

                private function hidden() {}

                /** @return void */

                public function gap() {}
            }

            $handler = function () {};
            """
        XCTAssertEqual(try lines(of: "missing-documentation", in: contents), [8, 11, 20, 28])
        let all = setting("missing-documentation", ["scope": .string("all")])
        XCTAssertEqual(try lines(of: "missing-documentation", in: contents, settings: all), [8, 11, 20, 22, 24, 28])
    }

    func testChecksCamelCaseFunctionsAndPascalCaseTypes() throws {
        let contents = """
            <?php
            function camelCase() {}
            function snake_case() {}
            /** A good one. */
            class GoodName
            {
                public function __construct() {}
                public function __toString(): string { return ''; }
                public function test_it_works(): void {}
                public function BadMethod(): void {}
            }
            interface bad_interface {}
            trait Loggable {}
            enum status {}
            """
        XCTAssertEqual(try messages(of: "naming-convention", in: contents), [
            "function \"snake_case\" doesn't match the expected naming convention.",
            "function \"BadMethod\" doesn't match the expected naming convention.",
            "type \"bad_interface\" doesn't match the expected naming convention.",
            "type \"status\" doesn't match the expected naming convention."
        ])
    }

    func testCountsMembersForGodClassAndMeasuresCohesion() throws {
        let limits = setting("god-class", ["maxMembers": .int(3), "maxImportsForGodClass": .int(0)])
        XCTAssertEqual(try messages(of: "god-class", in: widget, settings: limits), [])
        let contents = """
            <?php
            use A\\B;
            /** Profile. */
            class Profile
            {
                use Greets;
                private int $count = 0;
                private string $name = '', $title = '';
                // Not a member.
                public function __construct() { $this->count = 0; }
                /** Increments. */
                public function increment(): void { $this->count++; }
                /** Reads. */
                public function total(): int { return $this->count; }
                /** Renames. */
                public function rename(string $name): void { $this->name = $name; }
                /** Retitles. */
                public static function make(): self { return new self(); }
            }
            """
        XCTAssertEqual(try messages(of: "god-class", in: contents, settings: limits),
                       ["Type \"Profile\" has 8 members in a file with 1 imports."])
        XCTAssertEqual(try messages(of: "god-class", in: contents), [])
        let lcom4 = setting("lack-of-cohesion", ["maxGroups": .int(1)])
        XCTAssertEqual(try messages(of: "lack-of-cohesion", in: contents, settings: lcom4),
                       ["Type \"Profile\" splits into 2 unrelated method groups (LCOM4), over 1."])
        XCTAssertEqual(try messages(of: "lack-of-cohesion", in: contents), [])
    }

    func testCountsTheFieldsAPropertyDeclarationLists() throws {
        let contents = """
            <?php
            /** Data. */
            class Data
            {
                public int $a = 0;
                public string $b = '', $c = '';
            }
            """
        XCTAssertEqual(try lines(of: "data-class", in: contents), [3])
    }

    func testCountsUseDeclarationsAndRequiresAsImports() throws {
        let contents = """
            <?php
            use App\\One;
            use App\\{Two, Three};
            require_once __DIR__ . '/four.php';
            include 'five.php';
            """
        let limit = setting("high-coupling", ["maxImports": .int(3)])
        XCTAssertEqual(try messages(of: "high-coupling", in: contents, settings: limit),
                       ["File imports 4 modules, over the 3-import coupling threshold."])
        XCTAssertEqual(try messages(of: "high-coupling", in: contents), [])
    }

    func testMeasuresClosuresAndArrowFunctionsAsNestedFunctions() throws {
        let contents = """
            <?php
            /** Sums. */
            function sum(array $items): int
            {
                $total = array_map(function ($item) use ($items) {
                    if ($item > 0) {
                        return $item;
                    }
                    return 0;
                }, $items);
                $double = fn($x) => $x > 0 ? $x : 0;
                return array_sum($total);
            }
            """
        // The closure's two `return`s are its own: it's flagged, and `sum`, which returns once, isn't.
        XCTAssertEqual(try lines(of: "too-many-returns", in: contents,
                                 settings: setting("too-many-returns", ["maxReturns": .int(1)])), [5])
        // The closure's `if` sits one function deeper: nesting 1 + 1 = 2, plus the ternary's 1 + 1.
        XCTAssertEqual(try messages(of: "cognitive-complexity", in: contents,
                                    settings: setting("cognitive-complexity", ["max": .int(0)])).first,
                       "Function \"sum\" has cognitive complexity 4, over the 0 limit.")
        XCTAssertEqual(try lines(of: "naming-convention", in: contents), [])
    }

    func testReadsPHPCommentsForTheTextRules() throws {
        let contents = """
            <?php
            // $total = computeTotal($items, $tax);

            # $total = computeTotal($items, $tax);

            #[Attribute(Attribute::TARGET_CLASS)]

            /* $total = computeTotal($items, $tax); */
            $server = '10.20.30.40';
            """
        let commented = setting("commented-out-code")
        XCTAssertEqual(try lines(of: "commented-out-code", in: contents, settings: commented), [2, 4, 8])
        XCTAssertEqual(try lines(of: "hardcoded-ip", in: contents, settings: setting("hardcoded-ip")), [9])
    }

    // MARK: Mixed HTML

    func testParsesATemplateWithoutMeasuringItsMarkup() throws {
        let contents = """
            <!DOCTYPE html>
            <html>
            <head><title><?= htmlspecialchars($title) ?></title></head>
            <body>
            <?php foreach ($items as $item): ?>
              <li><?= $item ?></li>
            <?php endforeach; ?>
            <?php if ($footer): ?>
              <footer>Bye</footer>
            <?php endif; ?>
            <?php
            /** Renders a row. */
            function renderRow($row) { return $row; }
            ?>
            </body>
            </html>
            """
        let all = try findings(contents, file: "views/index.phtml", settings: setting("long-function", ["maxLines": .int(1)]))
        XCTAssertEqual(all.filter { $0.ruleID == "long-function" }.map(\.line), [])
        XCTAssertEqual(all.filter { $0.ruleID == "missing-documentation" }, [])
        XCTAssertEqual(try lines(of: "magic-number", in: contents, file: "views/index.phtml"), [])
        let parser = Parser()
        try parser.setLanguage(TreeSitterLanguageSpec.php.language)
        XCTAssertEqual(try XCTUnwrap(parser.parse(contents)?.rootNode).hasError, false)
        let undocumented = contents.replacingOccurrences(of: "/** Renders a row. */\n", with: "")
        XCTAssertEqual(try lines(of: "missing-documentation", in: undocumented, file: "views/index.phtml"), [12])
    }

    func testAMostlyHTMLFileKeepsItsPHPFindings() throws {
        let markup = (1...200).map { "<p class=\"row-\($0)\">Row</p>" }.joined(separator: "\n")
        let contents = markup + "\n<?php\nfunction loose() { if ($token == $input) {} }\n?>\n" + markup
        XCTAssertEqual(try lines(of: "php-loose-comparison", in: contents, file: "page.php"), [202])
        XCTAssertEqual(try lines(of: "missing-documentation", in: contents, file: "page.php"), [202])
    }

    // MARK: Tests

    func testFindsPHPUnitAndPestTestsOnlyInTestFiles() throws {
        let contents = """
            <?php
            final class WidgetTest extends TestCase
            {
                public function testAsserts(): void { $this->assertSame(1, 1); }

                public function testStatic(): void { self::assertTrue(true); }

                public function testNothing(): void { run(); }

                #[Test]
                public function marked(): void { run(); }

                /** @test */
                public function annotated(): void { run(); }

                public function testThrows(): void { $this->expectException(E::class); run(); }

                public function testCounted(): void { run(); $this->addToAssertionCount(1); }

                public function testQuiet(): void { $this->expectNotToPerformAssertions(); run(); }

                public function helper(): void { run(); }
            }

            it('expects', function () { expect(1)->toBe(1); });
            it('does nothing', function () { run(); });
            test('arrow', fn () => run());
            """
        XCTAssertEqual(try lines(of: "test-without-assertions", in: contents, file: "tests/Unit/WidgetTest.php"),
                       [8, 10, 14, 26, 27])
        XCTAssertEqual(try lines(of: "test-without-assertions", in: contents, file: "src/WidgetTest.php"),
                       [8, 10, 14, 26, 27])
        XCTAssertEqual(try lines(of: "test-without-assertions", in: contents, file: "src/Widget.php"), [])
    }

    // MARK: PHP smells

    func testFlagsDebugOutputOutsideTests() throws {
        let contents = """
            <?php
            var_dump($a);
            \\var_dump($a);
            print_r($a);
            print_r($a, false);
            $s = print_r($a, true);
            dd($a);
            dump($a);
            $collection->dump();
            Debug::dump($a);
            Other\\var_dump($a);
            """
        XCTAssertEqual(try lines(of: "php-debug-output", in: contents), [2, 3, 4, 5, 7, 8])
        XCTAssertEqual(try messages(of: "php-debug-output", in: contents).first,
                       "Remove var_dump() debug output, or log it instead.")
        XCTAssertEqual(try lines(of: "php-debug-output", in: contents, file: "tests/Feature/WidgetTest.php"), [])
        XCTAssertEqual(try lines(of: "php-debug-output", in: contents, file: "test/helpers.php"), [])
    }

    func testLeavesDebugOutputCapturedByAnOutputBuffer() throws {
        let contents = """
            <?php
            function describe($event) {
                var_dump($event);
                ob_start();
                var_dump($event);
                return ob_get_clean();
            }
            function other($event) {
                var_dump($event);
            }
            """
        XCTAssertEqual(try lines(of: "php-debug-output", in: contents), [3, 9])
    }

    func testFlagsEvalAndCreateFunction() throws {
        let contents = """
            <?php
            eval('$x = 1;');
            $f = create_function('$a', 'return $a;');
            $g = evaluate('x');
            $this->eval('x');
            """
        XCTAssertEqual(try lines(of: "php-eval", in: contents), [2, 3])
        XCTAssertEqual(try lines(of: "php-eval", in: contents, file: "tests/EvalTest.php"), [2, 3])
    }

    func testFlagsErrorSuppression() throws {
        let contents = """
            <?php
            $data = @file_get_contents($path);
            $ok = file_exists($path) ? 1 : 0;
            """
        XCTAssertEqual(try lines(of: "php-error-suppression", in: contents), [2])
    }

    func testLetsAMkdirThatTheSameConditionChecksWithIsDirSuppressItsWarning() throws {
        let contents = """
            <?php
            if (!@mkdir($dir, 0777, true) && !is_dir($dir)) { throw new RuntimeException($dir); }
            if (!(@mkdir($dir)) && !is_dir($dir)) { return; }
            $made = @mkdir($dir) || is_dir($dir);
            if (!@mkdir($dir)) { return; }
            @mkdir($dir);
            if (!@rmdir($dir) && !is_dir($dir)) { return; }
            """
        XCTAssertEqual(try lines(of: "php-error-suppression", in: contents), [5, 6, 7])
    }

    func testFlagsExtractOfSuperglobalsOnly() throws {
        let contents = """
            <?php
            extract($_GET);
            extract($_POST, EXTR_SKIP);
            extract($_REQUEST);
            extract($row);
            extract(['a' => 1]);
            """
        XCTAssertEqual(try lines(of: "php-extract", in: contents), [2, 3, 4])
    }

    func testFlagsLooseComparisonOfSecrets() throws {
        let contents = """
            <?php
            if ($token == $input) {}
            if ($user->passwordHash != $given) {}
            if (hash_hmac('sha256', $body, $key) == $signature) {}
            if ($request->getNonce() <> $nonce) {}
            if ($token === $input) {}
            if (hash_equals($token, $input)) {}
            if ($count == $total) {}
            if ($token == null) {}
            if ($_POST['csrf_token'] == $expected) {}
            """
        XCTAssertEqual(try lines(of: "php-loose-comparison", in: contents), [2, 3, 4, 5, 10])
    }

    func testRuleSettingsCanTurnASmellOff() throws {
        let off = ["php-eval": RuleSettings(enabled: false, severity: .warning, parameters: RuleParameters(values: [:]))]
        XCTAssertEqual(try lines(of: "php-eval", in: "<?php\neval('1');\n", settings: off), [])
    }
}

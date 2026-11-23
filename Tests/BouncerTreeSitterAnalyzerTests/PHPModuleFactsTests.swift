import XCTest
import Foundation
import BouncerCore
@testable import BouncerTreeSitterAnalyzer

final class PHPModuleFactsTests: XCTestCase {
    private func facts(_ contents: String, path: String = "/repo/src/Http/Controller.php") throws -> ModuleFacts {
        let file = SourceFile(path: URL(fileURLWithPath: path), language: .php, contents: contents)
        return try XCTUnwrap(try TreeSitterAnalyzer(spec: .php).moduleFacts(file: file))
    }

    func testRecordsSimpleAliasedGroupedFunctionAndConstUses() throws {
        let contents = """
            <?php
            declare(strict_types=1);
            namespace App\\Http;

            use App\\Models\\User;
            use \\App\\Models\\Post as P, Vendor\\Lib\\Client;
            use App\\{Support\\Clock, Bar\\Baz as Q};
            use function App\\Support\\helper;
            use const App\\Support\\LIMIT;
            use function App\\Fns\\{first, second};
            use App\\Mixed\\{function third, const FOURTH, Klass};
            """
        let imports = try facts(contents).imports
        XCTAssertEqual(imports.map(\.specifier), [
            "App\\Models\\User", "App\\Models\\Post", "Vendor\\Lib\\Client", "App\\Support\\Clock", "App\\Bar\\Baz",
            "function App\\Support\\helper", "const App\\Support\\LIMIT", "function App\\Fns\\first",
            "function App\\Fns\\second", "function App\\Mixed\\third", "const App\\Mixed\\FOURTH", "App\\Mixed\\Klass"
        ])
        XCTAssertEqual(imports.prefix(5).map(\.names), [["User"], ["P"], ["Client"], ["Clock"], ["Q"]])
        XCTAssertEqual(imports.first?.line, 5)
    }

    func testRecordsLiteralInclusionsAndSkipsComputedPaths() throws {
        let contents = """
            <?php
            require_once __DIR__ . '/bootstrap.php';
            include 'lib/helpers.php';
            require dirname(__FILE__) . "/config.php";
            require(__DIR__ . "/../shared/db.php");
            include_once "views/$name.php";
            require $path;
            require BASE . '/x.php';
            """
        XCTAssertEqual(try facts(contents).imports.map(\.specifier), [
            "require __DIR__/bootstrap.php", "require lib/helpers.php", "require __DIR__/config.php",
            "require __DIR__/../shared/db.php"
        ])
    }

    func testExportsDeclarationsAndRecordsStructure() throws {
        let contents = """
            <?php
            namespace App\\Models;

            abstract class Model {}
            final class User extends Model implements \\JsonSerializable, Arrayable {
                use HasNames;
                private ?string $name = null;
                public function __construct(private int $id, string ...$tags) {}
                public function jsonSerialize(): mixed { return []; }
            }
            interface Arrayable { public function toArray(): array; }
            trait HasNames { function names() { function inner() {} } }
            enum Role: string { case Admin = 'admin'; }
            if (!function_exists('helper')) { function helper($value) {} }
            """
        let module = try facts(contents)
        XCTAssertEqual(module.exports.map(\.name), ["Model", "User", "Arrayable", "HasNames", "Role", "helper"])
        XCTAssertEqual(module.exports.first?.line, 4)
        let types = module.structure.types
        XCTAssertEqual(types.map(\.kind), [.abstractClass, .class, .interface, .other, .enum])
        XCTAssertEqual(types[1].supertypes, ["Model", "\\JsonSerializable", "Arrayable"])
        XCTAssertEqual(types[1].fields, ["name:?string"])
        XCTAssertEqual(types[1].methods, ["__construct", "jsonSerialize"])
        let functions = module.structure.functions.map { "\($0.owner ?? "-").\($0.name)(\($0.parameters.joined(separator: ",")))" }
        XCTAssertEqual(functions, ["User.User.init(id,tags)", "User.jsonSerialize()", "HasNames.names()", "-.inner()",
                                   "-.helper(value)"])
    }

    func testReadsPHPMixedWithHTML() throws {
        let contents = """
            <!doctype html>
            <html>
            <?php use App\\View\\Layout; require __DIR__ . '/partials/head.phtml'; ?>
            <body class="<?= $class ?>">
            <p>use Not\\An\\Import; require 'not-php.php';</p>
            <?php function render(Layout $layout): string { return ''; } ?>
            </body>
            </html>
            """
        let module = try facts(contents, path: "/repo/templates/page.phtml")
        XCTAssertEqual(module.imports.map(\.specifier), ["App\\View\\Layout", "require __DIR__/partials/head.phtml"])
        XCTAssertEqual(module.imports.map(\.line), [3, 3])
        XCTAssertEqual(module.exports.map(\.name), ["render"])
    }
}

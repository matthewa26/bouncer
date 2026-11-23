import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

/// The PHP spellings of the security patterns, run on `.php` files through the text-rule registry.
final class PHPSecurityPatternTests: OWASPRuleTestCase {
    private let path = "/repo/src/app.php"

    private func flags(_ contents: String, _ rule: String, _ expected: [Int],
                       file: StaticString = #filePath, line: UInt = #line) {
        assertFlags(contents, .php, rule, expected, path: path, file: file, line: line)
    }

    private func clean(_ contents: String, _ rule: String, file: StaticString = #filePath, line: UInt = #line) {
        assertClean(contents, .php, rule, path: path, file: file, line: line)
    }

    // MARK: sql-string-building

    func testFlagsSQLBuiltFromVariablesAndSuperglobals() {
        flags("<?php\n$sql = \"SELECT * FROM users WHERE id = $id\";\n", "sql-string-building", [2])
        flags("<?php\n$sql = 'SELECT * FROM users WHERE id = ' . $_GET['id'];\n", "sql-string-building", [2])
        flags("<?php\n$r = mysqli_query($db, \"DELETE FROM t WHERE id = {$row['id']}\");\n", "sql-string-building", [2])
        flags("<?php\n$r = $pdo->query('SELECT name FROM t WHERE id = ' . $id);\n", "sql-string-building", [2])
        flags("<?php\n$r = pg_query($conn, $_POST['q']);\n", "sql-string-building", [2])
        flags("<?php\n$pdo->exec(\"UPDATE users SET name = '$name'\");\n", "sql-string-building", [2])
    }

    func testSkipsPreparedStatementsAndComments() {
        clean("<?php\n$st = $pdo->prepare('SELECT * FROM users WHERE id = ?');\n$st->execute([$id]);\n",
              "sql-string-building")
        clean("<?php\n$r = $pdo->query(\"SELECT * FROM users WHERE id = ?\");\n", "sql-string-building")
        clean("<?php\n// $sql = \"SELECT * FROM users WHERE id = $id\";\n", "sql-string-building")
        clean("<?php\n$sql = 'SELECT * FROM t WHERE id = ' . $pdo->quote($id);\n", "sql-string-building")
    }

    // MARK: php-shell-injection

    func testFlagsShellCallsAndBackticksWithVariables() {
        flags("<?php\nexec('ls ' . $dir, $out);\n", "php-shell-injection", [2])
        flags("<?php\n$o = shell_exec(\"git log $ref\");\n", "php-shell-injection", [2])
        flags("<?php\nsystem($_GET['cmd']);\n", "php-shell-injection", [2])
        flags("<?php\npassthru($cmd);\n$p = proc_open($cmd, $spec, $pipes);\n$h = popen($cmd, 'r');\n",
              "php-shell-injection", [2, 3, 4])
        flags("<?php\n$o = `ls $dir`;\n", "php-shell-injection", [2])
    }

    func testSkipsEscapedArgumentsLiteralsMethodsAndQuotedBackticks() {
        clean("<?php\nexec('ls ' . escapeshellarg($dir), $out);\n", "php-shell-injection")
        clean("<?php\nexec('ls -la', $out);\nsystem('uptime');\n", "php-shell-injection")
        clean("<?php\n$stmt->exec($sql);\n", "php-shell-injection")
        clean("<?php\n$q = \"SELECT `name` FROM `$table`\";\n", "php-shell-injection")
    }

    // MARK: path-traversal

    func testFlagsIncludesOfAVariablePath() {
        flags("<?php\ninclude $page;\n", "path-traversal", [2])
        flags("<?php\nrequire_once \"views/$view.php\";\n", "path-traversal", [2])
        flags("<?php\n$config = require $dir . '/config.php';\n", "path-traversal", [2])
        flags("<?php\ninclude($_GET['page'] . '.php');\n", "path-traversal", [2])
    }

    func testSkipsLiteralIncludePaths() {
        clean("<?php\nrequire __DIR__ . '/../vendor/autoload.php';\ninclude_once 'header.php';\n", "path-traversal")
        clean("<?php\n// include $page;\n$msg = \"Please include $name\";\n", "path-traversal")
    }

    // MARK: unsafe-deserialization

    func testFlagsUnserializeOfInput() {
        flags("<?php\n$data = unserialize($_COOKIE['cart']);\n", "unsafe-deserialization", [2])
        flags("<?php\n$data = unserialize(base64_decode($payload));\n", "unsafe-deserialization", [2])
    }

    func testSkipsUnserializeWithAllowedClasses() {
        clean("<?php\n$data = unserialize($payload, ['allowed_classes' => false]);\n", "unsafe-deserialization")
        clean("<?php\n$data = unserialize($payload, ['allowed_classes' => [Cart::class]]);\n", "unsafe-deserialization")
        clean("<?php\n$data = $serializer->unserialize($payload);\n", "unsafe-deserialization")
    }

    // MARK: php-weak-password-hash and weak-crypto

    func testFlagsMD5AndSHA1OnPasswordsOnlyOnce() {
        let contents = "<?php\n$hash = md5($password);\n$stored = sha1($_POST['passwd']);\n"
            + "$passwordHash = hash('md5', $plain);\n"
        flags(contents, "php-weak-password-hash", [2, 3, 4])
        clean(contents, "weak-crypto")
    }

    func testLeavesOtherHashesToWeakCryptoAndPasswordHashAlone() {
        let contents = "<?php\n$key = sha1($request->getHeader('Sec-WebSocket-Key'));\n$etag = md5($body);\n"
        clean(contents, "php-weak-password-hash")
        flags(contents, "weak-crypto", [2, 3])
        clean("<?php\n$hash = password_hash($password, PASSWORD_DEFAULT);\n", "php-weak-password-hash")
        clean("<?php\n$hash = password_hash($password, PASSWORD_DEFAULT);\n", "weak-crypto")
    }

    // MARK: debug-mode-enabled

    func testFlagsDisplayErrorsSwitchedOn() {
        flags("<?php\nini_set('display_errors', '1');\nini_set(\"display_errors\", 'On');\n",
              "debug-mode-enabled", [2, 3])
    }

    func testSkipsDisplayErrorsOffAndTests() {
        clean("<?php\nini_set('display_errors', '0');\nini_set('display_errors', 'Off');\n", "debug-mode-enabled")
        assertClean("<?php\nini_set('display_errors', '1');\n", .php, "debug-mode-enabled",
                    path: "/repo/tests/BootTest.php")
    }

    // MARK: disabled-tls-verification

    func testFlagsTLSVerificationSwitchedOff() {
        let contents = "<?php\ncurl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);\ncurl_setopt_array($ch, [\n"
            + "    CURLOPT_SSL_VERIFYPEER => 0,\n    CURLOPT_SSL_VERIFYHOST => 0,\n]);\n"
            + "$client = new Client(['verify' => false]);\n"
        flags(contents, "disabled-tls-verification", [2, 4, 5, 7])
    }

    func testSkipsTLSVerificationSwitchedOn() {
        let contents = "<?php\ncurl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);\n"
            + "curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 2);\n$client = new Client(['verify' => true]);\n"
        clean(contents, "disabled-tls-verification")
    }

    // MARK: profile

    func testRegistersThePHPProfileForTheHeuristicFallback() {
        let profile = LanguageProfiles.profile(for: .php)
        XCTAssertEqual(profile.lineCommentPrefixes, ["//", "#"])
        XCTAssertNotNil(profile.functionStartPattern)
        XCTAssertTrue(profile.extraPatternRules.contains { $0.id == "php-shell-injection" })
    }

    func testEveryPHPPatternAndWeakCryptoCompile() {
        let specs = LanguageProfiles.profile(for: .php).extraPatternRules + UniversalPatterns.specs
        for spec in specs {
            XCTAssertNotNil(PatternRule(spec: spec), spec.id)
        }
    }
}

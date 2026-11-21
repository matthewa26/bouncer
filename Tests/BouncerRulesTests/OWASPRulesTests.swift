import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

/// Shared helper for the OWASP rule tests: the lines a rule flags in a snippet.
class OWASPRuleTestCase: XCTestCase {
    private let context = AnalysisContext(repoRoot: URL(fileURLWithPath: "/repo"), ruleSettings: [:])

    func lines(_ contents: String, _ language: Language, rule: String, path: String = "/repo/src/app") -> [Int] {
        let file = SourceFile(path: URL(fileURLWithPath: path), language: language, contents: contents)
        return TextRules.make(profile: LanguageProfiles.profile(for: language))
            .filter { $0.id == rule }
            .flatMap { $0.evaluate(file: file, context: context) }
            .map(\.line)
    }

    func assertFlags(_ contents: String, _ language: Language, _ rule: String, _ expected: [Int],
                     path: String = "/repo/src/app", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lines(contents, language, rule: rule, path: path), expected, "\(language)",
                       file: file, line: line)
    }

    func assertClean(_ contents: String, _ language: Language, _ rule: String, path: String = "/repo/src/app",
                     file: StaticString = #filePath, line: UInt = #line) {
        assertFlags(contents, language, rule, [], path: path, file: file, line: line)
    }
}

final class OWASPMisconfigurationRulesTests: OWASPRuleTestCase {
    // MARK: debug-mode-enabled

    func testFlagsDebugModeInFlaskDjangoAndExpress() {
        assertFlags("app = Flask(__name__)\napp.run(host='0.0.0.0', debug=True)\n", .python, "debug-mode-enabled", [2])
        assertFlags("SECRET = 'x'\nDEBUG = True\n", .python, "debug-mode-enabled", [2], path: "/repo/site/settings.py")
        assertFlags("DEBUG = True\n", .python, "debug-mode-enabled", [1], path: "/repo/site/settings/prod.py")
        assertFlags("app.config['DEBUG'] = True\n", .python, "debug-mode-enabled", [1])
        assertFlags("const app = express();\napp.set('env', 'development');\n", .javascript, "debug-mode-enabled", [2])
    }

    func testSkipsDebugOffDebugOutsideSettingsAndComments() {
        assertClean("app.run(debug=False)\n# app.run(debug=True)\n", .python, "debug-mode-enabled")
        assertClean("DEBUG = True\n", .python, "debug-mode-enabled", path: "/repo/tools/build.py")
        assertClean("app.set('env', process.env.NODE_ENV);\n", .typescript, "debug-mode-enabled")
        assertClean("app.run(debug=True)\n", .python, "debug-mode-enabled", path: "/repo/tests/test_app.py")
    }

    // MARK: permissive-cors and cors-credentials-any-origin

    func testFlagsAnyOriginCORSInEveryLanguage() {
        assertFlags("app.use(cors());\n", .javascript, "permissive-cors", [1])
        assertFlags("res.setHeader('Access-Control-Allow-Origin', '*');\n", .typescript, "permissive-cors", [1])
        assertFlags("app.use(cors({\n  origin: '*',\n}));\n", .typescript, "permissive-cors", [2])
        assertFlags("CORS(app)\n", .python, "permissive-cors", [1])
        assertFlags("CORS_ALLOW_ALL_ORIGINS = True\n", .python, "permissive-cors", [1])
        assertFlags("c := cors.New(cors.Options{\n\tAllowedOrigins: []string{\"*\"},\n})\n", .go, "permissive-cors", [2])
        assertFlags("w.Header().Set(\"Access-Control-Allow-Origin\", \"*\")\n", .go, "permissive-cors", [1])
        assertFlags("@CrossOrigin\n@GetMapping(\"/a\")\n", .java, "permissive-cors", [1])
        assertFlags("registry.addMapping(\"/**\").allowedOrigins(\"*\");\n", .java, "permissive-cors", [1])
        assertFlags("let cors = CORSMiddleware.Configuration(allowedOrigin: .all, allowedMethods: [.GET])\n", .swift,
                    "permissive-cors", [1])
        assertFlags("[response setValue:@\"*\" forHTTPHeaderField:@\"Access-Control-Allow-Origin\"];\n", .objc,
                    "permissive-cors", [1])
    }

    func testSkipsListedOriginsAndCredentialedFiles() {
        assertClean("app.use(cors({ origin: ['https://a.example'] }));\n", .javascript, "permissive-cors")
        assertClean("CORS(app, origins=['https://a.example'])\n", .python, "permissive-cors")
        assertClean("w.Header().Set(\"Access-Control-Allow-Origin\", origin)\n", .go, "permissive-cors")
        assertClean("@CrossOrigin(origins = \"https://a.example\")\n", .java, "permissive-cors")
        let credentialed = "app.use(cors({ origin: true, credentials: true }));\n"
        assertClean(credentialed, .javascript, "permissive-cors")
        assertFlags(credentialed, .javascript, "cors-credentials-any-origin", [1])
    }

    func testFlagsAnyOriginWithCredentials() {
        assertFlags("CORS(app, origins='*', supports_credentials=True)\n", .python, "cors-credentials-any-origin", [1])
        let go = "cors.New(cors.Options{\n\tAllowedOrigins: []string{\"*\"},\n\tAllowCredentials: true,\n})\n"
        assertFlags(go, .go, "cors-credentials-any-origin", [2])
        let java = "config.addAllowedOrigin(\"*\");\nconfig.setAllowCredentials(true);\n"
        assertFlags(java, .java, "cors-credentials-any-origin", [1])
        let swift = "CORSMiddleware.Configuration(allowedOrigin: .originBased, allowCredentials: true)\n"
        assertFlags(swift, .swift, "cors-credentials-any-origin", [1])
        let objc = "[r setValue:@\"*\" forHTTPHeaderField:@\"Access-Control-Allow-Origin\"];\n"
            + "[r setValue:@\"true\" forHTTPHeaderField:@\"Access-Control-Allow-Credentials\"];\n"
        assertFlags(objc, .objc, "cors-credentials-any-origin", [1])
        let ts = "res.header('Access-Control-Allow-Origin', '*');\nres.header('Access-Control-Allow-Credentials', 'true');\n"
        assertFlags(ts, .typescript, "cors-credentials-any-origin", [1])
    }

    func testSkipsCredentialsWithListedOrigins() {
        assertClean("app.use(cors({ origin: 'https://a.example', credentials: true }));\n", .javascript,
                    "cors-credentials-any-origin")
        assertClean("CORS(app, origins=['https://a'], supports_credentials=True)\n", .python,
                    "cors-credentials-any-origin")
        assertClean("AllowedOrigins: []string{\"https://a\"},\nAllowCredentials: true,\n", .go,
                    "cors-credentials-any-origin")
    }

    // MARK: insecure-cookie

    func testFlagsCookiesWithoutSecureOrHttpOnly() {
        assertFlags("app.use(session({\n  cookie: {\n    secure: false,\n  },\n}));\n", .javascript, "insecure-cookie", [3])
        assertFlags("res.cookie('sid', id, { httpOnly: false });\n", .typescript, "insecure-cookie", [1])
        assertFlags("resp.set_cookie('sid', sid, secure=False)\n", .python, "insecure-cookie", [1])
        assertFlags("SESSION_COOKIE_SECURE = False\n", .python, "insecure-cookie", [1])
        assertFlags("http.SetCookie(w, &http.Cookie{\n\tName: \"sid\",\n\tHttpOnly: false,\n})\n", .go,
                    "insecure-cookie", [3])
        assertFlags("Cookie cookie = new Cookie(\"sid\", id);\ncookie.setSecure(false);\n", .java, "insecure-cookie", [2])
        assertFlags("let cookie = HTTPCookies.Value(string: id, isSecure: false)\n", .swift, "insecure-cookie", [1])
    }

    func testSkipsSecureCookiesAndUnrelatedSecureFlags() {
        assertClean("nodemailer.createTransport({ host, port: 587, secure: false });\n", .javascript, "insecure-cookie")
        assertClean("res.cookie('sid', id, { httpOnly: true, secure: true });\n", .javascript, "insecure-cookie")
        assertClean("resp.set_cookie('sid', sid, secure=True, httponly=True)\n", .python, "insecure-cookie")
        assertClean("tls := &tls.Config{\n\tSecure: false,\n}\n", .go, "insecure-cookie")
        assertClean("conn.setSecure(false);\n", .java, "insecure-cookie")
        assertClean("let c = HTTPCookies.Value(string: id, isSecure: true)\n", .swift, "insecure-cookie")
    }

    // MARK: xml-external-entities

    func testFlagsParsersThatResolveExternalEntities() {
        assertFlags("const doc = libxmljs.parseXml(xml, { noent: true });\n", .javascript, "xml-external-entities", [1])
        assertFlags("parser = etree.XMLParser(resolve_entities=True)\n", .python, "xml-external-entities", [1])
        let java = "f.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, true);\n"
            + "dbf.setExpandEntityReferences(true);\n"
            + "dbf.setFeature(\"http://apache.org/xml/features/disallow-doctype-decl\", false);\n"
        assertFlags(java, .java, "xml-external-entities", [1, 2, 3])
        assertFlags("parser.shouldResolveExternalEntities = true\n", .swift, "xml-external-entities", [1])
        assertFlags("[parser setShouldResolveExternalEntities:YES];\n", .objc, "xml-external-entities", [1])
    }

    func testSkipsParsersWithEntitiesOff() {
        assertClean("libxmljs.parseXml(xml, { noent: false });\n", .javascript, "xml-external-entities")
        assertClean("etree.XMLParser(resolve_entities=False)\n", .python, "xml-external-entities")
        assertClean("f.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, false);\n", .java,
                    "xml-external-entities")
        assertClean("parser.shouldResolveExternalEntities = false\n", .swift, "xml-external-entities")
        assertClean("[parser setShouldResolveExternalEntities:NO];\n", .objc, "xml-external-entities")
    }
}

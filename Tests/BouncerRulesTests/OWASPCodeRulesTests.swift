import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class OWASPCryptoRulesTests: OWASPRuleTestCase {
    // MARK: hardcoded-iv

    func testFlagsLiteralIVsNoncesAndSalts() {
        assertFlags("iv = b\"0123456789abcdef\"\ncipher = AES.new(key, AES.MODE_CBC, b\"fixedfixedfixed!\")\n", .python,
                    "hardcoded-iv", [1, 2])
        assertFlags("dk = hashlib.pbkdf2_hmac('sha256', pw, salt=b'NaCl', iterations=1)\n", .python, "hardcoded-iv", [1])
        assertFlags("const iv = Buffer.from('a1b2c3d4e5f6a7b8');\n", .javascript, "hardcoded-iv", [1])
        assertFlags("crypto.createCipheriv('aes-256-cbc', key, Buffer.alloc(16));\n", .typescript, "hardcoded-iv", [1])
        assertFlags("let iv: [UInt8] = [0x00, 0x01, 0x02, 0x03]\n", .swift, "hardcoded-iv", [1])
        assertFlags("let nonce = try AES.GCM.Nonce(data: Data([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]))\n", .swift,
                    "hardcoded-iv", [1])
        assertFlags("nonce := []byte(\"unique-nonce\")\n", .go, "hardcoded-iv", [1])
        assertFlags("Cipher c = init(new IvParameterSpec(\"0000000000000000\".getBytes()));\n", .java, "hardcoded-iv", [1])
        assertFlags("byte[] iv = new byte[] { 1, 2, 3, 4 };\nspec = new IvParameterSpec(new byte[16]);\n", .java,
                    "hardcoded-iv", [1, 2])
        assertFlags("unsigned char iv[16] = { 0x01, 0x02 };\n", .objc, "hardcoded-iv", [1])
        assertFlags("NSData *kIV = [@\"abcdefghijklmnop\" dataUsingEncoding:NSUTF8StringEncoding];\n", .objc,
                    "hardcoded-iv", [1])
    }

    func testSkipsRandomIVsSaltNamespacesAndLookalikeNames() {
        assertClean("iv = os.urandom(16)\nsigner = Signer(key, salt='app.email')\n", .python, "hardcoded-iv")
        assertClean("const iv = crypto.randomBytes(16);\nconst saltRounds = 10;\nconst div = 'x';\n", .javascript,
                    "hardcoded-iv")
        assertClean("var iv = [UInt8](repeating: 0, count: 16)\nSecRandomCopyBytes(kSecRandomDefault, 16, &iv)\n",
                    .swift, "hardcoded-iv")
        assertClean("nonce := make([]byte, gcm.NonceSize())\nio.ReadFull(rand.Reader, nonce)\n", .go, "hardcoded-iv")
        assertClean("byte[] iv = new byte[16];\nrandom.nextBytes(iv);\n", .java, "hardcoded-iv")
        assertClean("uint8_t iv[16] = {0};\nSecRandomCopyBytes(kSecRandomDefault, 16, iv);\n", .objc, "hardcoded-iv")
    }

    // MARK: short-crypto-key

    func testFlagsShortRSAKeysAndSmallCurves() {
        assertFlags("generateKeyPairSync('rsa', { modulusLength: 1024 });\n", .javascript, "short-crypto-key", [1])
        assertFlags("crypto.generateKeyPairSync('ec', { namedCurve: 'secp192r1' });\n", .typescript, "short-crypto-key", [1])
        assertFlags("from cryptography.hazmat.primitives.asymmetric import rsa\n"
                    + "k = rsa.generate_private_key(public_exponent=65537, key_size=1024)\n", .python,
                    "short-crypto-key", [2])
        assertFlags("key, _ := rsa.GenerateKey(rand.Reader, 1024)\n", .go, "short-crypto-key", [1])
        assertFlags("KeyPairGenerator g = KeyPairGenerator.getInstance(\"RSA\");\ng.initialize(1024);\n", .java,
                    "short-crypto-key", [2])
        assertFlags("let attrs: [String: Any] = [kSecAttrKeySizeInBits as String: 1024]\n", .swift, "short-crypto-key", [1])
        assertFlags("NSDictionary *a = @{ (id)kSecAttrKeySizeInBits: @1024 };\n", .objc, "short-crypto-key", [1])
    }

    func testSkipsStrongKeys() {
        assertClean("generateKeyPairSync('rsa', { modulusLength: 4096 });\n", .javascript, "short-crypto-key")
        assertClean("import rsa\nrsa.generate_private_key(public_exponent=65537, key_size=2048)\n", .python,
                    "short-crypto-key")
        assertClean("rsa.GenerateKey(rand.Reader, 2048)\n", .go, "short-crypto-key")
        assertClean("pool.initialize(1024);\n", .java, "short-crypto-key")
        assertClean("let attrs = [kSecAttrKeySizeInBits as String: 256]\n", .swift, "short-crypto-key")
        assertClean("NSDictionary *a = @{ (id)kSecAttrKeySizeInBits: @2048 };\n", .objc, "short-crypto-key")
    }
}

final class OWASPInjectionRulesTests: OWASPRuleTestCase {
    // MARK: objc-shell-injection

    func testFlagsObjectiveCShellCommandsBuiltFromFormats() {
        assertFlags("system([[NSString stringWithFormat:@\"rm %@\", path] UTF8String]);\n", .objc,
                    "objc-shell-injection", [1])
        assertFlags("[NSTask launchedTaskWithLaunchPath:@\"/bin/sh\" arguments:@[@\"-c\", [NSString "
                    + "stringWithFormat:@\"ls %@\", dir]]];\n", .objc, "objc-shell-injection", [1])
        let task = "task.launchPath = @\"/bin/bash\";\ntask.arguments = @[@\"-c\", [NSString stringWithFormat:@\"x %@\", y]];\n"
        assertFlags(task, .objc, "objc-shell-injection", [2])
    }

    func testSkipsFixedCommandsAndDirectArguments() {
        assertClean("system(\"ls -l\");\n", .objc, "objc-shell-injection")
        assertClean("task.launchPath = @\"/usr/bin/git\";\ntask.arguments = @[@\"log\", ref];\n", .objc,
                    "objc-shell-injection")
        assertClean("system([[NSString stringWithFormat:@\"rm %@\", p] UTF8String]);\n", .c, "objc-shell-injection")
    }

    // MARK: nosql-injection

    func testFlagsRequestObjectsAndBuiltWhereClauses() {
        let js = "const mongoose = require('mongoose');\nUser.findOne({ email: req.body.email, pass: req.body.pass });\n"
            + "db.collection('u').find({ $where: 'this.age > ' + age });\n"
        assertFlags(js, .javascript, "nosql-injection", [2, 3])
        assertFlags("from pymongo import MongoClient\nusers.find_one(request.json)\n", .python, "nosql-injection", [2])
        assertFlags("import \"go.mongodb.org/mongo-driver/bson\"\nf := bson.M{\"$where\": \"this.a == \" + a}\n", .go,
                    "nosql-injection", [2])
        assertFlags("import com.mongodb.BasicDBObject;\nq = new BasicDBObject(\"$where\", \"this.a == \" + a);\n",
                    .java, "nosql-injection", [2])
    }

    func testSkipsCastValuesSanitizedAppsAndOtherFiles() {
        assertClean("const mongoose = require('mongoose');\nUser.findOne({ email: String(req.body.email) });\n",
                    .javascript, "nosql-injection")
        assertClean("const mongoSanitize = require('express-mongo-sanitize');\nUser.find({ a: req.body.a });\n",
                    .javascript, "nosql-injection")
        assertClean("items.find({ a: req.body.a });\n", .typescript, "nosql-injection")
        assertClean("import pymongo\nusers.find_one({'_id': user_id})\n", .python, "nosql-injection")
    }

    // MARK: template-injection

    func testFlagsRequestInputCompiledAsATemplate() {
        let flask = "from flask import request, render_template_string\nname = request.args.get('n')\n"
            + "return render_template_string('Hello ' + name)\n"
        assertFlags(flask, .python, "template-injection", [3])
        assertFlags("return render_template_string(f\"<h1>{title}</h1>\")\n", .python, "template-injection", [1])
        assertFlags("const html = ejs.render(req.body.template, {});\n", .javascript, "template-injection", [1])
        assertFlags("const t = Handlebars.compile(`<p>${req.query.msg}</p>`);\n", .typescript, "template-injection", [1])
        let go = "tpl := r.URL.Query().Get(\"t\")\nt, _ := template.New(\"x\").Parse(tpl)\n"
        assertFlags(go, .go, "template-injection", [2])
    }

    func testSkipsFixedTemplatesGivenInputAsData() {
        assertClean("from flask import request\nreturn render_template_string('Hello {{ n }}', n=request.args['n'])\n",
                    .python, "template-injection")
        assertClean("const html = ejs.render(TEMPLATE, { msg: req.query.msg });\n", .javascript, "template-injection")
        assertClean("t := template.Must(template.New(\"x\").Parse(page))\n", .go, "template-injection")
    }
}

final class OWASPAuthAndIntegrityRulesTests: OWASPRuleTestCase {
    // MARK: jwt-verification-disabled

    func testFlagsDisabledJWTChecks() {
        assertFlags("import jwt\nclaims = jwt.decode(token, verify=False)\n", .python, "jwt-verification-disabled", [2])
        assertFlags("import jwt\njwt.decode(t, key, options={\"verify_signature\": False})\n", .python,
                    "jwt-verification-disabled", [2])
        assertFlags("jwt.verify(token, key, { algorithms: ['HS256', 'none'] });\n", .javascript,
                    "jwt-verification-disabled", [1])
        assertFlags("const jwt = require('jsonwebtoken');\njwt.verify(t, k, { ignoreExpiration: true });\n",
                    .typescript, "jwt-verification-disabled", [2])
        assertFlags("import \"github.com/golang-jwt/jwt/v5\"\nreturn jwt.UnsafeAllowNoneSignatureType, nil\n", .go,
                    "jwt-verification-disabled", [2])
        assertFlags("import io.jsonwebtoken.Jwts;\nJwts.parser().parseClaimsJwt(token);\n", .java,
                    "jwt-verification-disabled", [2])
    }

    func testSkipsVerifiedJWTs() {
        assertClean("import jwt\njwt.decode(token, key, algorithms=['HS256'])\n", .python, "jwt-verification-disabled")
        assertClean("jwt.verify(token, key, { algorithms: ['RS256'] });\n", .javascript, "jwt-verification-disabled")
        assertClean("import jwt\nt, err := jwt.Parse(s, keyFunc)\n", .go, "jwt-verification-disabled")
        assertClean("import io.jsonwebtoken.Jwts;\nJwts.parser().verifyWith(key).build().parseSignedClaims(t);\n",
                    .java, "jwt-verification-disabled")
    }

    // MARK: unsafe-deserialization

    func testFlagsObjectDeserializers() {
        let java = "ObjectInputStream in = new ObjectInputStream(socket.getInputStream());\nObject o = in.readObject();\n"
        assertFlags(java, .java, "unsafe-deserialization", [1])
        assertFlags("XMLDecoder d = new XMLDecoder(stream);\n", .java, "unsafe-deserialization", [1])
        assertFlags("const serialize = require('node-serialize');\nserialize.unserialize(req.cookies.p);\n",
                    .javascript, "unsafe-deserialization", [2])
        assertFlags("let obj = NSKeyedUnarchiver.unarchiveObject(with: data)\n", .swift, "unsafe-deserialization", [1])
        assertFlags("id obj = [NSKeyedUnarchiver unarchiveObjectWithData:data];\n", .objc, "unsafe-deserialization", [1])
    }

    func testSkipsSecureDecodingAndFilteredStreams() {
        let java = "in.setObjectInputFilter(filter);\nObjectInputStream in = new ObjectInputStream(s);\nin.readObject();\n"
        assertClean(java, .java, "unsafe-deserialization")
        assertClean("const v = JSON.parse(body);\nx.unserialize(y);\n", .javascript, "unsafe-deserialization")
        assertClean("let obj = try NSKeyedUnarchiver.unarchivedObject(ofClass: Note.self, from: data)\n", .swift,
                    "unsafe-deserialization")
        assertClean("id o = [NSKeyedUnarchiver unarchivedObjectOfClass:[Note class] fromData:d error:&e];\n", .objc,
                    "unsafe-deserialization")
    }

    func testPythonDeserializationStaysWithItsOwnRule() {
        let source = "import yaml, dill\nyaml.unsafe_load(s)\ndill.loads(b)\npickle.loads(b)\n"
        XCTAssertEqual(lines(source, .python, rule: "python-unsafe-deserialization"), [2, 3, 4])
        assertClean(source, .python, "unsafe-deserialization")
    }

    // MARK: timing-unsafe-comparison

    func testFlagsSecretsComparedWithOrdinaryEquality() {
        assertFlags("import hmac\nif signature == expected_signature:\n    ok()\n", .python, "timing-unsafe-comparison", [2])
        assertFlags("// webhook\nif (req.headers.token === process.env.API_TOKEN) next();\n", .javascript,
                    "timing-unsafe-comparison", [2])
        assertFlags("// HMAC check\nif mac != computedHMAC {\n\treturn errBad\n}\n", .go, "timing-unsafe-comparison", [2])
        assertFlags("// auth\nif (apiKey.equals(x) || apiKey == provided) {}\n", .java, "timing-unsafe-comparison", [2])
        assertFlags("// HMAC\nguard signature == expected else { throw E.bad }\n", .swift, "timing-unsafe-comparison", [2])
        assertFlags("// password\nif (password == stored) { }\n", .objc, "timing-unsafe-comparison", [2])
    }

    func testSkipsPresenceChecksDescriptionsFormChecksAndConstantTimeCalls() {
        let python = "import hmac\nif token == '' or token is None or signature != None:\n    pass\n"
            + "if hmac.compare_digest(signature, expected):\n    pass\nif password != confirm_password:\n    pass\n"
        assertClean(python, .python, "timing-unsafe-comparison")
        let swift = "// auth\nif token == nil || token.kind == .bearer || tokenType == other { }\n"
            + "static func == (lhs: A, rhs: A) -> Bool { lhs.token == rhs.token }\n"
        assertClean(swift, .swift, "timing-unsafe-comparison")
        assertClean("if (token === null || typeof secret === 'string') {}\n", .typescript, "timing-unsafe-comparison")
        assertClean("// auth\nif token == nextToken {}\n", .go, "timing-unsafe-comparison")
        assertClean("// password\nconst others = list.filter(ot => ot !== token);\n", .javascript,
                    "timing-unsafe-comparison")
        assertClean("# secret\nif token == ('', ''):\n    pass\n", .python, "timing-unsafe-comparison")
    }
}

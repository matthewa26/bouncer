import BouncerCore

extension SecurityPatterns {
    /// A variable named for an IV, nonce, or salt: `iv`, `nonce`, `salt`, `aesIV`, `gcm_nonce`, `passwordSalt`.
    private static let ivName = #"(?:[A-Za-z_]\w*(?<=[a-z0-9])(?:IV|Iv|Nonce|Salt)|[A-Za-z_]\w*_(?:iv|IV|nonce|NONCE|"#
        + #"salt|SALT)|iv|IV|nonce|NONCE|salt|SALT|initializationVector)"#

    /// Fixed IVs, nonces, and salts: a literal assigned to one, or passed where a cipher takes one.
    static let hardcodedIV = SecurityPatternSpec(
        id: "hardcoded-iv",
        message: "IV, nonce, or salt is a fixed literal; generate a fresh random one for every encryption or hash.",
        patterns: [
            SecurityPattern([.python], #"^\s*(?:self\.)?\b"# + ivName + #"\s*=\s*b["'][^"']+["']"#),
            SecurityPattern([.python], #"^\s*(?:self\.)?\b"# + ivName + #"\s*=\s*["'][^"']+["']\.encode\("#),
            SecurityPattern([.python], #"\b(?:iv|nonce|salt)\s*=\s*b["'][^"']+["']"#),
            SecurityPattern([.python], #"\bAES\.new\([^,]+,[^,]+,\s*b["']|\bmodes\.(?:CBC|CFB|OFB|CTR|GCM)\(\s*b["']"#),
            SecurityPattern(scripts, #"\b(?:const|let|"#
                + #"var)\s+"# + ivName + #"\s*=\s*(?:Buffer\.from\(\s*["'`][^"'`$]+["'`]"#
                + #"|new\s+Uint8Array\(\s*\[\s*\d|["'`][^"'`$]+["'`]\s*;?\s*$)"#),
            SecurityPattern(scripts, #"\bcreateCipheriv\([^,]+,[^,]+,\s*(?:["'`]|Buffer\.(?:from\(\s*["'`]|alloc\())"#),
            SecurityPattern(scripts, #"\b(?:iv|nonce)\s*:\s*(?:Buffer\.from\(\s*["'`]|new\s+Uint8Array\(\s*(?:\[|"#
                + #"\d+\s*\)))"#),
            SecurityPattern([.swift], #"\b(?:let|var)\s+"# + ivName + #"\s*(?::\s*(?:\[UInt8\]|Data))?\s*=\s*(?:\[\s*"#
                + #"(?:0x[0-9A-Fa-f]+|\d+)\s*,|Data\(\s*\[\s*(?:0x|\d)|Array\("[^"]+"\.utf8\)|Data\("[^"]+"\.utf8\)|"#
                + #""[^"]+"\.data\(using:)"#),
            SecurityPattern([.swift], #"\bNonce\(data:\s*(?:Data\(\s*)?\[\s*(?:0x|\d)"#),
            SecurityPattern([.go], #"\b"# + ivName + #"\s*:?=\s*\[\]byte(?:\(\s*"[^"]+"|\{\s*(?:0x|\d))"#),
            SecurityPattern([.go], #"\bNewCBC(?:En|De)crypter\([^,]+,\s*\[\]byte(?:\(\s*"|\{)"#),
            SecurityPattern([.java], #"\bnew\s+(?:IvParameterSpec|PBEParameterSpec)\(\s*(?:"[^"]*"\.getBytes|"#
                + #"new\s+byte\s*"#
                + #"\[\s*\]\s*\{|new\s+byte\s*\[\s*\d+\s*\]\s*\))"#),
            SecurityPattern([.java], #"\bnew\s+GCMParameterSpec\(\s*\w+\s*,\s*(?:"[^"]*"\.getBytes|"#
                + #"new\s+byte\s*\[\s*\]\s*\{)"#),
            SecurityPattern([.java], #"\bbyte\s*\[\]\s*"# + ivName + #"\s*=\s*(?:\{|new\s+byte\s*\[\s*\]\s*\{|"#
                + #""[^"]*"\.getBytes)"#),
            SecurityPattern([.objc], #"\b(?:unsigned\s+char|uint8_t|char|Byte)\s+"# + ivName
                + #"\s*\[\s*\w*\s*\]\s*=\s*(?:\{\s*(?:0x[0-9A-Fa-f]+|\d+|'.')\s*,|")"#),
            SecurityPattern([.objc], #"\b"# + ivName + #"\s*=\s*\[\s*@"[^"]+"\s+dataUsingEncoding:"#)
        ],
        conditions: (fileGate: nil, fileExclusion: nil,
                     lineExclusion: #"(?i)random|urandom|getRandomValues|rand\.Read|token_bytes|placeholder|example"#)
    )

    /// RSA, DSA, or DH sizes under 2048 bits, written as the number a key-size parameter takes.
    private static let weakBits = #"(?:512|768|1024|1536)\b"#

    /// RSA keys under 2048 bits and elliptic curves of 192 bits or fewer.
    static let shortCryptoKey = SecurityPatternSpec(
        id: "short-crypto-key",
        message: "Key is too short to resist attack; use RSA of at least 2048 bits or an EC curve of at least 256.",
        patterns: [
            SecurityPattern(web, #"["'](?:secp(?:112|128|160|192)[rk][12]|prime192v[123]|P-192|"#
                + #"sect(?:113|131|163|193)[rk][12])["']"#),
            SecurityPattern(scripts, #"\bmodulusLength\s*:\s*"# + weakBits),
            SecurityPattern(scripts, #"\brsa\.generateKeyPair\(\s*(?:\{\s*bits\s*:\s*)?"# + weakBits),
            SecurityPattern([.python], #"\bkey_size\s*=\s*"# + weakBits, context: .file(#"(?i)\b(?:rsa|dsa|dh)\b"#)),
            SecurityPattern([.python], #"\b(?:RSA|DSA)\.generate\(\s*(?:bits\s*=\s*)?"# + weakBits),
            SecurityPattern([.python], #"\bec\.(?:SECP192R1|SECT163K1|SECT163R2)\("#),
            SecurityPattern([.go], #"\b(?:rsa|dsa)\.GenerateKey\(\s*[^,]+,\s*"# + weakBits),
            SecurityPattern([.java], #"\.initialize\(\s*"# + weakBits, context: .file(#"\bKeyPairGenerator\b"#)),
            SecurityPattern([.java], #"\bnew\s+RSAKeyGenParameterSpec\(\s*"# + weakBits),
            SecurityPattern([.swift, .objc], #"\bkSecAttrKeySizeInBits(?:\s+as\s+String)?\s*[:,]\s*"#
                + #"(?:@\(?\s*|NSNumber\(value:\s*)?"# + weakBits)
        ]
    )

    /// A shell, `/bin/sh`-style, named in an Objective-C argument list.
    private static let objcShell = #"@"(?:/usr)?/bin/(?:ba|z|da|k)?sh""#

    /// `system`/`popen` or a shell `NSTask` handed a command built with `stringWithFormat:` or appending.
    static let objcShellInjection = SecurityPatternSpec(
        id: "objc-shell-injection",
        message: "Shell command built from a format string risks injection; run the program directly with "
            + "an argument array.",
        patterns: [
            SecurityPattern([.objc], #"\b(?:system|popen)\s*\([^;]*(?:stringWithFormat:|"#
                + #"stringByAppending(?:String|Format):)"#),
            SecurityPattern([.objc], #"launchedTaskWithLaunchPath:\s*"# + objcShell
                + #"\s+arguments:\s*@\[\s*@"-c"\s*,\s*\[NSString\s+stringWithFormat:"#),
            SecurityPattern([.objc], #"@"-c"\s*,\s*\[NSString\s+stringWithFormat:"#, context: .nearby(objcShell))
        ]
    )

    /// MongoDB's query methods, which treat an object argument as operators.
    private static let mongoQuery = #"\.(?:find|findOne|findOneAndUpdate|findOneAndDelete|findOneAndRemove|deleteOne|"#
        + #"deleteMany|updateOne|updateMany|countDocuments|find_one|find_one_and_update|find_one_and_delete|"#
        + #"delete_one|delete_many|update_one|update_many|count_documents)\(\s*(?:\{[^}]*?:\s*)?"#

    /// `$where` built from strings, and request bodies handed straight to a MongoDB query.
    static let nosqlInjection = SecurityPatternSpec(
        id: "nosql-injection",
        message: "Request input or a built string reaches a NoSQL query, where an object like {\"$ne\": null} or "
            + "a $where script changes its meaning; cast values to strings, or sanitize the query.",
        patterns: [
            SecurityPattern(scripts, #"\$where['"]?\s*:\s*(?:['"][^'"]*['"]\s*\+|`[^`]*\$\{)"#),
            SecurityPattern(scripts, mongoQuery + #"req\.(?:body|query)\b"#),
            SecurityPattern([.python], #"["']\$where["']\s*:\s*(?:f["']|["'][^"']*["']\s*(?:\+|%)|"#
                + #"["'][^"']*["']\.format\()"#),
            SecurityPattern([.python], mongoQuery + #"request\.(?:json|get_json\(\)|data)\b"#),
            SecurityPattern([.go], #""\$where"\s*:\s*(?:"[^"]*"\s*\+|fmt\.Sprintf\()"#),
            SecurityPattern([.java], #"\bnew\s+(?:BasicDBObject|Document)\(\s*"\$where"\s*,\s*(?:"[^"]*"\s*\+|"#
                + #"String\.format\()"#)
        ],
        conditions: (fileGate: #"(?i)mongo|\bcollection\b|\$where"#,
                     fileExclusion: #"mongo-sanitize|mongoSanitize|express-mongo-sanitize"#,
                     lineExclusion: #"\bString\(|\bstr\(|sanitiz|\btoString\(\)"#)
    )

    /// JWT checks switched off: no signature verification, the `none` algorithm, or expiry ignored.
    static let jwtVerificationDisabled = SecurityPatternSpec(
        id: "jwt-verification-disabled",
        message: "JWT signature or expiry checking is switched off, so a forged or expired token is accepted.",
        patterns: [
            SecurityPattern([.python], #"\bjwt\.decode\([^)]*\bverify\s*=\s*False\b"#),
            SecurityPattern([.python], #"["']verify_(?:signature|exp)["']\s*:\s*False\b"#),
            SecurityPattern([.python], #"\balgorithms\s*=\s*\[[^\]]*["'](?i:none)["']"#),
            SecurityPattern(scripts, #"\balgorithms\s*:\s*\[[^\]]*['"](?i:none)['"]|"#
                + #"\balgorithm\s*:\s*['"](?i:none)['"]"#),
            SecurityPattern(scripts, #"\bignoreExpiration\s*:\s*true\b"#),
            SecurityPattern([.go], #"\bjwt\.(?:SigningMethodNone|UnsafeAllowNoneSignatureType)\b"#),
            SecurityPattern([.java], #"\.(?:parseClaimsJwt|parseUnsecuredClaims)\(|\.unsecured\(\)"#)
        ],
        conditions: (fileGate: #"(?i)jwt|jose|jsonwebtoken"#, fileExclusion: nil, lineExclusion: nil)
    )

    /// Deserializers that can build arbitrary objects from their input, outside Python, which
    /// `python-unsafe-deserialization` covers.
    static let unsafeDeserialization = SecurityPatternSpec(
        id: "unsafe-deserialization",
        message: "Deserializing untrusted data this way can build arbitrary objects and run code; use a data-only "
            + "format, or restrict the classes it may create.",
        patterns: [
            SecurityPattern([.java], #"\bnew\s+ObjectInputStream\("#, context: .file(#"\.readObject\("#)),
            SecurityPattern([.java], #"\bnew\s+XMLDecoder\(|\.enableDefaultTyping\("#),
            SecurityPattern(scripts, #"\.unserialize\("#, context: .file(#"node-serialize"#)),
            SecurityPattern([.swift], #"\bNSKeyedUnarchiver\.unarchiveObject\(with(?:File)?:|"#
                + #"\bNSKeyedUnarchiver\.unarchiveTopLevelObjectWithData\(|\bNSUnarchiver\b|"#
                + #"\.requiresSecureCoding\s*=\s*false\b"#),
            SecurityPattern([.objc], #"\[NSKeyedUnarchiver\s+unarchiveObjectWith(?:Data|File):|"#
                + #"\bunarchiveTopLevelObjectWithData:|\bNSUnarchiver\b|\bsetRequiresSecureCoding:\s*NO\b|"#
                + #"\.requiresSecureCoding\s*=\s*NO\b|\[NSKeyedUnarchiver\s+alloc\]\s+initForReadingWithData:"#),
            SecurityPattern([.php], #"(?<![\w$>:])unserialize\s*\((?![^;]*allowed_classes['"]\s*=>\s*(?:false|\[))"#
                + #"[^,;)]*\$"#)
        ],
        conditions: (fileGate: nil, fileExclusion: #"ObjectInputFilter|ValidatingObjectInputStream|resolveClass\("#,
                     lineExclusion: nil)
    )
}

# Security Rules and the OWASP Top 10

Which security risks Bouncer checks for, grouped by OWASP Top 10:2025 category, and the `owasp`
profile that turns every one of them on as an error.

## Overview

Bouncer's security rules are pattern checks: each looks for a risky call or setting written in
the source, such as a TLS check switched off, a SQL string built by concatenation, or request
input handed to `fetch`. They aren't a taint-analysis engine or a substitute for a dedicated SAST
tool, a dependency scanner, or a penetration test. They're tuned for precision: a finding should
almost always be worth a look, at the cost of missing variations the patterns don't recognize.

Each security rule is mapped to exactly one category of the
[OWASP Top 10:2025](https://owasp.org/Top10/). `--format json` adds the category to every
finding from a mapped rule as `"owasp": "A05:2025"`; findings from other rules are written
exactly as before, with no `owasp` key. The HTML report (`--format html`) shows an
**OWASP category** filter, such as `A05:2025 Injection`, whenever the report has a security
finding, and its JSON copy and download carry the same `owasp` field. The console, table, and
Xcode formats don't show categories.

See <doc:RuleCatalog> for each rule's exact patterns, languages, and limits.

## The mapping

### A01:2025 Broken Access Control

`path-traversal`, `ssrf`, `open-redirect`, `cors-credentials-any-origin`.

Request input reaching a file path, an outbound request's URL, or a redirect's destination, and
CORS that lets any site make credentialed requests. Access control itself (who may see which
record) lives in application logic no pattern can read, so this category is covered only in part:
these rules catch the request-input and CORS mistakes that bypass it, not a missing ownership
check.

### A02:2025 Security Misconfiguration

`insecure-http-url`, `hardcoded-ip`, `debug-mode-enabled`, `permissive-cors`, `insecure-cookie`,
`xml-external-entities`.

Plain `http://` URLs, hard-coded addresses, debug mode left on, CORS open to every origin,
cookies without `Secure` or `HttpOnly`, and XML parsers that resolve external entities.

### A03:2025 Software Supply Chain Failures

`unpinned-dependency`, `missing-lockfile`, `pipe-to-shell`, `unpinned-ci-action`.

Dependencies and CI actions without a pinned version, manifests without a lockfile, and
`curl … | sh` installs.

### A04:2025 Cryptographic Failures

`secret-looking-pattern`, `weak-crypto`, `insecure-random`, `disabled-tls-verification`,
`hardcoded-iv`, `short-crypto-key`.

Committed credentials, MD5/SHA-1/DES/ECB, non-cryptographic randomness for tokens and IDs,
disabled certificate checks, fixed IVs, nonces, and salts, and RSA keys under 2048 bits or curves
of 192 bits or fewer.

### A05:2025 Injection

`sql-string-building`, `sql-missing-where`, `shell-eval-usage`, `powershell-invoke-expression`,
`c-gets-usage`, `c-unsafe-string-function`, `python-shell-injection`, `js-shell-injection`,
`go-shell-injection`, `swift-shell-injection`, `rust-shell-injection`, `objc-shell-injection`,
`js-eval`, `js-raw-html`, `python-eval-exec`, `template-injection`, `nosql-injection`.

SQL, shell, and template strings built from variables, code evaluated from strings, raw HTML
written into the page, unbounded C string functions, and request bodies handed to NoSQL queries.

### A06:2025 Insecure Design

No rules. Insecure design is a missing control, such as no rate limit on login or no threat model
for a payment flow, and the absence of something that was never written has no pattern to match.
Design reviews and threat modeling cover this category.

### A07:2025 Authentication Failures

`powershell-plaintext-password`, `jwt-verification-disabled`, `timing-unsafe-comparison`.

Plaintext password handling, JWT signature or expiry checks switched off, and secrets compared
with ordinary equality, which leaks timing. Most authentication failures (weak password rules,
missing MFA, session fixation) are about what an application doesn't do, so this category is
covered only in part.

### A08:2025 Software or Data Integrity Failures

`python-unsafe-deserialization`, `unsafe-deserialization`.

Deserializers that can build arbitrary objects from their input: `pickle`, `yaml.load`, Java's
`ObjectInputStream` and `XMLDecoder`, `node-serialize`, and the non-secure `NSKeyedUnarchiver`
APIs.

### A09:2025 Security Logging and Alerting Failures

`logged-secret`, `unlogged-security-failure`.

Secrets written to logs, and failed security checks (a token that doesn't verify, a permission
that's denied) handled without a log line, an error, or a response. `unlogged-security-failure`
is a proxy: it reads the code a handler guards for words like *verify*, *authenticate*, or
*token*, and accepts any logging, reporting, rethrowing, returning, or responding as handling the
failure, so it misses handlers that log to the wrong place and can flag a handler whose caller
logs.

### A10:2025 Mishandling of Exceptional Conditions

`empty-catch`, `swift-discarded-try`, `python-bare-except`, `java-generic-exception-catch`,
`rust-unwrap`, `fail-open`.

Errors swallowed or caught too broadly, and security checks that let a request through when they
fail (`return true` or `next()` in the error handler).

## The owasp profile

`--profile owasp` (or `"profile": "owasp"` in `.bouncer`) enables every rule in the mapping above
and reports it as an error, so a run fails on any security finding:

```
bouncer review . --profile owasp
```

Rules that are off unless configured are turned on, and the rest of the catalog keeps its
defaults. Like any profile, it's the base layer: a rule your `~/.bouncer` or repo `.bouncer` sets
explicitly keeps that setting, so you can drop a rule back to a warning or turn it off:

```json
{
  "profile": "owasp",
  "rules": {
    "hardcoded-ip": { "severity": "warning" },
    "insecure-http-url": { "enabled": false }
  }
}
```

See <doc:Profiles> for how profiles layer.

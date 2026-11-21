import XCTest
import Foundation
import BouncerCore
@testable import BouncerRules

final class OWASPRequestFlowRulesTests: OWASPRuleTestCase {
    // MARK: ssrf

    func testFlagsRequestInputChoosingAnOutboundURL() {
        assertFlags("const r = await fetch(req.query.url);\n", .javascript, "ssrf", [1])
        assertFlags("const target = req.body.target;\nawait axios.get(target);\n", .typescript, "ssrf", [2])
        assertFlags("url = request.args.get('u')\nresp = requests.get(url, timeout=5)\n", .python, "ssrf", [2])
        assertFlags("data = urllib.request.urlopen(request.form['feed']).read()\n", .python, "ssrf", [1])
        assertFlags("u := r.URL.Query().Get(\"u\")\nresp, err := http.Get(u)\n", .go, "ssrf", [2])
        assertFlags("target := r.FormValue(\"t\")\nreq, _ := http.NewRequest(\"GET\", target, nil)\n", .go, "ssrf", [2])
        assertFlags("String u = request.getParameter(\"u\");\nnew URL(u).openConnection();\n", .java, "ssrf", [2])
        assertFlags("let u = req.query[\"u\"] ?? \"\"\nlet r = try await req.client.get(URI(string: u))\n", .swift,
                    "ssrf", [2])
        let objc = "NSURLSession *s = [NSURLSession sharedSession];\nNSString *u = request.query[@\"u\"];\n"
            + "NSURL *url = [NSURL URLWithString:u];\n"
        assertFlags(objc, .objc, "ssrf", [3])
    }

    func testSkipsFixedHostsCheckedHostsAndUnrelatedCalls() {
        assertClean("await fetch('https://api.example.com/users/' + req.params.id);\n", .javascript, "ssrf")
        assertClean("await fetch(`https://api.example.com/u/${req.query.id}`);\n", .typescript, "ssrf")
        assertClean("url = request.args.get('u')\nif url not in ALLOWED_HOSTS:\n    abort(400)\nrequests.get(url)\n",
                    .python, "ssrf")
        assertClean("resp, err := http.Get(cfg.Endpoint)\n", .go, "ssrf")
        assertClean("const n = parseInt(req.query.n);\nawait fetch(n);\n", .javascript, "ssrf")
        assertClean("await fetch(req.query.url);\n", .javascript, "ssrf", path: "/repo/test/proxy.test.js")
    }

    // MARK: open-redirect

    func testFlagsRequestInputChoosingARedirect() {
        assertFlags("res.redirect(req.query.next);\n", .javascript, "open-redirect", [1])
        assertFlags("const dest = req.query.returnTo;\nres.redirect(302, dest);\n", .typescript, "open-redirect", [2])
        assertFlags("const next = new URL(location.href).searchParams.get('next');\nwindow.location.href = next;\n",
                    .javascript, "open-redirect", [2])
        assertFlags("nxt = request.args.get('next')\nreturn redirect(nxt)\n", .python, "open-redirect", [2])
        assertFlags("return HttpResponseRedirect(request.GET['next'])\n", .python, "open-redirect", [1])
        assertFlags("http.Redirect(w, r, r.URL.Query().Get(\"next\"), http.StatusFound)\n", .go, "open-redirect", [1])
        assertFlags("response.sendRedirect(request.getParameter(\"next\"));\n", .java, "open-redirect", [1])
        assertFlags("return req.redirect(to: req.query[\"next\"] ?? \"/\")\n", .swift, "open-redirect", [1])
    }

    func testSkipsFixedRedirectsAndValidatedTargets() {
        assertClean("res.redirect('/login?next=' + req.query.next);\n", .javascript, "open-redirect")
        assertClean("const location = req.query.loc;\n", .javascript, "open-redirect")
        let django = "nxt = request.GET.get('next')\nif not url_has_allowed_host_and_scheme(nxt, None):\n"
            + "    nxt = '/'\nreturn redirect(nxt)\n"
        assertClean(django, .python, "open-redirect")
        assertClean("return redirect(url_for('index'))\n", .python, "open-redirect")
        assertClean("http.Redirect(w, r, \"/home\", http.StatusFound)\n", .go, "open-redirect")
        assertClean("response.sendRedirect(\"/login\");\n", .java, "open-redirect")
    }
}

final class OWASPFailureHandlingRulesTests: OWASPRuleTestCase {
    // MARK: fail-open

    func testFlagsHandlersThatLetAFailedCheckThrough() {
        let express = "jwt.verify(token, key, (err, user) => {\n  if (err) return next();\n  req.user = user;\n});\n"
        assertFlags(express, .javascript, "fail-open", [2])
        let ts = "try {\n  await verifyToken(t);\n  return true;\n} catch (e) {\n  return true;\n}\n"
        assertFlags(ts, .typescript, "fail-open", [4])
        let python = "try:\n    jwt.decode(token, key, algorithms=['HS256'])\nexcept jwt.InvalidTokenError:\n"
            + "    return True\n"
        assertFlags(python, .python, "fail-open", [3])
        let go = "ok, err := verifySignature(body, sig)\nif err != nil {\n\tauthorized = true\n}\n"
        assertFlags(go, .go, "fail-open", [2])
        let java = "try {\n  authenticate(user, password);\n} catch (AuthException e) {\n  return true;\n}\n"
        assertFlags(java, .java, "fail-open", [3])
        let swift = "do {\n    try verifier.verify(token)\n} catch {\n    return true\n}\n"
        assertFlags(swift, .swift, "fail-open", [3])
        let objc = "@try {\n  [self verifySignature:sig];\n} @catch (NSException *e) {\n  return YES;\n}\n"
        assertFlags(objc, .objc, "fail-open", [3])
    }

    func testSkipsHandlersThatDenyOrAreNotOnASecurityCheck() {
        let deny = "jwt.verify(token, key, (err, user) => {\n  if (err) return next(err);\n});\n"
        assertClean(deny, .javascript, "fail-open")
        let unrelated = "try {\n  JSON.parse(s);\n} catch (e) {\n  return true;\n}\n"
        assertClean(unrelated, .typescript, "fail-open")
        assertClean("try:\n    jwt.decode(t, k)\nexcept jwt.InvalidTokenError:\n    return False\n", .python, "fail-open")
        assertClean("do {\n    try verifier.verify(token)\n} catch {\n    return false\n}\n", .swift, "fail-open")
    }

    // MARK: unlogged-security-failure

    func testFlagsHandlersThatSwallowAFailedCheck() {
        let ts = "try {\n  req.user = await verifyToken(t);\n} catch (e) {\n  req.user = undefined;\n}\n"
        assertFlags(ts, .typescript, "unlogged-security-failure", [3])
        let python = "try:\n    claims = jwt.decode(token, key)\nexcept jwt.InvalidTokenError:\n    claims = {}\n"
        assertFlags(python, .python, "unlogged-security-failure", [3])
        let go = "claims, err := jwt.Parse(raw, keyFunc)\nif err != nil {\n\tclaims = nil\n}\n"
        assertFlags(go, .go, "unlogged-security-failure", [2])
        let java = "try {\n  checkPermission(user);\n} catch (SecurityException e) {\n  // ignore\n  denied++;\n}\n"
        assertFlags(java, .java, "unlogged-security-failure", [3])
        let swift = "do {\n    try authenticate(user)\n} catch {\n    session = nil\n}\n"
        assertFlags(swift, .swift, "unlogged-security-failure", [3])
        let objc = "@try {\n  [self verifySignature:sig];\n} @catch (NSException *e) {\n  self.user = nil;\n}\n"
        assertFlags(objc, .objc, "unlogged-security-failure", [3])
        let js = "verifyToken(t).catch(() => { state.user = null; });\n"
        assertFlags(js, .javascript, "unlogged-security-failure", [1])
    }

    func testSkipsHandlersThatLogRethrowReturnOrAreEmpty() {
        let logged = "try {\n  await verifyToken(t);\n} catch (e) {\n  logger.warn('bad token', e);\n}\n"
        assertClean(logged, .typescript, "unlogged-security-failure")
        let rethrown = "try:\n    jwt.decode(t, k)\nexcept jwt.InvalidTokenError:\n    raise Unauthorized()\n"
        assertClean(rethrown, .python, "unlogged-security-failure")
        assertClean("try:\n    jwt.decode(t, k)\nexcept jwt.InvalidTokenError:\n    pass\n", .python,
                    "unlogged-security-failure")
        assertClean("claims, err := jwt.Parse(raw, kf)\nif err != nil {\n\treturn nil, err\n}\n", .go,
                    "unlogged-security-failure")
        assertClean("try {\n  parse(s);\n} catch (e) {\n  x = 1;\n}\n", .java, "unlogged-security-failure")
        assertClean("do {\n    try authenticate(user)\n} catch {\n    os_log(\"auth failed\")\n}\n", .swift,
                    "unlogged-security-failure")
        let stderr = "try:\n    user, acct, passwd = rc.authenticators(host)\nexcept KeyError:\n"
            + "    sys.stderr.write('No account')\n"
        assertClean(stderr, .python, "unlogged-security-failure")
        assertClean("try:\n    os.unlink(path)\nexcept PermissionError:\n    found = False\n", .python,
                    "unlogged-security-failure")
        assertClean("@try {\n  [self verify];\n} @catch (NSException *e) {\n  NSLog(@\"%@\", e);\n}\n", .objc,
                    "unlogged-security-failure")
    }
}

import BouncerCore

/// The data behind the rules that follow request input to a dangerous call: an outbound request (`ssrf`), a
/// redirect (`open-redirect`), or a template engine (`template-injection`).
public enum RequestSinks {
    private static let scripts = SecurityPatterns.scripts

    /// Every request-input sink rule, one per spec.
    public static let specs: [RequestSinkSpec] = [ssrf, openRedirect, templateInjection]

    /// Request input used as the URL of an outbound HTTP request.
    static let ssrf = RequestSinkSpec(
        id: "ssrf",
        message: "Request input chooses the URL of an outbound request (SSRF), so a caller can reach internal hosts; "
            + "check the host against an allowlist.",
        calls: (sinks: [
            SecurityPattern(scripts, #"(?<![.\w$])fetch\(|\baxios(?:\.(?:get|post|put|patch|delete|head|request))?\("#),
            SecurityPattern(scripts, #"\bhttps?\.(?:get|request)\(|\bgot(?:\.(?:get|post))?\(|\brequest\.(?:get|"#
                + #"post)\("#),
            SecurityPattern([.python], #"\b(?:requests|httpx)\.(?:get|post|put|patch|delete|head|options)\("#),
            SecurityPattern([.python], #"\burlopen\("#),
            SecurityPattern([.go], #"\b(?:http|http\.DefaultClient|client|httpClient)\.(?:Get|Head|Post|PostForm)\("#),
            SecurityPattern([.go], #"\bhttp\.NewRequest(?:WithContext)?\((?:\s*ctx\s*,)?\s*[^,]+,\s*"#),
            SecurityPattern([.java], #"\bnew\s+URL\((?=.*\.(?:openConnection|openStream)\()"#),
            SecurityPattern([.java], #"\.(?:getForObject|getForEntity|postForObject|postForEntity|exchange)\(|"#
                + #"\bHttpRequest\.newBuilder\("#),
            SecurityPattern([.swift], #"\b(?:dataTask|downloadTask|data|download)\((?:with|from):\s*"#,
                            context: .file(#"\bURLSession\b"#)),
            SecurityPattern([.swift], #"\bclient\.(?:get|post|put|delete)\("#),
            SecurityPattern([.objc], #"\[NSURL\s+URLWithString:\s*"#,
                            context: .file(#"\bNSURLSession\b|\bNSURLConnection\b"#))
        ], direct: []),
        reach: .leading,
        validation: #"(?i)allow_?list|allowed_?(?:hosts?|domains?|urls?)|whitelist|is_?safe_?url|validate_?url|"#
            + #"isAllowed|ALLOWED_"#
    )

    /// Request input used as a redirect's destination.
    static let openRedirect = RequestSinkSpec(
        id: "open-redirect",
        message: "Request input chooses where to redirect (open redirect), so a link to this site can send users "
            + "anywhere; allow only relative paths or listed hosts.",
        calls: (sinks: [
            SecurityPattern(scripts, #"\b(?:res|ctx|reply|response)\.redirect\(\s*(?:\d{3}\s*,\s*)?"#),
            SecurityPattern(scripts, #"(?<![.\w$])(?<!const\s|let\s|var\s)(?:window\.|"#
                + #"document\.)?location(?:\.href)?\s*=(?!=)\s*|\blocation\.(?:assign|replace)\("#),
            SecurityPattern([.python], #"(?<![.\w])redirect\(|\b(?:HttpResponseRedirect|RedirectResponse)\("#),
            SecurityPattern([.go], #"\bhttp\.Redirect\(\s*\w+\s*,\s*\w+\s*,\s*|\bc\.Redirect\(\s*[\w.]+\s*,\s*"#),
            SecurityPattern([.java], #"\.sendRedirect\(|"redirect:"\s*\+\s*"#),
            SecurityPattern([.swift], #"\.redirect\(to:\s*"#)
        ], direct: []),
        reach: .leading,
        validation: #"(?i)is_safe_url|url_has_allowed_host_and_scheme|is_?safe_?(?:redirect|url)|is_?local_?url|"#
            + #"allow_?list|allowed_?(?:hosts?|domains?)|whitelist|startsWith\(\s*['"]/|startswith\(\s*['"]/|"#
            + #"HasPrefix\(\s*\w+\s*,\s*"/"#
    )

    /// Request input, or a string built on the spot, compiled as a template rather than passed to one as data.
    static let templateInjection = RequestSinkSpec(
        id: "template-injection",
        message: "Request input is compiled as a template (server-side template injection), which can run code; "
            + "pass it to a fixed template as a variable instead.",
        calls: (sinks: [
            SecurityPattern([.python], #"\brender_template_string\(|\bjinja2\.Template\(|\.from_string\("#),
            SecurityPattern([.python], #"\bTemplate\((?=.*\.render\()"#),
            SecurityPattern(scripts, #"\b(?:ejs|pug|nunjucks)\.(?:render|compile|renderString)\(|"#
                + #"\b[Hh]andlebars\.compile\("#),
            SecurityPattern(scripts, #"\b_\.template\(|\bdoT\.template\("#),
            SecurityPattern([.go], #"\btemplate\.New\([^)]*\)\.Parse\(|\btemplate\.HTML\("#)
        ], direct: [
            SecurityPattern([.python], #"\brender_template_string\(\s*(?:f["']|["'][^"']*["']\s*(?:\+|%)|"#
                + #"["'][^"']*["']\.format\()"#),
            SecurityPattern(scripts, #"\b(?:(?:ejs|pug|nunjucks)\.(?:render|compile|renderString)|"#
                + #"[Hh]andlebars\.compile)"#
                + #"\(\s*`[^`]*\$\{"#),
            SecurityPattern([.go], #"\btemplate\.New\([^)]*\)\.Parse\(\s*(?:fmt\.Sprintf\(|"[^"]*"\s*\+)"#)
        ]),
        reach: .anywhere
    )
}

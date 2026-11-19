/// The debug-output patterns behind `c-debug-print` and `cpp-debug-print`: a `printf`/`puts`, an
/// `fprintf(stderr, …)`, or (C++) a `std::cout`/`cerr`/`clog` stream whose text starts with a debugging marker
/// (`DEBUG`, `DBG`, `XXX`, `debug:`), or is only a `"here"`-style trace (`"here"`, `"HERE 2\n"`).
///
/// Ordinary output and logging (`fprintf(stderr, "error: …")`, `LOG(…)`) isn't matched: telling a leftover from
/// real output needs the marker.
enum CDebugOutput {
    private static let marker = #""\s*[\[<(]?\s*(?:(?:DEBUG|DBG|XXX)\b|[Dd]ebug:)|"\s*(?:here|HERE|Here)\s*\d*[!:.]*"#
        + #"\s*(?:\\n)?""#
    /// The C pattern: a `printf`-family call whose text starts with a marker.
    static let cPattern = #"\b(?:printf|puts)\s*\(\s*(?:"# + marker + #")|\bfprintf\s*\(\s*stderr\s*,\s*(?:"#
        + marker + ")"
    /// The C++ pattern: the C one, or a standard stream fed a marker.
    static let cppPattern = cPattern + #"|\bstd::(?:cout|cerr|clog)\s*<<\s*(?:"# + marker + ")"
    /// The message both rules share.
    static let message = "Debug output left in; remove it, or use a logging macro that compiles out."
}

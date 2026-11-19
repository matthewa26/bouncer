/// The HTML report's page: styles, markup, and the script that renders the table, all inline so the file works
/// offline and straight from disk. The fixed parts are constants; `page` joins them around the run's values in a
/// single pass, so text from a finding can never be read as part of the template.
enum HTMLTemplate {
    /// Builds the page from already-escaped pieces.
    ///
    /// - Parameters:
    ///   - title: The page title, HTML-escaped.
    ///   - summary: The summary line, HTML-escaped.
    ///   - rows: The findings as a JSON array, safe inside a `<script>` element.
    ///   - json: The `--format json` report, HTML-escaped.
    /// - Returns: The complete page.
    static func page(title: String, summary: String, rows: String, json: String) -> String {
        let parts = [documentStart, title, styles, title, summaryStart, summary, views, json, dataStart, rows, script]
        return parts.joined()
    }

    /// The doctype and head, up to the title.
    private static let documentStart = #"""
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>
        """#

    /// The rest of the head, with the styles, and the page header up to its heading's text.
    private static let styles = #"""
        </title>
        <style>
        :root { --bg: #fff; --fg: #1d1d1f; --muted: #6e6e73; --line: #e5e5ea; --panel: #f5f5f7;
          --error: #c62828; --warning: #b26a00; --info: #1565c0; }
        @media (prefers-color-scheme: dark) { :root { --bg: #161618; --fg: #f2f2f7; --muted: #a1a1a6;
          --line: #2c2c2e; --panel: #1f1f22; --error: #ff6b6b; --warning: #ffb74d; --info: #64b5f6; } }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--fg);
          font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        header, main { max-width: 1200px; margin: 0 auto; padding: 16px; }
        h1 { font-size: 20px; margin: 8px 0 4px; } .summary { color: var(--muted); margin: 0; }
        .tabs { display: flex; gap: 8px; margin-top: 16px; border-bottom: 1px solid var(--line); }
        .tabs button { background: none; border: 0; border-bottom: 2px solid transparent; color: var(--muted);
          font: inherit; padding: 8px 4px; cursor: pointer; }
        .tabs button[aria-selected="true"] { color: var(--fg); border-bottom-color: var(--fg); font-weight: 600; }
        .controls { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; margin: 12px 0; }
        input[type=search] { flex: 1 1 240px; padding: 6px 10px; border: 1px solid var(--line); border-radius: 6px;
          background: var(--bg); color: var(--fg); font: inherit; }
        .count { color: var(--muted); }
        .scroll { overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
        th { cursor: pointer; user-select: none; white-space: nowrap; background: var(--panel); }
        td.loc, td.rule { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 12.5px; }
        td.rule { white-space: nowrap; } td.loc { overflow-wrap: anywhere; min-width: 16ch; }
        td.msg { min-width: 32ch; }
        .sev { font-weight: 600; text-transform: capitalize; }
        .sev.error { color: var(--error); } .sev.warning { color: var(--warning); } .sev.info { color: var(--info); }
        pre { background: var(--panel); padding: 12px; border-radius: 6px; overflow: auto; font-size: 12.5px; }
        button.action { padding: 6px 12px; border: 1px solid var(--line); border-radius: 6px;
          background: var(--panel); color: var(--fg); font: inherit; cursor: pointer; }
        .empty { color: var(--muted); padding: 24px 0; }
        [hidden] { display: none !important; }
        </style></head>
        <body><header><h1>
        """#

    /// Closes the heading and opens the summary line.
    private static let summaryStart = #"""
        </h1><p class="summary">
        """#

    /// The tabs, the table view, and the JSON view up to its text.
    private static let views = #"""
        </p>
        <nav class="tabs" role="tablist">
        <button role="tab" aria-selected="true" data-view="table">Table</button>
        <button role="tab" aria-selected="false" data-view="json">JSON</button></nav></header>
        <main><section id="table-view">
        <div class="controls"><input type="search" id="query" placeholder="Filter by rule, file, or message">
        <label><input type="checkbox" class="sev-filter" value="error" checked> Errors</label>
        <label><input type="checkbox" class="sev-filter" value="warning" checked> Warnings</label>
        <label><input type="checkbox" class="sev-filter" value="info" checked> Info</label>
        <span class="count" id="count"></span></div>
        <div class="scroll"><table><thead><tr>
        <th data-key="severity">Severity</th><th data-key="ruleID">Rule</th>
        <th data-key="location">Location</th><th data-key="message">Message</th>
        </tr></thead><tbody id="rows-body"></tbody></table></div>
        <p class="empty" id="empty" hidden>No findings match.</p></section>
        <section id="json-view" hidden><div class="controls">
        <button class="action" id="copy">Copy JSON</button><button class="action" id="download">Download JSON</button>
        <span class="count" id="copied"></span></div><pre id="json">
        """#

    /// Closes the JSON view and opens the findings data.
    private static let dataStart = #"""
        </pre></section></main>
        <script type="application/json" id="rows">
        """#

    /// Closes the findings data, then the script that renders, filters, and sorts the table and runs the tabs
    /// and JSON buttons.
    private static let script = #"""
        </script>
        <script>
        const rows = JSON.parse(document.getElementById("rows").textContent);
        rows.forEach(r => { r.location = r.path + ":" + r.line; });
        const rank = { error: 0, warning: 1, info: 2 };
        let sortKey = "severity", ascending = true;
        const $ = id => document.getElementById(id);
        function compare(a, b) {
          if (sortKey === "severity") return rank[a.severity] - rank[b.severity];
          if (sortKey === "location") return a.path.localeCompare(b.path) || a.line - b.line;
          return String(a[sortKey]).localeCompare(String(b[sortKey]));
        }
        function render() {
          const query = $("query").value.toLowerCase();
          const shown = new Set([...document.querySelectorAll(".sev-filter:checked")].map(box => box.value));
          const visible = rows.filter(r => shown.has(r.severity)
            && (r.ruleID + " " + r.location + " " + r.message).toLowerCase().includes(query))
            .sort((a, b) => (ascending ? 1 : -1) * compare(a, b));
          const body = $("rows-body");
          body.replaceChildren(...visible.map(r => {
            const tr = document.createElement("tr");
            [["sev " + r.severity, r.severity], ["rule", r.ruleID], ["loc", r.location], ["msg", r.message]]
              .forEach(([cls, text]) => { const td = tr.insertCell(); td.className = cls; td.textContent = text; });
            return tr;
          }));
          $("count").textContent = "Showing " + visible.length + " of " + rows.length;
          $("empty").hidden = visible.length > 0;
        }
        document.querySelectorAll("th").forEach(th => th.addEventListener("click", () => {
          ascending = sortKey === th.dataset.key ? !ascending : true;
          sortKey = th.dataset.key;
          render();
        }));
        $("query").addEventListener("input", render);
        document.querySelectorAll(".sev-filter").forEach(box => box.addEventListener("change", render));
        document.querySelectorAll(".tabs button").forEach(tab => tab.addEventListener("click", () => {
          const tabs = document.querySelectorAll(".tabs button");
          tabs.forEach(other => other.setAttribute("aria-selected", other === tab));
          $("table-view").hidden = tab.dataset.view !== "table";
          $("json-view").hidden = tab.dataset.view !== "json";
        }));
        $("copy").addEventListener("click", async () => {
          try { await navigator.clipboard.writeText($("json").textContent); $("copied").textContent = "Copied."; }
          catch { getSelection().selectAllChildren($("json")); $("copied").textContent = "Selected; press Ctrl+C."; }
        });
        $("download").addEventListener("click", () => {
          const link = document.createElement("a");
          link.href = URL.createObjectURL(new Blob([$("json").textContent], { type: "application/json" }));
          link.download = "bouncer-report.json";
          link.click();
        });
        render();
        </script></body></html>
        """#
}

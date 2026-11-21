/// The HTML report's page: styles, markup, and the script that renders the table, all inline so the file works
/// offline and straight from disk. The fixed parts are constants; `page` joins them around the run's values in a
/// single pass, so text from a finding can never be read as part of the template.
enum HTMLTemplate {
    /// Builds the page from already-escaped pieces.
    ///
    /// - Parameters:
    ///   - title: The page title, HTML-escaped.
    ///   - summary: The summary line, HTML-escaped.
    ///   - data: The findings in the compact form `HTMLReportData` encodes, safe inside a `<script>` element.
    /// - Returns: The complete page.
    static func page(title: String, summary: String, data: String) -> String {
        [documentStart, title, styles, title, summaryStart, summary, views, data, script].joined()
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
          --error: #c62828; --warning: #b26a00; --info: #1565c0; --focus: #1565c0; }
        @media (prefers-color-scheme: dark) { :root { --bg: #161618; --fg: #f2f2f7; --muted: #a1a1a6;
          --line: #2c2c2e; --panel: #1f1f22; --error: #ff6b6b; --warning: #ffb74d; --info: #64b5f6;
          --focus: #64b5f6; } }
        * { box-sizing: border-box; }
        body { margin: 0; background: var(--bg); color: var(--fg);
          font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        header, main { max-width: 1200px; margin: 0 auto; padding: 16px; }
        h1 { font-size: 20px; margin: 8px 0 4px; } .summary { color: var(--muted); margin: 0; }
        :focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
        .visually-hidden { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0);
          white-space: nowrap; }
        .tabs { display: flex; gap: 8px; margin-top: 16px; border-bottom: 1px solid var(--line); }
        .tabs button { background: none; border: 0; border-bottom: 2px solid transparent; color: var(--muted);
          font: inherit; padding: 8px 4px; cursor: pointer; }
        .tabs button[aria-selected="true"] { color: var(--fg); border-bottom-color: var(--fg); font-weight: 600; }
        .controls { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; margin: 12px 0; }
        .controls label.search { flex: 1 1 240px; display: flex; }
        input[type=search], select { padding: 6px 10px; border: 1px solid var(--line); border-radius: 6px;
          background: var(--bg); color: var(--fg); font: inherit; }
        input[type=search] { flex: 1; }
        fieldset { border: 0; margin: 0; padding: 0; display: flex; gap: 12px; }
        .count, .note { color: var(--muted); }
        details { border: 1px solid var(--line); border-radius: 6px; padding: 8px 12px; margin: 0 0 12px; }
        summary { cursor: pointer; font-weight: 600; }
        .rule-list { list-style: none; margin: 0; padding: 0; columns: 2 320px; column-gap: 24px; }
        .rule-list li { display: flex; gap: 8px; align-items: baseline; padding: 2px 0; break-inside: avoid; }
        .rule-list label { flex: 1; font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 12.5px;
          overflow-wrap: anywhere; }
        .rule-list .n { color: var(--muted); font-variant-numeric: tabular-nums; }
        .scroll { overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; }
        th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
        th { white-space: nowrap; background: var(--panel); }
        th button.sort { background: none; border: 0; padding: 0; color: inherit; font: inherit; font-weight: 600;
          cursor: pointer; }
        th .arrow { display: inline-block; min-width: 1.2em; padding-left: 4px; color: var(--muted); }
        td.loc, td.rule { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 12.5px; }
        td.rule { white-space: nowrap; } td.loc { overflow-wrap: anywhere; min-width: 16ch; }
        td.msg { min-width: 32ch; }
        button.hide { margin-left: 6px; padding: 0 6px; border: 1px solid var(--line); border-radius: 4px;
          background: none; color: var(--muted); font: 11px/1.6 -apple-system, sans-serif; cursor: pointer; }
        button.hide:hover, button.hide:focus-visible { color: var(--fg); }
        .sev { font-weight: 600; text-transform: capitalize; }
        .sev.error { color: var(--error); } .sev.warning { color: var(--warning); } .sev.info { color: var(--info); }
        pre { background: var(--panel); padding: 12px; border-radius: 6px; overflow: auto; font-size: 12.5px; }
        button.action { padding: 6px 12px; border: 1px solid var(--line); border-radius: 6px;
          background: var(--panel); color: var(--fg); font: inherit; cursor: pointer; }
        .empty { color: var(--muted); padding: 24px 0; }
        #sentinel { height: 1px; }
        [hidden] { display: none !important; }
        </style></head>
        <body><header><h1>
        """#

    /// Closes the heading and opens the summary line.
    private static let summaryStart = #"""
        </h1><p class="summary">
        """#

    /// The tabs, the rule panel, the table view, and the JSON view, up to the findings data.
    private static let views = #"""
        </p>
        <nav class="tabs" role="tablist">
        <button role="tab" aria-selected="true" data-view="table">Table</button>
        <button role="tab" aria-selected="false" data-view="json">JSON</button></nav></header>
        <main><section id="table-view">
        <div class="controls"><label class="search"><span class="visually-hidden">Filter findings</span>
        <input type="search" id="query" placeholder="Filter by rule, file, or message"></label>
        <fieldset><legend class="visually-hidden">Severities to show</legend>
        <label><input type="checkbox" class="sev-filter" value="error" checked> Errors</label>
        <label><input type="checkbox" class="sev-filter" value="warning" checked> Warnings</label>
        <label><input type="checkbox" class="sev-filter" value="info" checked> Info</label></fieldset>
        <label id="category-filter" hidden>OWASP category <select id="category">
        <option value="">All categories</option></select></label>
        <span class="count" id="count" role="status" aria-live="polite"></span></div>
        <details id="rule-panel"><summary>Rules <span class="count" id="rule-summary"></span></summary>
        <div class="controls"><button class="action" id="show-all">Show all rules</button>
        <button class="action" id="copy-config">Copy as .bouncer</button>
        <span class="count" id="config-status" role="status"></span></div>
        <ul class="rule-list" id="rule-list"></ul></details>
        <div class="scroll"><table><thead><tr>
        <th data-key="severity" aria-sort="ascending"><button class="sort" data-key="severity">Severity<span
        class="arrow" aria-hidden="true">▲</span></button></th>
        <th data-key="rule" aria-sort="none"><button class="sort" data-key="rule">Rule<span
        class="arrow" aria-hidden="true"></span></button></th>
        <th data-key="location" aria-sort="none"><button class="sort" data-key="location">Location<span
        class="arrow" aria-hidden="true"></span></button></th>
        <th data-key="message" aria-sort="none"><button class="sort" data-key="message">Message<span
        class="arrow" aria-hidden="true"></span></button></th>
        </tr></thead><tbody id="rows-body"></tbody></table></div>
        <div id="sentinel" aria-hidden="true"></div>
        <p><button class="action" id="more" hidden>Show more</button></p>
        <p class="empty" id="empty" hidden>No findings match.</p></section>
        <section id="json-view" hidden><div class="controls">
        <button class="action" id="copy">Copy JSON</button><button class="action" id="download">Download JSON</button>
        <span class="count" id="copied" role="status"></span></div>
        <p class="note" id="json-note"></p><pre id="json-preview" tabindex="0"></pre></section></main>
        <script type="application/json" id="report-data">
        """#

    /// Closes the findings data, then the script that renders, filters, and sorts the table a page at a time,
    /// runs the rule panel, and builds the JSON preview, copy, and download from the compact rows.
    private static let script = #"""
        </script>
        <script>
        "use strict";
        const data = JSON.parse(document.getElementById("report-data").textContent);
        const { files, filePaths, rules, severities, rows } = data;
        // Optional, for rules that carry an OWASP category: data.owasp[ruleIndex] is the category or null.
        const owasp = Array.isArray(data.owasp) ? data.owasp : [];
        const PAGE = 100, $ = id => document.getElementById(id), fmt = n => n.toLocaleString();
        const storageKey = "bouncer-report:hidden-rules:" + (data.key || "");
        let sortKey = "severity", ascending = true, matching = new Int32Array(0), rendered = 0, lowered = null;
        const hidden = new Set(loadHidden());
        const ruleCounts = new Int32Array(rules.length), ruleSeverity = new Int32Array(rules.length).fill(99);
        rows.forEach(r => { ruleCounts[r[2]]++; ruleSeverity[r[2]] = Math.min(ruleSeverity[r[2]], r[3]); });
        const fileRank = rankOf(files), ruleRank = rankOf(rules);
        const ruleOrder = rules.map((_, i) => i)
          .sort((a, b) => ruleCounts[b] - ruleCounts[a] || ruleRank[a] - ruleRank[b]);

        function rankOf(list) {
          const rank = new Int32Array(list.length);
          list.map((_, i) => i).sort((a, b) => list[a] < list[b] ? -1 : list[a] > list[b] ? 1 : 0)
            .forEach((index, position) => { rank[index] = position; });
          return rank;
        }
        function loadHidden() {
          try {
            const saved = JSON.parse(localStorage.getItem(storageKey) || "[]");
            return Array.isArray(saved) ? saved : [];
          } catch { return []; }
        }
        function saveHidden() {
          try { localStorage.setItem(storageKey, JSON.stringify([...hidden].sort())); } catch { /* no storage */ }
        }

        function matches() {
          const query = $("query").value.trim().toLowerCase(), category = $("category").value;
          const shownSeverity = severities
            .map(s => document.querySelector(`.sev-filter[value="${s}"]`)?.checked ?? true);
          const ruleOn = rules.map((id, i) => !hidden.has(id) && (!category || owasp[i] === category));
          const fileHit = files.map(f => f.toLowerCase().includes(query));
          const ruleHit = rules.map(id => id.toLowerCase().includes(query));
          if (query && !lowered) lowered = rows.map(r => r[4].toLowerCase());
          const located = query.includes(":"), out = new Int32Array(rows.length);
          let count = 0;
          for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            if (!shownSeverity[r[3]] || !ruleOn[r[2]]) continue;
            if (query && !fileHit[r[0]] && !ruleHit[r[2]] && !lowered[i].includes(query)
              && !(located && (files[r[0]] + ":" + r[1]).toLowerCase().includes(query))) continue;
            out[count++] = i;
          }
          return out.subarray(0, count);
        }
        function compare(a, b) {
          const x = rows[a], y = rows[b];
          if (sortKey === "severity") return x[3] - y[3];
          if (sortKey === "rule") return ruleRank[x[2]] - ruleRank[y[2]];
          if (sortKey === "location") return fileRank[x[0]] - fileRank[y[0]] || x[1] - y[1];
          return x[4] < y[4] ? -1 : x[4] > y[4] ? 1 : 0;
        }
        function sorted(indices) {
          if (sortKey === "severity" && ascending) return indices; // the rows are embedded in this order
          const sign = ascending ? 1 : -1;
          return indices.sort((a, b) => sign * compare(a, b) || a - b);
        }

        const observer = "IntersectionObserver" in window ? new IntersectionObserver(entries => {
          if (entries.some(entry => entry.isIntersecting) && rendered < matching.length) renderMore();
        }, { rootMargin: "600px 0px" }) : null;
        function refresh() {
          matching = sorted(matches());
          rendered = 0;
          $("rows-body").replaceChildren();
          renderMore();
        }
        function renderMore() {
          const end = Math.min(rendered + PAGE, matching.length), fragment = document.createDocumentFragment();
          for (; rendered < end; rendered++) fragment.appendChild(rowElement(matching[rendered]));
          $("rows-body").appendChild(fragment);
          $("count").textContent = "Showing " + fmt(rendered) + " of " + fmt(matching.length)
            + " matching (" + fmt(rows.length) + " total)";
          $("empty").hidden = matching.length > 0;
          $("more").hidden = rendered >= matching.length;
          if (!observer || rendered >= matching.length) return;
          observer.unobserve($("sentinel")); // observing again reports whether it's still in view
          observer.observe($("sentinel"));
        }
        function rowElement(i) {
          const r = rows[i], tr = document.createElement("tr"), rule = rules[r[2]];
          cell(tr, "sev " + severities[r[3]], severities[r[3]]);
          const hide = document.createElement("button");
          hide.className = "hide"; hide.dataset.rule = rule; hide.textContent = "hide";
          hide.title = "Hide this rule"; hide.setAttribute("aria-label", "Hide rule " + rule);
          cell(tr, "rule", rule).append(hide);
          cell(tr, "loc", files[r[0]] + ":" + r[1]);
          cell(tr, "msg", r[4]);
          return tr;
        }
        function cell(tr, className, text) {
          const td = tr.insertCell();
          td.className = className; td.textContent = text;
          return td;
        }

        function buildRulePanel() {
          $("rule-list").replaceChildren(...ruleOrder.map(i => {
            const li = document.createElement("li"), label = document.createElement("label");
            const box = document.createElement("input"), only = document.createElement("button");
            box.type = "checkbox"; box.className = "rule-toggle"; box.value = rules[i];
            label.append(box, " " + rules[i]);
            const count = document.createElement("span"), severity = document.createElement("span");
            count.className = "n"; count.textContent = fmt(ruleCounts[i]);
            const severityName = severities[ruleSeverity[i]] || "";
            severity.className = "sev " + severityName; severity.textContent = severityName;
            only.className = "hide"; only.dataset.only = rules[i]; only.textContent = "only this";
            only.setAttribute("aria-label", "Show only rule " + rules[i]);
            li.append(label, count, severity, only);
            return li;
          }));
          syncRulePanel();
        }
        function syncRulePanel() {
          document.querySelectorAll(".rule-toggle").forEach(box => { box.checked = !hidden.has(box.value); });
          const count = rules.filter(id => hidden.has(id)).length;
          $("rule-summary").textContent = "(" + fmt(rules.length) + (count ? ", " + fmt(count) + " hidden)" : ")");
        }
        function rulesChanged() {
          saveHidden();
          syncRulePanel();
          refresh();
        }
        $("rule-list").addEventListener("change", event => {
          const box = event.target.closest(".rule-toggle");
          if (!box) return;
          if (box.checked) hidden.delete(box.value); else hidden.add(box.value);
          rulesChanged();
        });
        $("rule-list").addEventListener("click", event => {
          const only = event.target.closest("button[data-only]");
          if (!only) return;
          hidden.clear();
          rules.forEach(id => { if (id !== only.dataset.only) hidden.add(id); });
          rulesChanged();
        });
        $("rows-body").addEventListener("click", event => {
          const hide = event.target.closest("button.hide");
          if (hide) { hidden.add(hide.dataset.rule); rulesChanged(); }
        });
        $("show-all").addEventListener("click", () => { hidden.clear(); rulesChanged(); });
        $("copy-config").addEventListener("click", () => {
          const ids = [...hidden].sort();
          if (!ids.length) { $("config-status").textContent = "No rules are hidden."; return; }
          const config = { rules: Object.fromEntries(ids.map(id => [id, { enabled: false }])) };
          copyText(() => JSON.stringify(config, null, 2), $("config-status"));
        });

        function findingJSON(i) {
          const r = rows[i], quote = JSON.stringify;
          return '    {\n      "filePath" : ' + quote(filePaths[r[0]]) + ',\n      "line" : ' + r[1]
            + ',\n      "message" : ' + quote(r[4]) + ',\n      "ruleID" : ' + quote(rules[r[2]])
            + ',\n      "severity" : ' + quote(severities[r[3]]) + "\n    }";
        }
        function jsonParts(limit) {
          const count = Math.min(limit, rows.length), parts = ['{\n  "findings" : [\n'];
          for (let start = 0; start < count; start += 10000) {
            const chunk = [];
            for (let i = start; i < Math.min(start + 10000, count); i++) chunk.push(findingJSON(i));
            parts.push((start ? ",\n" : "") + chunk.join(",\n"));
          }
          const coverage = typeof data.coverage === "number"
            ? ',\n  "overallLineCoveragePercent" : ' + data.coverage : "";
          parts.push("\n  ]" + coverage + "\n}");
          return parts;
        }
        async function copyText(makeText, status) {
          try { await navigator.clipboard.writeText(makeText()); status.textContent = "Copied."; }
          catch { status.textContent = "Couldn't copy. Try Download JSON, or copy from a browser that allows it."; }
        }
        function showJSONPreview() {
          if ($("json-preview").textContent) return;
          $("json-note").textContent = rows.length > PAGE
            ? "Preview of the first " + fmt(PAGE) + " of " + fmt(rows.length)
              + " findings. Copy or download for all of them."
            : "All " + fmt(rows.length) + " findings, in the shape --format json prints.";
          $("json-preview").textContent = jsonParts(PAGE).join("");
        }
        $("copy").addEventListener("click", () => copyText(() => jsonParts(Infinity).join(""), $("copied")));
        $("download").addEventListener("click", () => {
          const link = document.createElement("a");
          link.href = URL.createObjectURL(new Blob(jsonParts(Infinity), { type: "application/json" }));
          link.download = "bouncer-report.json";
          link.click();
          setTimeout(() => URL.revokeObjectURL(link.href), 60000);
        });

        document.querySelectorAll("button.sort").forEach(button => button.addEventListener("click", () => {
          ascending = sortKey === button.dataset.key ? !ascending : true;
          sortKey = button.dataset.key;
          document.querySelectorAll("th[data-key]").forEach(th => {
            const active = th.dataset.key === sortKey;
            th.setAttribute("aria-sort", active ? (ascending ? "ascending" : "descending") : "none");
            th.querySelector(".arrow").textContent = active ? (ascending ? "▲" : "▼") : "";
          });
          refresh();
        }));
        let searchTimer = 0;
        $("query").addEventListener("input", () => {
          clearTimeout(searchTimer);
          searchTimer = setTimeout(refresh, 200);
        });
        document.querySelectorAll(".sev-filter").forEach(box => box.addEventListener("change", refresh));
        $("category").addEventListener("change", refresh);
        $("more").addEventListener("click", renderMore);
        document.querySelectorAll(".tabs button").forEach(tab => tab.addEventListener("click", () => {
          const tabs = document.querySelectorAll(".tabs button");
          tabs.forEach(other => other.setAttribute("aria-selected", other === tab));
          $("table-view").hidden = tab.dataset.view !== "table";
          $("json-view").hidden = tab.dataset.view !== "json";
          if (tab.dataset.view === "json") showJSONPreview();
        }));
        const categories = [...new Set(owasp.filter(Boolean))].sort();
        categories.forEach(category => $("category").add(new Option(category, category)));
        $("category-filter").hidden = categories.length === 0;
        buildRulePanel();
        refresh();
        </script></body></html>
        """#
}

/// The parts of the HTML report that show code: styles for the expanded finding, its code preview, and its diff,
/// and the script that expands findings, highlights code, diffs examples, and shows each rule's rationale as a
/// tooltip. Code from the report is untrusted, so the script only ever puts it on the page as text nodes.
extension HTMLTemplate {
    /// Styles for expanded findings, code blocks, syntax colours, diff lines, and the rationale tooltip. The
    /// colours pass WCAG AA contrast on every code background, in both the light and the dark theme.
    static let codeStyles = #"""
        :root { --code-bg: #f6f8fa; --hit-bg: #fff8c5; --hit-bar: #9a6700; --del-bg: #ffebe9; --add-bg: #dafbe1;
          --del-sign: #a40e26; --add-sign: #116329; --t-k: #cf222e; --t-s: #0a3069; --t-n: #0550ae;
          --t-c: #57606a; }
        @media (prefers-color-scheme: dark) { :root { --code-bg: #0f0f11; --hit-bg: #332b00; --hit-bar: #e3b341;
          --del-bg: #4c1c22; --add-bg: #103a20; --del-sign: #ffa198; --add-sign: #7ee787; --t-k: #ff7b72;
          --t-s: #a5d6ff; --t-n: #79c0ff; --t-c: #a3abb6; } }
        tr.finding { cursor: pointer; }
        tr.finding:hover td { background: var(--panel); }
        tr.finding td.sev::before { content: "▸ "; content: "▸ " / ""; color: var(--muted); }
        tr.finding[aria-expanded="true"] td.sev::before { content: "▾ "; content: "▾ " / ""; }
        tr.finding[aria-expanded="true"] td { border-bottom: 0; }
        tr.detail td { max-width: 0; padding: 0 8px 16px 24px; }
        .detail-body { position: sticky; left: 24px; max-width: calc(100vw - 72px); }
        .why { text-decoration: underline dotted; text-underline-offset: 3px; cursor: help; }
        #why-tip { position: fixed; z-index: 10; max-width: min(420px, calc(100vw - 16px)); padding: 8px 10px;
          border-radius: 6px; background: var(--fg); color: var(--bg); font-size: 13px; line-height: 1.4;
          box-shadow: 0 4px 16px rgba(0, 0, 0, 0.25); }
        .why-text { margin: 4px 0 8px; max-width: 90ch; }
        figure.code { margin: 8px 0; border: 1px solid var(--line); border-radius: 6px; background: var(--code-bg);
          overflow: hidden; }
        figure.code figcaption { padding: 4px 10px; font-size: 12px; color: var(--muted);
          border-bottom: 1px solid var(--line); }
        figure.example figcaption strong { color: var(--fg); }
        .lines { display: grid; overflow-x: auto; padding: 4px 0; tab-size: 4;
          font: 12.5px/1.5 ui-monospace, Menlo, Consolas, monospace; }
        .line { display: flex; white-space: pre; }
        .line .gutter { flex: none; min-width: 5ch; padding: 0 8px; text-align: right; color: var(--t-c);
          user-select: none; }
        .line .sign { flex: none; width: 2ch; user-select: none; font-weight: 600; }
        .line .text { padding-right: 12px; }
        .line.hit { background: var(--hit-bg); box-shadow: inset 3px 0 var(--hit-bar); }
        .line.hit .sign::before { content: "›"; content: "›" / ""; color: var(--hit-bar); }
        .line.del { background: var(--del-bg); } .line.add { background: var(--add-bg); }
        .line.del .sign::before { content: "-"; content: "-" / ""; color: var(--del-sign); }
        .line.add .sign::before { content: "+"; content: "+" / ""; color: var(--add-sign); }
        .t-k { color: var(--t-k); } .t-s { color: var(--t-s); } .t-n { color: var(--t-n); }
        .t-c { color: var(--t-c); font-style: italic; }
        .ws, .trunc { color: var(--t-c); } .trunc { font-style: italic; }

        """#

    /// Expands findings into their code, rationale, and diff; highlights code with a small tokenizer per
    /// language; diffs rule examples line by line; and shows each rule's rationale as a tooltip on hover, focus,
    /// or tap. It runs inside `script`'s element, before `scriptEnd` renders the table.
    static let codeScript = #"""
        // Code previews, rationale tooltips, and fix or example diffs. Code is untrusted: every piece of it
        // reaches the page through textContent or a text node, never as markup.
        const FIX = 5, COLUMNS = 4, TIP_GAP = 6, TIP_DELAY = 150;
        const TRUNCATED = "\u0000", expanded = new Set(), diffOpen = new Set();
        const SPOKEN = { hit: "Finding line: ", del: "Removed: ", add: "Added: " };
        let tipAnchor = null, tipTimer = 0, source = null;

        const C_WORDS = "auto bool break case catch char class const continue default delete do double else enum "
          + "explicit extern false float for friend goto if inline int long namespace new nullptr operator private "
          + "protected public register return short signed sizeof static struct switch template this throw true try "
          + "typedef typename union unsigned using virtual void volatile while";
        const C_STYLE = { line: ["//"], block: ["/*", "*/"], strings: ['"', "'"] };
        const HASH_STYLE = { line: ["#"], block: null, strings: ['"', "'"] };
        const LANGUAGES = {
          swift: { ...C_STYLE, strings: ['"""', '"'], words: "actor any as associatedtype async await break case "
            + "catch class continue default defer deinit do else enum extension fallthrough false fileprivate final "
            + "for func guard if import in init inout internal is let lazy nil open operator override private "
            + "protocol public repeat rethrows return self Self some static struct subscript super switch throw "
            + "throws true try typealias var weak where while" },
          js: { ...C_STYLE, strings: ['"', "'", "`"], words: "abstract any as async await boolean break case catch "
            + "class const constructor continue debugger declare default delete do else enum export extends false "
            + "finally for from function get if implements import in instanceof interface keyof let new null "
            + "number of private protected public readonly return set static string super switch this throw true "
            + "try type typeof undefined var void while yield" },
          python: { ...HASH_STYLE, strings: ['"""', "'''", '"', "'"], words: "False None True and as assert async "
            + "await break class continue def del elif else except finally for from global if import in is lambda "
            + "nonlocal not or pass raise return self try while with yield" },
          go: { ...C_STYLE, strings: ['"', "'", "`"], words: "break case chan const continue default defer else "
            + "fallthrough false for func go goto if import interface iota map nil package range return select "
            + "struct switch true type var" },
          rust: { ...C_STYLE, strings: ['"'], words: "as async await break const continue crate dyn else enum extern "
            + "false fn for if impl in let loop match mod move mut pub ref return self Self static struct super "
            + "trait true type unsafe use where while" },
          php: { ...C_STYLE, line: ["//", "#"], caseless: true, words: "abstract and array as break case catch class "
            + "clone const continue declare default do echo else elseif empty enum extends false final finally fn "
            + "for foreach function global if implements include instanceof interface isset match namespace new "
            + "null or private protected public readonly require require_once return static switch throw trait "
            + "true try unset use var while yield" },
          c: { ...C_STYLE, words: C_WORDS },
          objc: { ...C_STYLE, words: C_WORDS + " @class @end @implementation @interface @property @protocol "
            + "@selector id nil NO self super YES" },
          java: { ...C_STYLE, strings: ['"""', '"', "'"], words: "abstract boolean break byte case catch char class "
            + "const continue default do double else enum extends false final finally float for if implements "
            + "import instanceof int interface long native new null package private protected public record "
            + "return short static super switch synchronized this throw throws true try var void volatile while" },
          shell: { ...HASH_STYLE, words: "case do done elif else esac export fi for function if in local readonly "
            + "return select then until while" },
          powershell: { ...HASH_STYLE, block: ["<#", "#>"], caseless: true, words: "begin break catch class "
            + "continue do else elseif end exit filter finally for foreach function if in param process return "
            + "switch throw trap try until while $true $false $null" },
          sql: { line: ["--"], block: ["/*", "*/"], strings: ["'", '"'], caseless: true, words: "add all alter and "
            + "as asc between by case create delete desc distinct drop else end exists from group having in index "
            + "inner insert into is join key left like limit not null on or order outer primary references right "
            + "select set table then union update values view when where with" },
          json: { line: [], block: null, strings: ['"'], words: "true false null" },
          yaml: { ...HASH_STYLE, words: "true false null yes no on off" },
        };
        const ALIASES = {};
        ("swift:swift js:js,jsx,mjs,cjs,ts,tsx,mts,cts,javascript,typescript python:py,pyi,python go:go,golang "
          + "rust:rs,rust php:php,phtml c:c,h,cc,cpp,cxx,hpp,hh,c++ objc:m,mm,objc,objective-c java:java "
          + "shell:sh,bash,zsh,shell powershell:ps1,psm1,psd1,powershell,pwsh sql:sql json:json,jsonc yaml:yml,yaml")
          .split(" ").forEach(entry => {
            const [language, names] = entry.split(":");
            names.split(",").forEach(name => { ALIASES[name] = language; });
          });
        const NUMBER = "\\b(?:0[xXbBoO][\\da-fA-F_]+|\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?)";
        const WORD = "[A-Za-z_$@][\\w$]*";

        function grammarNamed(name) {
          const spec = LANGUAGES[ALIASES[String(name).toLowerCase()]];
          if (spec && !spec.regex) compile(spec);
          return spec || null;
        }
        function grammarForPath(path) {
          const base = path.slice(path.lastIndexOf("/") + 1), dot = base.lastIndexOf(".");
          return dot > 0 ? grammarNamed(base.slice(dot + 1)) : null;
        }
        function compile(spec) {
          const comments = spec.line.map(mark => escapeRegExp(mark) + "[^\\n]*");
          const [open, close] = (spec.block || []).map(escapeRegExp);
          if (open) comments.push(open + "[\\s\\S]*?(?:" + close + "|$)");
          const groups = [comments.join("|") || "(?!)", spec.strings.map(stringPattern).join("|"), NUMBER, WORD];
          spec.regex = new RegExp(groups.map(group => "(" + group + ")").join("|"), "g");
          spec.keywords = new Set(spec.words.split(" ").map(word => spec.caseless ? word.toLowerCase() : word));
        }
        function escapeRegExp(text) { return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
        function stringPattern(quote) {
          const q = escapeRegExp(quote), body = quote.length > 1 || quote === "`" ? "[^\\\\]" : "[^\\\\\\n]";
          return q + "(?:\\\\[\\s\\S]|(?!" + q + ")" + body + ")*(?:" + q + ")?";
        }
        function tokenize(text, spec) {
          const tokens = [];
          let last = 0;
          for (const match of spec ? text.matchAll(spec.regex) : []) {
            if (match.index > last) tokens.push(["", text.slice(last, match.index)]);
            tokens.push([tokenClass(match, spec), match[0]]);
            last = match.index + match[0].length;
          }
          if (last < text.length) tokens.push(["", text.slice(last)]);
          return tokens;
        }
        function tokenClass(match, spec) {
          if (match[1]) return "t-c";
          if (match[2]) return "t-s";
          if (match[3]) return "t-n";
          return spec.keywords.has(spec.caseless ? match[0].toLowerCase() : match[0]) ? "t-k" : "";
        }
        function tokenLines(texts, spec) {
          const lines = [[]];
          for (const [className, text] of tokenize(texts.join("\n"), spec)) {
            text.split("\n").forEach((piece, n) => {
              if (n) lines.push([]);
              if (piece) lines[lines.length - 1].push([className, piece]);
            });
          }
          return lines;
        }
        // Highlights the old side (context and removed lines) and the new side (context and added lines) of a
        // block separately, so a comment or string opened on one side can't run into the other.
        function highlightRows(models, kinds, spec) {
          const out = [];
          for (const skip of ["add", "del"]) {
            const picked = kinds.map((_, n) => n).filter(n => kinds[n] !== skip);
            if (!picked.length) continue;
            tokenLines(picked.map(n => models[n].text), spec).forEach((tokens, k) => { out[picked[k]] ||= tokens; });
          }
          return out;
        }

        function element(tag, className, text) {
          const node = document.createElement(tag);
          node.className = className; node.textContent = text;
          return node;
        }
        function prepare(raw, showSpaces) {
          const cut = raw.endsWith(TRUNCATED), text = cut ? raw.slice(0, -1) : raw;
          const trail = showSpaces ? /[ \t]*$/.exec(text)[0] : "";
          return { text: text.slice(0, text.length - trail.length), trail, cut };
        }
        function appendMarks(target, model) {
          if (model.trail) {
            const marks = element("span", "ws", model.trail.replace(/ /g, "·").replace(/\t/g, "→"));
            marks.title = "Trailing whitespace";
            target.append(marks);
          }
          if (model.cut) target.append(element("span", "trunc", " … (line cut for length)"));
        }
        function lineElement(row, tokens, model) {
          const line = element("div", "line " + row.kind, ""), text = element("span", "text", "");
          if (SPOKEN[row.kind]) line.append(element("span", "visually-hidden", SPOKEN[row.kind]));
          line.append(element("span", "gutter", row.number || ""), element("span", "sign", ""));
          tokens.forEach(([className, piece]) => text.append(className
            ? element("span", className, piece) : document.createTextNode(piece)));
          appendMarks(text, model);
          line.append(text);
          return line;
        }
        function codeBlock(caption, spec, rows) {
          const figure = element("figure", "code", ""), lines = element("div", "lines", "");
          const showSpaces = rows.some(row => row.kind === "del" || row.kind === "add");
          const models = rows.map(row => prepare(row.raw, showSpaces));
          const tokens = highlightRows(models, rows.map(row => row.kind), spec);
          lines.tabIndex = 0;
          lines.append(...rows.map((row, n) => lineElement(row, tokens[n], models[n])));
          figure.append(caption, lines);
          return figure;
        }
        function caption(strong, rest) {
          const node = element("figcaption", "", "");
          node.append(element("strong", "", strong), rest);
          return node;
        }

        // The code previews are the biggest part of the data, so they're parsed the first time a row expands.
        function previews() {
          if (!source) source = JSON.parse($("report-code").textContent);
          return source;
        }
        // Source lines come from the file's runs, [firstLine, [line, ...]], found by binary search.
        function sourceLine(file, n) {
          const chunks = (previews().code || [])[file] || [];
          let low = 0, high = chunks.length - 1;
          while (low < high) {
            const mid = (low + high + 1) >> 1;
            if (chunks[mid][0] <= n) low = mid; else high = mid - 1;
          }
          const chunk = chunks[low];
          return chunk && n >= chunk[0] ? chunk[1][n - chunk[0]] : undefined;
        }
        function contextRows(file, from, to, hit) {
          const out = [];
          for (let n = Math.max(1, from); n <= to; n++) {
            const raw = sourceLine(file, n);
            if (raw !== undefined) out.push({ kind: n === hit ? "hit" : "", number: n, raw });
          }
          return out;
        }
        function previewRows(r) {
          if (sourceLine(r[0], r[1]) === undefined) return [];
          const context = previews().context || 0;
          return contextRows(r[0], r[1] - context, r[1] + context, r[1]);
        }
        function fixRows(r) {
          const [start, removed, added] = r[FIX], end = start + removed.length, context = previews().context || 0;
          return [...contextRows(r[0], start - context, start - 1),
            ...removed.map((raw, n) => ({ kind: "del", number: start + n, raw })),
            ...added.map(raw => ({ kind: "add", number: "", raw })),
            ...contextRows(r[0], end, end + context - 1)];
        }
        function exampleRows(example) {
          const split = text => text.replace(/\n$/, "").split("\n");
          return diffLines(split(example[1]), split(example[2]));
        }
        function diffLines(a, b) {
          const table = lcsTable(a, b), out = [];
          let i = 0, j = 0;
          while (i < a.length || j < b.length) {
            if (i < a.length && j < b.length && a[i] === b[j]) { out.push({ kind: "", raw: a[i++] }); j++; }
            else if (j === b.length || (i < a.length && table[i + 1][j] >= table[i][j + 1])) {
              out.push({ kind: "del", raw: a[i++] });
            } else out.push({ kind: "add", raw: b[j++] });
          }
          return out;
        }
        function lcsTable(a, b) {
          const table = Array.from({ length: a.length + 1 }, () => new Int32Array(b.length + 1));
          for (let i = a.length - 1; i >= 0; i--) {
            for (let j = b.length - 1; j >= 0; j--) {
              table[i][j] = a[i] === b[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
            }
          }
          return table;
        }

        function withDetail(tr, i) {
          const fragment = document.createDocumentFragment();
          tr.setAttribute("aria-controls", "detail-" + i);
          fragment.append(tr, detailRow(i));
          return fragment;
        }
        function detailRow(i) {
          const tr = element("tr", "detail", ""), td = tr.insertCell();
          tr.id = "detail-" + i; td.colSpan = COLUMNS;
          td.append(detailBody(i));
          return tr;
        }
        function detailBody(i) {
          const r = rows[i], box = element("div", "detail-body", ""), preview = previewRows(r);
          if (why[r[2]]) box.append(element("p", "why-text", "Why it matters: " + why[r[2]]));
          if (preview.length) box.append(codeBlock(caption("Code", " at " + files[r[0]] + ":" + r[1]),
            grammarForPath(files[r[0]]), preview));
          appendDiff(box, i);
          if (!box.childNodes.length) box.append(element("p", "note", "No code, rationale, or example to show."));
          return box;
        }
        function appendDiff(box, i) {
          const kind = rows[i][FIX] ? "fix" : examples[rows[i][2]] ? "example" : "";
          if (!kind) return;
          const open = diffOpen.has(i);
          const button = element("button", "action diff-toggle", (open ? "Hide " : "Show ") + kind);
          button.dataset.row = i;
          button.setAttribute("aria-expanded", open);
          button.setAttribute("aria-controls", "diff-" + i);
          box.append(button);
          if (open) box.append(diffBlock(i));
        }
        function diffBlock(i) {
          const r = rows[i], example = examples[r[2]], block = r[FIX]
            ? codeBlock(caption("Fix", " for this code in " + files[r[0]]), grammarForPath(files[r[0]]), fixRows(r))
            : codeBlock(caption("Example", " in " + example[0] + " for " + rules[r[2]] + ", not from your code"),
              grammarNamed(example[0]), exampleRows(example));
          block.id = "diff-" + i;
          block.classList.add(r[FIX] ? "fix" : "example");
          return block;
        }
        function toggleRow(tr) {
          const i = Number(tr.dataset.row), open = !expanded.has(i);
          if (open) expanded.add(i); else { expanded.delete(i); diffOpen.delete(i); }
          tr.setAttribute("aria-expanded", open);
          if (open) { tr.after(detailRow(i)); tr.setAttribute("aria-controls", "detail-" + i); return; }
          document.getElementById("detail-" + i)?.remove();
          tr.removeAttribute("aria-controls");
        }
        function toggleDiff(i) {
          if (diffOpen.has(i)) diffOpen.delete(i); else diffOpen.add(i);
          const fresh = detailRow(i);
          document.getElementById("detail-" + i).replaceWith(fresh);
          fresh.querySelector("button.diff-toggle").focus();
        }
        function rowClicked(event) {
          const toggle = event.target.closest("button.diff-toggle"), anchor = event.target.closest(".why");
          if (toggle) return toggleDiff(Number(toggle.dataset.row));
          if (anchor) return showTip(anchor);
          const tr = event.target.closest("tr.finding");
          if (tr && !String(window.getSelection())) toggleRow(tr);
        }
        $("rows-body").addEventListener("keydown", event => {
          if (event.key !== "Enter" && event.key !== " ") return;
          if (!event.target.matches("tr.finding")) return;
          event.preventDefault();
          toggleRow(event.target);
        });

        // The rationale tooltip is one fixed element outside the table, so the table's scroll box never clips
        // it. Screen readers get the same text from hidden per-rule elements the anchors' aria-describedby names.
        function buildWhyTexts() {
          $("why-texts").replaceChildren(...why.map((text, i) => {
            const node = element("span", "", text || "");
            node.id = "why-" + i;
            return node;
          }));
        }
        function whyAnchor(index) {
          const anchor = element("span", "why", rules[index]);
          anchor.tabIndex = 0; anchor.dataset.rule = index;
          anchor.setAttribute("aria-describedby", "why-" + index);
          return anchor;
        }
        function showTip(anchor) {
          clearTimeout(tipTimer);
          $("why-tip").textContent = why[anchor.dataset.rule];
          $("why-tip").hidden = false;
          tipAnchor = anchor;
          placeTip();
        }
        // Puts the tooltip below its anchor, or above it when there's no room below, and keeps it on screen.
        function placeTip() {
          const tip = $("why-tip"), box = tipAnchor?.getBoundingClientRect();
          if (!box) return;
          if (box.bottom < 0 || box.top > window.innerHeight) return hideTip();
          const below = window.innerHeight - box.bottom > tip.offsetHeight + TIP_GAP;
          tip.style.top = Math.max(TIP_GAP, below ? box.bottom + TIP_GAP : box.top - tip.offsetHeight - TIP_GAP) + "px";
          const left = Math.min(box.left, window.innerWidth - tip.offsetWidth - TIP_GAP);
          tip.style.left = Math.max(TIP_GAP, left) + "px";
        }
        function hideTip() {
          clearTimeout(tipTimer);
          $("why-tip").hidden = true;
          tipAnchor = null;
        }
        function hideTipSoon() {
          clearTimeout(tipTimer);
          tipTimer = setTimeout(hideTip, TIP_DELAY);
        }
        $("rows-body").addEventListener("mouseover", event => {
          const anchor = event.target.closest(".why");
          if (anchor === tipAnchor) clearTimeout(tipTimer); else if (anchor) showTip(anchor);
        });
        $("rows-body").addEventListener("mouseout", event => {
          if (tipAnchor && event.target.closest(".why") === tipAnchor) hideTipSoon();
        });
        $("why-tip").addEventListener("mouseenter", () => clearTimeout(tipTimer));
        $("why-tip").addEventListener("mouseleave", hideTipSoon);
        $("rows-body").addEventListener("focusin", event => {
          if (event.target.matches(".why")) showTip(event.target);
        });
        $("rows-body").addEventListener("focusout", event => { if (event.target === tipAnchor) hideTip(); });
        document.addEventListener("keydown", event => { if (event.key === "Escape") hideTip(); });
        document.addEventListener("click", event => { if (!event.target.closest(".why, #why-tip")) hideTip(); });
        window.addEventListener("scroll", placeTip, true);
        window.addEventListener("resize", placeTip);

        """#
}

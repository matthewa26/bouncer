#!/usr/bin/env bash
# Drives `bouncer mcp` through a whole agent session against a throwaway git repo and checks every response:
# each stdout line must be one JSON-RPC response, and nothing else may reach stdout.
#
# Usage: Scripts/test-mcp.sh path/to/bouncer
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 BINARY" >&2
    exit 2
fi
BINARY=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

REPO="$WORK/repo"
mkdir -p "$REPO/Sources" "$WORK/home"
cd "$REPO"
git init -q
git config user.email test@example.com
git config user.name Test
cat > .bouncer <<'JSON'
{ "rules": { "force-unwrap": { "severity": "error" } } }
JSON
cat > Sources/Unwrap.swift <<'SWIFT'
/// Reads a value.
///
/// - Parameter value: The value.
/// - Returns: The value, unwrapped.
func read(_ value: Int?) -> Int {
    value!
}
SWIFT
cat > Sources/Numbers.swift <<'SWIFT'
/// Adds numbers.
///
/// - Parameter value: The value.
/// - Returns: The sum.
func add(_ value: Int) -> Int {
    let first = value + 7_919
    let second = first * 104_729
    let third = second - 15_485_863
    let fourth = third + 32_452_843
    return fourth + 49_979_687
}
SWIFT
for name in Alpha Beta Gamma Delta Epsilon; do
    printf '/// Reads.\n///\n/// - Parameter value: The value.\n/// - Returns: It.\n' > "Sources/$name.swift"
    printf 'func read%s(_ value: Int?) -> Int {\n    value!\n}\n' "$name" >> "Sources/$name.swift"
done
git add -A
git commit -qm initial

HOME="$WORK/home" python3 - "$BINARY" "$REPO" <<'PY'
import json, subprocess, sys

binary, repo = sys.argv[1], sys.argv[2]
server = subprocess.Popen(
    [binary, "mcp", repo], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=repo
)
next_id = 0

def fail(message):
    server.kill()
    sys.exit("FAIL: " + message)

def send(method, params=None, notification=False):
    global next_id
    message = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        message["params"] = params
    if not notification:
        next_id += 1
        message["id"] = next_id
    server.stdin.write(json.dumps(message) + "\n")
    server.stdin.flush()
    if notification:
        return None
    line = server.stdout.readline()
    try:
        response = json.loads(line)
    except ValueError:
        fail("stdout line isn't JSON: %r" % line)
    if response.get("id") != next_id or response.get("jsonrpc") != "2.0":
        fail("unexpected response: %r" % line)
    return response

def call(name, arguments=None):
    result = send("tools/call", {"name": name, "arguments": arguments or {}})["result"]
    text = result["content"][0]["text"]
    print("--- %s %s (%d chars)%s\n%s" % (name, json.dumps(arguments or {}), len(text),
                                         " [error]" if result["isError"] else "", text))
    return text, result["isError"]

def expect(condition, message):
    if not condition:
        fail(message)

client = {"name": "test-mcp", "version": "0"}
init = send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": client})
expect(init["result"]["serverInfo"]["name"] == "bouncer", "initialize names the server")
expect("scan" in init["result"].get("instructions", ""), "initialize teaches the loop")
send("notifications/initialized", notification=True)

tools = {tool["name"]: tool for tool in send("tools/list")["result"]["tools"]}
names = {"scan", "status", "findings", "verify", "check", "explain_rule"}
expect(set(tools) == names, "tools/list: %s" % sorted(tools))
expect("cursor" in tools["findings"]["inputSchema"]["properties"], "findings takes a cursor")

text, error = call("findings")
expect(error and "No scan yet. Call scan first." in text, "findings before a scan is an error")

text, error = call("scan")
for _ in range(600):
    if not text.startswith("Scanning"):
        break
    text, error = call("status")
expect(not error and "findings:" in text and "Results from" in text, "status ends with the summary")
expect("force-unwrap" in text, "the summary names the top rules")

text, error = call("findings", {"max_chars": 220})
expect(len(text) <= 220, "findings fits max_chars")
expect("Next cursor: f" in text, "a truncated page names the next cursor")
cursor = text.rsplit("Next cursor: ", 1)[1].rstrip(".")
text, error = call("findings", {"max_chars": 220, "cursor": cursor})
expect(not error and len(text) <= 220 and "Showing" in text, "the cursor fetches the next page")

text, error = call("findings", {"rule": ["force-unwrap"], "severity": "error"})
expect("Sources/Unwrap.swift" in text and "magic-number" not in text, "findings filters by rule and severity")

text, error = call("findings", {"severity": "fatal"})
expect(error and "severity must be one of" in text, "a bad argument is an error")

with open(repo + "/Sources/Unwrap.swift", "w") as source:
    source.write("/// Reads a value.\n///\n/// - Parameter value: The value.\n/// - Returns: The value, or 0.\n"
                 "func read(_ value: Int?) -> Int {\n    value ?? 0\n}\n")
text, error = call("verify", {"files": ["Sources/Unwrap.swift"]})
expect(not error and "1 fixed" in text and "0 new" in text, "verify reports the fixed finding")
expect("refresh on the next scan" in text, "verify notes project-wide rules")
text, error = call("findings", {"rule": "force-unwrap"})
expect("Sources/Unwrap.swift" not in text and "5 findings" in text, "verify updated the in-memory result")

text, error = call("explain_rule", {"id": "force-unwrap"})
expect(not error and "force-unwrap" in text, "explain_rule explains a known rule")
text, error = call("explain_rule", {"id": "force-unwarp"})
expect(error and "Did you mean" in text and "force-unwrap" in text, "explain_rule suggests close IDs")

with open(repo + "/Sources/Staged.swift", "w") as source:
    source.write("/// Reads.\n///\n/// - Parameter value: The value.\n/// - Returns: It.\n"
                 "func readAgain(_ value: Int?) -> Int {\n    value!\n}\n")
subprocess.run(["git", "add", "Sources/Staged.swift"], cwd=repo, check=True)
text, error = call("check")
expect(not error and "would block the commit" in text and "Sources/Staged.swift" in text, "check lists blockers")
subprocess.run(["git", "reset", "-q", "Sources/Staged.swift"], cwd=repo, check=True)
text, error = call("check")
expect(not error and "Nothing blocks the commit." in text, "check passes with nothing staged")

with open(repo + "/.bouncer", "w") as config:
    config.write('{ "rules": { "force-unwrap": { "severity": "error" } }, "agent": { "refresh": "immediate" } }')
text, error = call("scan")
for _ in range(600):
    if not text.startswith("Scanning"):
        break
    text, error = call("status")
expect("reused findings for" in text and "saved run not used" not in text, "the agent section keeps the saved run")
with open(repo + "/Sources/Alpha.swift", "w") as source:
    source.write("/// Reads.\n///\n/// - Parameter value: The value.\n/// - Returns: It.\n"
                 "func readAlpha(_ value: Int?) -> Int {\n    value ?? 1\n}\n")
text, error = call("findings", {"rule": "force-unwrap"})
expect(text.startswith("Re-checked 1 changed file.") and "Sources/Alpha.swift" not in text, "immediate refresh")
text, error = call("status")
expect(text.startswith("Results are current."), "immediate refresh with nothing changed")

server.stdin.close()
rest = server.stdout.read()
expect(rest == "", "stdout holds nothing but responses: %r" % rest)
expect(server.wait(timeout=60) == 0, "the server exits cleanly at end of input")
print("PASS: bouncer mcp")
PY

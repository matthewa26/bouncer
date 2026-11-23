# Contributing

Thanks for helping. Changes land through pull requests against `main`:

1. Fork the repository and create a branch.
2. Make your change, with tests for any new rule or behavior. If it adds or ships a feature, update its row in
   [ROADMAP.md](ROADMAP.md), the source of truth for feature status. A shipped row is ✅ with the first release
   that has it; an unshipped row is ⬜ with `planned <version>` or `backlog`.
3. Check it locally:
   ```sh
   swift build
   swift test                      # includes an end-to-end `bouncer mcp` session against the built binary
   .build/debug/bouncer review .   # Bouncer checks itself; this must report no errors
   sh Scripts/check-roadmap.sh     # every roadmap row says when it ships
   ```
4. Open a pull request. CI runs on macOS, Linux, and Windows and must pass. For a first-time
   contributor, a maintainer approves the CI run before it starts.

Every pull request needs the maintainer's review before it's merged, and pull requests are
squash-merged. Bouncer holds itself to its own rules: functions of at most 10 logical lines,
a complete `///` doc comment on every function, and lines of at most 120 characters. See the
[rule catalog](https://matthewa26.github.io/bouncer/documentation/bouncercore/rulecatalog)
for what each rule checks.

By contributing, you agree that your contribution is licensed under the project's
[GPL-3.0-or-later](LICENSE) license.

Report security issues privately, as described in [SECURITY.md](SECURITY.md).

# Vendored from tree-sitter-python

This directory's `parser.c`, `scanner.c`, `tree_sitter/*.h`, and `include/python.h`
are vendored from [tree-sitter/tree-sitter-python](https://github.com/tree-sitter/tree-sitter-python),
MIT licensed (see `LICENSE`).

They are vendored, rather than consumed as a normal SPM dependency, because
that repository's `Package.swift` detects `scanner.c` with a working-directory-relative
`FileManager.fileExists(atPath:)` check that fails when the package is resolved
as a dependency of another package (the check runs against the root package's
working directory, not `tree-sitter-python`'s own directory). That silently
drops the external scanner Python's grammar needs for indentation-sensitive
tokenizing, producing undefined symbols at link time. Vendoring with an
explicit, unconditional source list avoids the bug entirely.

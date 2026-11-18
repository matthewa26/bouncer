# Vendored from tree-sitter-javascript

This directory's grammar sources are vendored unmodified from
[tree-sitter/tree-sitter-javascript](https://github.com/tree-sitter/tree-sitter-javascript) v0.25.0,
MIT licensed (see `LICENSE`): `src/{parser,scanner}.c`, its `tree_sitter/*.h`, and
`include/javascript.h` (from upstream's `bindings/swift`).

They are vendored rather than consumed as an SPM dependency for the same reason as
`CTreeSitterPython` (see its NOTICE.md): upstream's `Package.swift` adds `scanner.c` only if a working-directory-relative `FileManager.fileExists` check passes, which fails when resolved as a dependency and drops the external scanner.

# Vendored from tree-sitter-objc

This directory's grammar sources are vendored unmodified from
[tree-sitter-grammars/tree-sitter-objc](https://github.com/tree-sitter-grammars/tree-sitter-objc) v3.0.2
(commit 18802acf31d0b5c1c1d50bdbc9eb0e1636cab9ed), MIT licensed (see `LICENSE`): `src/parser.c`, its
`tree_sitter/*.h`, and `include/objc.h` (from upstream's `bindings/swift`). The grammar has no external
scanner.

They are vendored rather than consumed as an SPM dependency for the same reason as the other
`CTreeSitter*` targets (see `CTreeSitterPython/NOTICE.md`): upstream packages resolve their C sources
relative to the working directory, which breaks when they're resolved as a dependency.

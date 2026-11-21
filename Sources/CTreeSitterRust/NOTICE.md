# Vendored from tree-sitter-rust

This directory's grammar sources are vendored unmodified from
[tree-sitter/tree-sitter-rust](https://github.com/tree-sitter/tree-sitter-rust) v0.24.2
(commit 77a3747266f4d621d0757825e6b11edcbf991ca5), MIT licensed (see `LICENSE`): `src/{parser,scanner}.c`,
its `tree_sitter/*.h`, and `include/rust.h` (from upstream's `bindings/swift`).

They are vendored rather than consumed as an SPM dependency for the same reason as the other
`CTreeSitter*` targets (see `CTreeSitterPython/NOTICE.md`): upstream packages resolve their C sources
relative to the working directory, which breaks when they're resolved as a dependency.

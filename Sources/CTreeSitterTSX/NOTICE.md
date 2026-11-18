# Vendored from tree-sitter-typescript

This directory's grammar sources are vendored unmodified from
[tree-sitter/tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript) v0.23.2,
MIT licensed (see `LICENSE`): `tsx/src/{parser,scanner}.c`, its `tree_sitter/*.h`, `common/scanner.h`, and
`include/tsx.h` (from upstream's `bindings/swift`).

They are vendored rather than consumed as an SPM dependency, like
`CTreeSitterPython`, because upstream's `Package.swift` depends on `ChimeHQ/SwiftTreeSitter`, a different package identity from the `tree-sitter/swift-tree-sitter` Bouncer uses, which would pull in a second `SwiftTreeSitter` module. TSX is a separate grammar from TypeScript (JSX syntax), so it gets its own target.

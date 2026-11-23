# Vendored from tree-sitter-php

This directory's grammar sources are vendored unmodified from
[tree-sitter/tree-sitter-php](https://github.com/tree-sitter/tree-sitter-php) v0.25.2
(commit c1e13490bd656b8869cd47e6f74997ed46750a08), MIT licensed (see `LICENSE`): the `php` grammar's
`php/src/{parser,scanner}.c` and its `tree_sitter/*.h`, `common/scanner.h`, and `include/php.h` (from upstream's
`bindings/swift`). Upstream's other grammar, `php_only`, isn't vendored: real `.php` files interleave HTML, which only
`php` parses, so `include/php.h`'s `tree_sitter_php_only` declaration has no definition and must not be called.

They are vendored rather than consumed as an SPM dependency for the same reason as the other
`CTreeSitter*` targets (see `CTreeSitterPython/NOTICE.md`). The upstream directory layout is kept so `scanner.c`'s
`../../common/scanner.h` include resolves unchanged.

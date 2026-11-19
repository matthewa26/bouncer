# Security policy

Please report vulnerabilities privately, through GitHub's
[private vulnerability reporting](https://github.com/matthewa26/bouncer/security/advisories/new),
not in a public issue. Include what you found, how to reproduce it, and which version or commit
you tested.

The parts where a vulnerability matters most:

- `install.ps1`, which users pipe into a shell, and the downloads it verifies against
  `SHA256SUMS`.
- The release and documentation workflows, which publish releases and the site.
- Anything that runs commands from a repository's `.bouncer` file, such as hooks.

Fixes go into the latest release only.

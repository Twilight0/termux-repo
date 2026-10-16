# copilot-cli (unofficial Termux port)

GitHub Copilot CLI — the agentic `copilot` terminal assistant — packaged for
Termux.

> **Unofficial.** This is a community package, not affiliated with or endorsed
> by GitHub. It installs and runs the official upstream binary; GitHub supports
> Linux/macOS/Windows only, and Termux/Android is not a supported platform.

## How it works

Upstream ships a single ~180 MB **glibc-linked Node SEA** executable per
architecture. Termux uses bionic, so the binary cannot run as-is. This package:

1. ships only the `copilot` launcher and these docs (the binary is **not**
   redistributed — see *Licensing* below),
2. downloads the official `copilot-linux-<arch>.tar.gz` plus `SHA256SUMS.txt`
   during `postinst` and **verifies the checksum**,
3. patches the ELF interpreter to Termux's glibc loader
   (`$PREFIX/glibc/lib/ld-linux-*.so.*`),
4. runs it through a launcher that sets up `LD_LIBRARY_PATH`, the Termux CA
   bundle, and `TMPDIR`, and disables upstream self-update.

No `proot` is involved.

## Requirements

- `glibc-repo` and `glibc` (pulled in automatically) — install with
  `pkg install glibc-repo` if APT complains.
- An active **GitHub Copilot subscription**.

## Authentication

See `auth-token.example` in this directory. In short, export a fine-grained PAT
(with the **Copilot Requests** permission) as `COPILOT_GITHUB_TOKEN`, or run
`copilot login --device-code`.

## Known limitations on Termux

- Interactive TUI: supported.
- Voice mode: upstream does not build it for `linux-arm64`.
- Image/PDF pasting and the `sharp` image pipeline: not available.
- Prefer remote (HTTP/SSE) MCP servers; local stdio servers may pick the wrong
  Node because the launcher prepends the glibc prefix to `PATH`.

## Files

| Path | Purpose |
|------|---------|
| `$PREFIX/bin/copilot` | launcher (this package) |
| `$PREFIX/lib/copilot-cli/copilot` | upstream binary (downloaded at install) |
| `~/.copilot/` | Copilot CLI config, sessions, and cache |
| `~/.cache/copilot/` | caches; override with `COPILOT_CACHE_HOME` |

## Licensing / redistribution

The upstream Copilot CLI license restricts standalone redistribution. This
package therefore **does not redistribute** the binary: it is fetched from
GitHub's official release at install time and pinned to a version, and
self-update is disabled so the packaged install stays consistent with APT.

## Updating

The package pins a known-good upstream version (`VERSION`). To move it, bump
`VERSION`, rebuild, and smoke-test before publishing. Upstream releases very
frequently (`copilot update` is disabled here), so APT is the update channel.

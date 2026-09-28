# Twilight0's Termux Repository

Custom APT repository for Termux with packages not available in the official repos.

## Quick Install

```bash
curl -sL https://twilight0.github.io/termux-repo/install.sh | bash
```

## Packages

| Package | Description | Arch |
|---------|-------------|------|
| `wrangler` | Cloudflare Workers CLI (cloud API only, no local dev) | all |
| `9router` | Free AI coding router with smart fallback | all |
| `curl-cffi` | Browser TLS impersonation for Python (yt-dlp --impersonate) | all |
| `yt-dlp-git` | Video/audio downloader, git master snapshot | all |
| `agentty` | Blazing-fast AI pair programmer, native Bionic build | aarch64 |
| `pipx` | Install/run Python apps in isolated venvs | all |
| `yt-tui` | Curses TUI for yt-dlp (search, queue, history) | all |
| `muse-code` | Meta's Muse Code AI agent with session/MCP tools | aarch64, x86_64 |
| `opencode` | AI-powered coding assistant (v2, no proot) | aarch64, x86_64 |
| `opencode-legacy` | AI-powered coding assistant (legacy v1, proot) | aarch64, x86_64 |
| `antigravity-cli` | Google Antigravity CLI | aarch64, x86_64 |
| `oh-my-pi` | Oh-My-Pi plugin manager for Pi | aarch64, x86_64 |

## Documentation & Guides

- [**DNS Forwarding & Caching Guide (DNS_FORWARDING.md)**](DNS_FORWARDING.md): Running AdGuard Home and dnsmasq on unrooted/rooted Android with client configuration for local and LAN devices.
- [**Package Research & Architecture (PACKAGE_RESEARCH.md)**](PACKAGE_RESEARCH.md): Technical teardown of VA39 patching, Bun seccomp SIGSYS workarounds, workerd stubbing, and evaluations for future packages.

## opencode v2 packaging notes

`opencode` (currently 2.0.18) ships as an upstream glibc Linux binary plus a small
preload shim. `opencode-legacy` keeps the v1 line (1.18.x) untouched for users who
need the old TUI/plugin API. Both provide the `opencode` command and declare mutual
`Conflicts`, so only one can be installed at a time.

Runtime dependencies (v2): `glibc-repo`, `glibc`, `ripgrep`, `jq`, `nodejs-lts`
(for local MCP servers). No `proot`. Build-time dependency: a glibc-targeting C
compiler for the shim (`gcc-glibc` on Termux, `gcc-aarch64-linux-gnu` on a build
host); `build.sh` refuses to compile it with Termux's bionic gcc (verified via a
`libc.so.6` linkage check).

Why a shim is needed: v2 runs a background service that the client starts by
re-executing `[process.execPath, "serve", ...]`. Under an explicit glibc-loader
invocation `execPath` is the *loader*, so the spawn degrades to
`ld-linux "serve" ...` and dies with exit 127 (`serve: error while loading shared
libraries`). `--standalone` fails the same way. Verified with `strace` on-device.

Why not `patchelf` the interpreter instead: Bun single-executable bundles locate
their embedded payload via internal offsets (same reason the binary must never be
stripped). Rewriting program headers with `patchelf --set-interpreter/--set-rpath`
corrupts that layout — the patched binary segfaults immediately, while the
untouched binary runs. Only byte-identical, in-place edits are safe, and no
writable short absolute path exists on Android for an INTERP symlink, so the
loader-invocation + shim route is used instead.

Shim design (`packages/opencode/helper/execshim.c`): intercepts `execve`,
`execvpe`, `posix_spawn`, `posix_spawnp`; rewrites only loader+`"serve"` spawns
to `[loader, $OPENCODE_BIN, serve, ...]`; everything else passes through. Child
hygiene matters because the preload is inherited: a constructor unsets
`LD_PRELOAD` before the runtime snapshots its environment, and rewritten spawns
get an `LD_PRELOAD`-free envp — verified via `/proc/<serve-pid>/environ`, so
bionic shell tools and MCP servers start cleanly. The wrapper (`helper/opencode.sh`)
also unsets Termux's `termux-exec` preload (incompatible with glibc processes),
sets `SSL_CERT_FILE`, and exports `OPENCODE_DISABLE_AUTOUPDATE=1` so upstream
self-update can never replace the packaged install.

v1 needed a `faccessat2`→`faccessat` opcode patch plus `proot` because its Bun
runtime hard-coded syscall 439 (SIGSYS on Android seccomp). The v2 binary contains
zero `faccessat2` references (opcode scan + dynamic symbols use
`faccessat@GLIBC_2.17`), so neither the patch nor `proot` is required. The managed
service shuts down with the TUI under normal quit; after a kill, stop leftovers
with `opencode service stop` (or `pkill -f 'opencode.*serve'`).

## Notes

- **wrangler** is an npm wrapper. `wrangler dev` is not supported (no local workerd runtime). Use `wrangler deploy` instead.
- **opencode** (v2), **antigravity-cli**, and **oh-my-pi** require `glibc-repo` and `glibc`. Install with `pkg install glibc-repo`.
- **opencode-legacy** (v1) additionally requires `proot` for syscall emulation. **muse-code** requires `proot` too. On x86_64 devices without AVX2, `qemu-user-x86-64` is suggested for muse-code.
- **opencode** (v2) and **opencode-legacy** (v1) conflict: both provide the `opencode` command, so only one may be installed at a time. apt will offer to remove the other on switch.

## Adding Packages

Each package lives in `packages/<name>/` with either:
- `DEBIAN/control` + `DEBIAN/postinst` (for simple npm/meta packages)
- `build.sh` (for packages that download prebuilt binaries)

## CI

GitHub Actions builds all packages weekly and deploys to GitHub Pages. Push to `main` to trigger a build.

## Uninstall

```bash
curl -sL https://twilight0.github.io/termux-repo/uninstall.sh | bash
```

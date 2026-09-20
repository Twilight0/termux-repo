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
| `muse-code` | Meta's Muse Code AI agent with session/MCP tools | aarch64, x86_64 |
| `opencode` | AI-powered coding assistant | aarch64 |
| `antigravity-cli` | Google Antigravity CLI (VA39-patched) | aarch64 |
| `oh-my-pi` | Oh-My-Pi plugin manager for Pi | aarch64 |

## Notes

- **wrangler** is an npm wrapper. `wrangler dev` is not supported (no local workerd runtime). Use `wrangler deploy` instead.
- **opencode**, **antigravity-cli**, and **oh-my-pi** require `glibc-repo` and `glibc`. Install with `pkg install glibc-repo`.
- **muse-code** requires `proot` for syscall emulation. On x86_64 devices without AVX2, `qemu-user-x86-64` is suggested.

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

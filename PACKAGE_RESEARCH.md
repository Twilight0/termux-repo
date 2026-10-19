# Package Research & Architecture Notes

This document details the architectural analysis, technical challenges, solutions, and packaging feasibility for packages maintained in `Twilight0/termux-repo` and future candidate software.

---

## 1. Maintained Packages: Analysis & Solutions

### `antigravity-cli`
- **Description:** Google's Antigravity CLI AI coding agent.
- **Upstream:** Google Cloud manifests (`linux_arm64.json` / `linux_amd64.json`).
- **Binary Format:** Dynamically-linked glibc Go executable (~210 MB uncompressed, ~40 MB UPX-compressed).
- **Android / Termux Hurdles:**
  1. **39-bit Virtual Address (VA) Space (ARM64):** Android ARM64 kernels limit user-space virtual addresses to 39 bits (`1UL << 39 = 512 GB`). Upstream Go runtime and TCMalloc assume 48-bit VA space, crashing on startup on Android.
  2. **Missing `faccessat2` Syscall:** Older Android kernels (< 5.8) or seccomp profiles return `ENOSYS` for `faccessat2` (syscall 439 on aarch64), crashing standard glibc runtime.
  3. **Third-party Bootstrapper Coupling:** Previous builds relied on `wallentx/antigravity-cli-termux`, which bundled an ARM64-only Bionic binary with hardcoded auto-update network calls.
- **Implemented Solutions:**
  - **`helper/patch_va39.py`:** Standalone Python script that disassembles 32-bit ARM64 machine instructions and patches page alignment bitmasks, mmap parameters, and redirects `faccessat2` $\to$ `faccessat`.
  - **Architecture Branching:** `patch_va39.py` is applied exclusively to `aarch64`. On `x86_64`, standard 48-bit address space exists natively and the official binary is packaged unpatched.
  - **Decoupled POSIX Launcher (`helper/agy.sh`):** A clean shell script that unsets Bionic `LD_PRELOAD`, sets `GODEBUG="netdns=cgo"`, points `SSL_CERT_FILE` to Termux certificates, and dynamically resolves the appropriate glibc loader (`ld-linux-aarch64.so.1` or `ld-linux-x86-64.so.2`).
  - **Dependencies:** `glibc-repo`, `glibc`, `resolv-conf`, `ca-certificates`.

---

### `opencode` (v2, current)
- **Description:** AnomalyCo's terminal-based AI coding assistant, v2 line (client/service architecture, OpenTUI interface).
- **Upstream:** Versioned glibc tarballs at `opencode.ai/files/bin/<ver>/` (2.0.29 packaged; also published as npm `@opencode/cli-<target>`). v2 is NOT on GitHub releases (latest there is the v1 line). Single `opencode` binary per platform — no separate `serve` binary exists anywhere upstream.
- **Binary Format:** Bun single-executable bundle (JavaScriptCore). Despite aggregator claims of a "Node.js rewrite", binary forensics on 2.0.6/2.0.18 (arm64 + x64, glibc + musl) show `$bunfs` chunks, `uv_*@@BUN_1.2` symbol versioning, and embedded TypeScript compiler plus `@opentui/core`. NEEDED on the glibc arm64 build is only `libc`, `libpthread`, `libdl`, `libm`.
- **Android / Termux Hurdles:**
  1. **Binary Stripping / Restructuring Corruption:** Bun locates its embedded payload via internal offsets. `strip` truncates it — and `patchelf --set-interpreter/--set-rpath` breaks it too: the patched binary segfaults immediately while the untouched binary runs (verified on-device). Only byte-identical, in-place edits are safe.
  2. **Service self-spawn via `process.execPath`:** every client mode (TUI, `--standalone`, `run`) starts the background service as `[execPath, "serve", ...]`. Under an explicit loader invocation `execPath` is the *loader*, so the child becomes `ld-linux "serve" ...` and dies with exit 127 (`serve: error while loading shared libraries`). Confirmed with `strace -f -e execve` on-device; `--standalone` spawns `[loader, "serve", "--stdio", "--port", "0"]` and fails the same way.
  3. **Bionic / glibc Linker Collision:** Termux's `LD_PRELOAD=libtermux-exec-ld-preload.so` crashes any glibc process (`version 'LIBC' not found`); it must be unset before loader invocation — including for the glibc toolchain itself at build time.
- **Implemented Solutions (`packages/opencode/`):**
  - **Exec-spawn shim (`helper/execshim.c`):** glibc `LD_PRELOAD` library intercepting `execve`/`execvpe`/`posix_spawn`/`posix_spawnp`; rewrites only loader+`"serve"` spawns to `[loader, $OPENCODE_BIN, serve, ...]`. Child hygiene: a constructor unsets `LD_PRELOAD` before the runtime snapshots its environment, and rewritten spawns get an `LD_PRELOAD`-free envp (verified via `/proc/<serve-pid>/environ`), so bionic shell tools and MCP servers start cleanly.
  - **Untouched binary, no proot:** ships the upstream binary as-is. v2 contains zero `faccessat2` references (opcode scan + `faccessat@GLIBC_2.17` in dynsym), so the v1 opcode patch and `proot` are both unnecessary.
  - **Wrapper (`helper/opencode.sh`):** unsets Bionic preloads, sets `OPENCODE_BIN`, `LD_PRELOAD` (shim), `SSL_CERT_FILE`, `OPENCODE_DISABLE_AUTOUPDATE=1` (upstream self-update must never replace the packaged install), `OPENCODE_DISABLE_TUI_AUDIO=1`.
  - **Shim build guard:** `build.sh` compiles the shim with a glibc-targeting compiler only (`gcc-glibc` on Termux, `gcc-aarch64-linux-gnu` on CI/build hosts) and aborts unless the output links `libc.so.6`.
  - **Dependencies:** `glibc-repo`, `glibc`, `ripgrep`, `jq`, `nodejs-lts` (local MCP servers).
- **On-device validation (2026-09-28, aarch64, Android 16):** `--version` / `--help` / `serve` / `session list --server` all exit 0 via the loader; the TUI runs under a pty with its managed service self-spawning from the installed binary; no seccomp/SIGSYS failures. The actual `.deb` was built on-device (`opencode_2.0.18-1_termux_aarch64.deb`), installed over v1, and the packaged flow re-verified. Agent execution (`run`) was not exercised (spends provider tokens).
- **Notes:** the managed service shuts down with the TUI on normal quit; after a kill, use `opencode service stop`. V1 plugin implementations and `tui.json` do not carry over (v2 uses a new plugin API and global `cli.json`). The earlier `opencode-legacy` (frozen v1 line) packaging has been retired.

---

### `oh-my-pi` (`omp`)
- **Description:** Extension manager and CLI agent for Pi.
- **Upstream:** GitHub releases (`oh-my-pi`).
- **Binary Format:** Bun single-executable application.
- **Android / Termux Hurdles:**
  - Same kernel seccomp restrictions as OpenCode: blocked syscalls result in `Unknown signal 31` (`SIGSYS`).
- **Implemented Solutions:**
  - Replaced legacy C bootstrapper with a `proot` wrapper (`helper/omp.sh`) to emulate restricted syscalls and bridge the glibc loader.
  - Added `proot` to package dependencies.

---

### `copilot-cli` (unofficial GitHub Copilot CLI)
- **Description:** GitHub's agentic terminal assistant (`copilot`). Distinct from the deprecated `gh copilot` extension.
- **Upstream:** GitHub Releases (`github/copilot-cli`); npm `@github/copilot`. Unofficial port; not affiliated with GitHub. Supported OS upstream is Linux/macOS/Windows only — Termux/Android is out of scope (open issues #1257, #3333; termux-packages closed it `wontfix`, #30004).
- **Binary Format:** A **Node SEA** (Node 24, `v8_enable_sandbox=0`, `pointer_compression=0`), single glibc-linked executable per arch (~186 MB, `copilot-linux-<arch>.tar.gz`). Ships glibc **and** musl variants; **no android/bionic** variant, and no armv7.
- **Android / Termux Hurdles:**
  1. **glibc-only runtime:** the SEA (and its embedded Rust `runtime.node` addon, which needs up to `GLIBC_2.34`) cannot load on bionic. Plain `npm install -g @github/copilot` is a dead end — the npm package is a ~13 KB stub whose `os`-gated optional deps never match `android`.
  2. **Self-update clobbers the install:** `autoUpdate` defaults on and `copilot update` rewrites the tree, bypassing any loader patching.
  3. **Blocked syscalls (potential):** `faccessat2` (439) via glibc, `close_range` (436) via Rust `std::process::Command` in `runtime.node`. Node/libuv core is Android-safe.
  4. **Redistribution:** the license restricts standalone redistribution, so the binary must not be bundled in the `.deb`.
- **Implemented Solutions (`packages/copilot-cli/`):**
  - **Download-at-install, never bundled:** a tiny `.deb` ships only the launcher + docs; `postinst` fetches `copilot-linux-<arch>.tar.gz` + `SHA256SUMS.txt`, **verifies the checksum**, then installs the binary to `$PREFIX/lib/copilot-cli/`.
  - **`patchelf --set-interpreter` to the glibc loader** (`$PREFIX/glibc/lib/ld-linux-*.so.*`). Safe here (the SEA is `0x10000`-aligned and patchelf-clean, unlike Bun SEBs/Go), and it keeps `process.execPath` pointing at the real binary, avoiding self-spawn breakage. No 39-bit VA patch needed.
  - **Launcher (`helper/copilot.sh`):** unsets bionic `LD_PRELOAD`, sets `LD_LIBRARY_PATH=$PREFIX/glibc/lib`, `SSL_CERT_FILE`/`NODE_EXTRA_CA_CERTS` to the Termux CA bundle, `TMPDIR`, and `COPILOT_AUTO_UPDATE=false`.
  - **DNS works natively:** `glibc-repo` symlinks `resolv.conf`/`hosts` into `$PREFIX/glibc/etc`, so no DNS `LD_PRELOAD` shim is required (verified on-device: a glibc `getaddrinfo` resolves). The `postinst` adds `$PREFIX/glibc/etc/nsswitch.conf` if absent.
  - **Auth without a keyring:** Termux has no D-Bus Secret Service; use `COPILOT_GITHUB_TOKEN` (fine-grained PAT with the *Copilot Requests* permission) or `copilot login --device-code`.
  - **Dependencies:** `glibc-repo`, `glibc`, `gcc-libs-glibc` (libstdc++), `patchelf`, `ripgrep` (bundled `rg` has no Android build), `git`, `bash`, `curl`, `ca-certificates`. No `proot`.
- **Notes:** version is pinned in `packages/copilot-cli/VERSION`. Upstream releases very frequently (~35–65/month), so APT is the update channel and self-update is disabled. Reference implementations: `Thr45hx/copilot-cli-termux-native` (patchelf + shims) and the glibc recipe in issue #3333. Rejected alternatives: a bionic-native port (`nishantn15/copilot-termux`, permanent re-patching treadmill) and `proot-distro` (ptrace latency + SIGKILL risk under MCP load).

---

### `muse-code`
- **Description:** Meta's terminal AI coding agent powered by Muse Spark.
- **Upstream:** Meta CDN.
- **Binary Format:** Prebuilt Linux executable (`aarch64` and `x86_64`).
- **Android / Termux Hurdles:**
  - Relies on glibc and specific syscall behavior.
- **Implemented Solutions:**
  - Wrapped with `proot` for universal syscall compatibility across Android kernels.
  - Bundled interactive curses session picker (`muse-session`) and MCP manager (`muse-mcp`).

---

## 2. Candidate Packages: Feasibility & Roadmap

### 1. `adguardhome` (AdGuard Home)
- **Feasibility:** **High (Recommended)**
- **Architecture:** Standalone Golang binary.
- **Why It Fits Termux:**
  - Compiles the DNS server, DoH/DoT/DoQ engines, adblock rule evaluator, and complete React web interface into a single executable.
  - Zero external runtime dependencies.
  - Fully relocatable via CLI flags:
    ```bash
    AdGuardHome -c "$PREFIX/etc/adguardhome/AdGuardHome.yaml" -w "$PREFIX/var/lib/adguardhome"
    ```
  - Perfect for unrooted devices: can be configured to listen on port `5353` for DNS and `3000` for the Web UI.
- **Packaging Plan:**
  - Download official upstream `linux-arm64` and `linux-amd64` binaries.
  - Install binary to `$PREFIX/lib/adguardhome/AdGuardHome`.
  - Install starter configuration template and launcher script to `$PREFIX/bin/adguardhome`.

---

### 2. `dnsmasq`
- **Feasibility:** **High (Recommended)**
- **Architecture:** Lightweight C daemon.
- **Why It Fits Termux:**
  - Ultra-low memory usage (< 5 MB RAM).
  - Fast in-memory TTL caching and negative query caching.
  - Supports loading local host blocklists (`addn-hosts=...`).
  - No complex runtime requirements (builds cleanly with standard C library).
- **Packaging Plan:**
  - Build binary with Bionic or glibc.
  - Provide production-ready default config `$PREFIX/etc/dnsmasq.conf` configured for port `5353` (non-root safe).

---

### 3. `pi-hole` (Pi-hole)
- **Feasibility:** **Low (Not Recommended for Native Packaging)**
- **Architecture:** Distributed multi-service stack:
  1. `pihole-FTL` (C daemon, customized dnsmasq fork).
  2. Web server (`lighttpd` or `nginx`).
  3. PHP runtime (`php-cgi` + SQLite3).
  4. Core Bash scripts managing blocklists and systemd services.
- **Why Native Packaging Is Discouraged:**
  - Hardcodes FHS system paths (`/etc/pihole`, `/etc/dnsmasq.d`, `/var/www/html/admin`, `/var/log/pihole`).
  - Orchestrating a web server, PHP FastCGI daemon, and FTL DNS daemon natively inside Termux requires high maintenance and fragile path patching.
  - **Better Alternative:** Users who strictly require Pi-hole should run it inside a standard Debian/Ubuntu container using `proot-distro install debian`.

---

### 4. `dnsproxy` (AdGuard Team)
- **Feasibility:** **High**
- **Architecture:** Simple Go CLI utility.
- **Features:** A lightweight DNS proxy that supports DoH, DoT, DoQ, and DNSCrypt with in-memory caching.
- **Use Case:** Ideal for users who want encrypted DNS forwarding and caching in Termux without the web UI overhead of AdGuard Home.

---

### 5. `cloudflared` (Cloudflare)
- **Feasibility:** **High**
- **Architecture:** Single Go executable.
- **Features:** Provides Cloudflare Tunnel (remote access to local services without opening firewall ports) and a local DNS-over-HTTPS proxy (`cloudflared proxy-dns --port 5353`).

---

### 6. `curl_cffi` (curl-impersonate Python binding)
- **Feasibility:** **High**
- **Upstream:** PyPI `curl_cffi` + in-house wheel builder `Twilight0/curl-cffi-builder` (CI cross-compiles Android `arm64-v8a` / `armeabi-v7a` / `x86_64`, iOS, manylinux, macOS, Windows + Kodi add-on; latest builder release v0.16.3).
- **What It Is:** Python binding bundling patched curl + BoringSSL to impersonate browser TLS fingerprints. A library, not a CLI — end-user value comes through dependents, chiefly `yt-dlp --impersonate` (unlocks Cloudflare-protected pages) and scrapers facing bot checks.
- **Wheel Coverage (verified 2026-09-23):** v0.16.3 ships Android wheels for **cp310 through cp314** (all three ABIs each), so the current Termux Python 3.14 is covered (`cp314-cp314-android_21_arm64_v8a`). Note the Android wheels are version-locked per CPython (unlike the `abi3` manylinux/macOS ones), so each Termux Python bump needs the matching builder target to exist — worth a CI check that keeps matrix and Termux in step.
- **Packaging Plan:**
  - Unlike the npm `all`-arch packages, this must be **arch-specific**: `postinst` pip-installs the per-arch wheel URL from the builder releases (`arm64_v8a` on `aarch64`, `x86_64` on `x86_64`).
  - `Depends: python`; version pin must track builder releases, not PyPI.
  - Natural companion to a future `yt-dlp` package (its `--impersonate` flag lights up only when `curl_cffi` is importable).

---

### 7. `hermes-agent` (Nous Research AI agent) — DO NOT PACKAGE
- **Upstream already ships an official, signed Termux APT repo:** `https://hermes-assets.nousresearch.com/releases/termux/<channel>` with suites `hermes-stable` / `hermes-canary`, signed by key fingerprint `C572 B5FD D1A2 9CCF A9A9 12B6 840B 0848 E139 156D`. Their `install.sh` refuses Termux outright and points at `pkg install hermes-agent`.
- **Why not us:** a same-named deb would collide with theirs on any device with both repos — and theirs is the better build (native bionic, bundled Python 3.14 + Node + uv + ripgrep + ffmpeg, Android API-24 wheels; no proot/glibc wrapping needed). aarch64-only.
- **Status (late Sept 2026):** upstream docs banner says the Termux package is **currently broken, fix in progress**. Revisit when the banner lifts; even then the right move is a docs pointer (or opt-in repo line), not a repackaged deb.

---

## 3. Additional Candidate Packages: Developer & AI Tools

### AI/ML

| Package | Description | Notes |
|---------|-------------|-------|
| `claude-code` | Anthropic's Claude CLI | Similar to opencode |
| `aider` | AI pair programming, git-aware | Python/Go |
| `ollama` | Local LLM runner | Complex on Termux, high demand |
| `mlx` | Apple ML framework | Cross-platform TBD |

### Dev Tools

| Package | Description | Notes |
|---------|-------------|-------|
| `lazygit` | Terminal git UI | Go binary, very popular |
| `lazydocker` | Terminal docker UI | Go binary |
| `atuin` | Shell history sync | Encrypted, cross-machine |
| `mise` | Polyglot version manager | asdf replacement |

### Cloud/Infra

| Package | Description | Notes |
|---------|-------------|-------|
| `rclone` | Cloud storage sync | Google Drive, S3, etc. |
| `terraform` | Infrastructure as Code | HashiCorp binaries |
| `flux` | GitOps CD tool | Weaveworks |

### Modern CLI Utils

| Package | Description | Notes |
|---------|-------------|-------|
| `bat` | Cat with syntax highlighting | Rust binary |
| `fd` | Find alternative | Rust binary |
| `ripgrep` | Grep alternative | Rust binary |
| `delta` | Git diff pager | Rust binary |
| `zoxide` | Smart cd | Rust binary |
| `starship` | Cross-shell prompt | Rust binary |
| `eza` | Modern ls | Rust binary |
| `dust` | Disk usage | Rust binary |
| `procs` | Modern ps | Rust binary |

### Media/Content

| Package | Description | Notes |
|---------|-------------|-------|
| `ffmpeg` | Media processing | Check if Termux version lags |
| `yt-dlp` | Video download | Python, frequent updates |

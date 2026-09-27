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

### `opencode`
- **Description:** AnomalyCo's terminal-based AI coding assistant.
- **Upstream:** GitHub releases (`anomalyco/opencode`).
- **Binary Format:** Bun single-executable bundle (V8 / JavaScriptCore engine).
- **Android / Termux Hurdles:**
  1. **Binary Stripping Corruption:** Bun appends application bytecode and asset manifests to the end of the ELF executable. Running `strip` truncates this trailer, producing an unbootable binary.
  2. **Syscall Restrictions (`SIGSYS` / Signal 31):** Bun and JavaScriptCore invoke advanced Linux syscalls (`userfaultfd`, `landlock_create_ruleset`, `clone3`, etc.) that are rejected by Android seccomp filters, killing the process with `SIGSYS` (exit code 159).
  3. **Bionic / glibc Linker Collision:** If `LD_PRELOAD` contains Termux's Bionic `libtermux-exec.so`, glibc's dynamic loader crashes with `invalid ELF header`.
- **Implemented Solutions:**
  - **PRoot Syscall Trapping:** Wrapped execution inside `proot` in `helper/opencode.sh`. PRoot safely intercepts and emulates unhandled syscalls without triggering kernel seccomp faults.
  - **Safe Packaging:** Preserved Bun binary without running `strip` or incompatible UPX compression.
  - **Environment Sanitization:** Wrapper automatically clears `LD_PRELOAD` and `LD_LIBRARY_PATH` and ensures `libc.so.6` symlinks exist.
  - **Dependencies:** `glibc-repo`, `glibc`, `proot`, `ripgrep`, `jq`, `nodejs-lts`.

#### `opencode` v2 (Node.js rewrite, beta — experimental, not currently packaged)
- **Upstream:** The official `v2` branch and v2 installer; the update endpoint checked 2026-09-25 reports `2.0.16` (`@opencode/cli`). Older beta instructions used `@opencode-ai/cli@beta`, so package names and channels remain moving. The official installer writes a Linux glibc ARM64 binary and an `opencode2` shim under its own install directory.
- **Why v1 tricks do not transfer:** v2 replaces the Bun runtime and introduces a client/server architecture. A normal Termux loader invocation can start the binary, but v2 re-executes `process.execPath` to launch its managed `serve` process. When `process.execPath` is the glibc loader, the child fails with `serve: error while loading shared libraries: serve: cannot open shared object file`. `--standalone` uses the same self-exec path and is not a loader workaround.
- **Termux smoke test (2026-09-25, aarch64, glibc 2.44):** direct execution failed with `required file not found`; invoking the official v2.0.16 binary through `$PREFIX/glibc/lib/ld-linux-aarch64.so.1` reported `opencode v2.0.16`. The interactive TUI and provider requests were not independently exercised.
- **Verified no-proot workaround:** start `serve` manually through the glibc loader, then run client commands against it with `--server http://127.0.0.1:<port>` and the same `OPENCODE_PASSWORD` on both sides. A v2.0.16 `api --server ... get /api/info` request succeeded. This is suitable for headless, API, and server-oriented use; it does not repair transparent managed-service spawning.
- **Transparent managed mode:** an interpreter-only ELF patch on a copied binary may preserve `process.execPath` and allow normal self-exec, but this is an experimental community workaround, not validated by this repository. A plain shell wrapper cannot change what `/proc/self/exe` reports.
- **Existing fallback:** `proot-distro` remains the conservative compatibility route because it presents a normal Linux userspace and avoids the Android loader/re-exec mismatch. The earlier DNS/`getaddrinfo ETIMEOUT` concern remains a separate provider-network risk for native Termux builds.
- **Packaging implications:** If v2 is packaged later, keep it as a separate `opencode2` command, pin the beta version, disable auto-update, and isolate `HOME`, `XDG_*`, service registration, and database paths from v1. V1 and v2 read the same configuration locations by default, so sharing state during beta testing is unsafe.
- **Options for this repo:**
  1. Stay on v1 (current): still maintained upstream and packaged today. Zero additional support surface.
  2. Experimental native v2 companion: ship the loader/manual-server wrapper for headless users, with explicit beta and compatibility warnings.
  3. `proot-distro` companion: bootstrap a Linux userland for users who need the full v2 runtime; reliable but heavy and beta-churn-sensitive.
- **Recommendation:** keep v1 as the supported package. Document the loader/manual-server experiment separately; do not present v2 as a drop-in native package until its self-exec, update, and Android runtime behavior stabilizes.

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

### `wrangler`
- **Description:** Cloudflare Workers and Pages developer CLI.
- **Upstream:** npm registry (`wrangler`).
- **Package Format:** Architecture-independent (`all`) Debian package wrapping npm.
- **Android / Termux Hurdles:**
  1. **`workerd` Incompatibility:** Cloudflare's local runtime `workerd` is compiled for standard glibc x86_64/arm64 and does not support `android-arm64-le`, failing with `Unsupported platform: android arm64 LE` upon import.
  2. **npm Postinstall Failure:** `npm install -g wrangler` attempts to trigger build scripts that assume desktop Linux environments.
  3. **Symlink Collision:** Creating `$PREFIX/bin/wrangler` as a symlink before installing wrapper overwritten the main module script.
- **Implemented Solutions:**
  - Installed via `npm install -g --ignore-scripts` during `postinst`.
  - Stubbed `workerd/lib/main.js` with `exports.binPath = "/bin/true";` so remote API commands (`wrangler deploy`, `wrangler secret`, `wrangler tail`) work flawlessly without invoking the local emulator.
  - Provided wrapper script pointing to Node.js.

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

### 7. `yt-dlp` (video/audio downloader, latest-git tracking)
- **Feasibility:** **High (Recommended)**
- **Upstream:** GitHub `yt-dlp/yt-dlp` master. Note: there is **no** `yt-dlp-nightly` on PyPI (verified 404) — git tracking means `pip install git+https://github.com/yt-dlp/yt-dlp.git`, which needs `git` at install time.
- **Why Latest-Git:** Extractors break whenever sites redesign, so master is routinely weeks ahead of the last stable in working sites — users consistently ask for git-fresh builds, not release pins.
- **Packaging Plan:**
  - `arch=all` pure-Python package (`yt-dlp-git`), same `postinst` pattern as `wrangler`/`9router`: `pip install --upgrade git+https://github.com/yt-dlp/yt-dlp.git`.
  - `Depends: python, git` (+ optional `ffmpeg` for merging; Termux already ships it). Zero pip dependencies otherwise.
  - Date-based deb version (e.g. `2026.09.23-1`); reinstall/upgrade pulls master fresh.
  - The existing weekly CI cron (`0 0 * * 0`) already matches the desired refresh cadence; no extra scheduling needed.
  - Compounds with entry 6: git master + the builder's Android `curl_cffi` wheel = impersonation-capable downloading (`--impersonate chrome`) on the phone.

---

### 8. `hermes-agent` (Nous Research AI agent) — DO NOT PACKAGE
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

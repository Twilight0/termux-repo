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

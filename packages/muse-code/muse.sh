#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

if [[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux" ]]; then
  export SSL_CERT_FILE="${SSL_CERT_FILE:-/data/data/com.termux/files/usr/etc/tls/cert.pem}"
  export SSL_CERT_DIR="${SSL_CERT_DIR:-/data/data/com.termux/files/usr/etc/tls/certs}"
  export TMPDIR="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
fi

REAL_BIN="${PREFIX}/lib/muse/muse"
if [[ ! -x "${REAL_BIN}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "${SCRIPT_DIR}/../lib/muse/muse" ]]; then
    REAL_BIN="${SCRIPT_DIR}/../lib/muse/muse"
  fi
fi

# Handle session/mcp subcommands
if [[ "${1:-}" == "session" || "${1:-}" == "sessions" ]]; then
  shift
  exec "${PREFIX}/lib/muse/muse-session" "$@"
fi

if [[ "${1:-}" == "mcp" ]]; then
  case "${2:-}" in
    ""|list|status|import|add|enable|disable|remove|export|help)
      shift
      exec "${PREFIX}/lib/muse/muse-mcp" "$@"
      ;;
  esac
fi

# Run under proot on Termux/Android
if [[ -n "${TERMUX_VERSION:-}" || -d "/data/data/com.termux" ]]; then
  if [[ -z "${PROOT_ACTIVE:-}" ]] && ! grep -q 'TracerPid:[[:space:]]*[1-9]' /proc/self/status 2>/dev/null; then
    if ! command -v proot >/dev/null 2>&1; then
      printf 'Error: proot is required to run Muse Code on Android/Termux.\n' >&2
      printf 'Please install it with: pkg install proot\n' >&2
      exit 1
    fi
    PROOT_ARGS=("--kill-on-exit")
    PROOT_ARGS+=("-b" "/system:/system" "-b" "/vendor:/vendor" "-b" "/data:/data")
    [[ -d /apex ]] && PROOT_ARGS+=("-b" "/apex:/apex")
    [[ -d /storage ]] && PROOT_ARGS+=("-b" "/storage:/storage")
    PROOT_ARGS+=("-b" "${PREFIX}:/usr")
    for d in bin etc lib share tmp var; do
      [[ -d "${PREFIX}/${d}" ]] && PROOT_ARGS+=("-b" "${PREFIX}/${d}:/${d}")
    done
    for d in dev proc; do
      [[ -d "/${d}" ]] && PROOT_ARGS+=("-b" "/${d}:/${d}")
    done
    PROOT_ARGS+=("-r" "${PREFIX}/..")
    PROOT_ARGS+=("--cwd=.")
    export PROOT_ACTIVE=1
    export HOME="/home"
    exec proot "${PROOT_ARGS[@]}" "$REAL_BIN" "$@"
  fi
fi

# AVX2 fallback on x86_64
if [[ "$(uname -m)" == "x86_64" ]] && ! grep -q -m1 "avx2" /proc/cpuinfo 2>/dev/null; then
  if command -v qemu-x86_64 >/dev/null 2>&1; then
    exec qemu-x86_64 -cpu max "$REAL_BIN" "$@"
  else
    printf 'Error: Your CPU does not support AVX2 instructions required by Muse.\n' >&2
    printf 'Install qemu-user-x86-64: pkg install qemu-user-x86-64\n' >&2
    exit 1
  fi
else
  exec "$REAL_BIN" "$@"
fi

#!/bin/sh
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
REAL_BIN="${PREFIX}/lib/opencode/opencode-bin"
LD_LOADER="${PREFIX}/glibc/lib/ld-linux-aarch64.so.1"
LIB_PATH="${PREFIX}/glibc/lib"

if [ "$(uname -m)" = "x86_64" ]; then
    LD_LOADER="${PREFIX}/glibc/lib/ld-linux-x86-64.so.2"
fi

export SSL_CERT_FILE="${SSL_CERT_FILE:-${PREFIX}/etc/tls/cert.pem}"
export GODEBUG="netdns=cgo,asyncpreemptoff=1"

# Run under proot to intercept unallowed Android seccomp syscalls (prevents Signal 31 / SIGSYS)
if [ -n "${TERMUX_VERSION:-}" ] || [ -d "/data/data/com.termux" ]; then
  if [ -z "${PROOT_ACTIVE:-}" ]; then
    if ! command -v proot >/dev/null 2>&1; then
      echo "Error: proot is required to run opencode on Android/Termux." >&2
      echo "Please install it with: pkg install proot" >&2
      exit 1
    fi
    export PROOT_ACTIVE=1
    exec proot --kill-on-exit \
      -b /system -b /vendor -b /data -b /dev -b /proc \
      -b "${PREFIX}:${PREFIX}" \
      "$LD_LOADER" --library-path "$LIB_PATH" "$REAL_BIN" "$@"
  fi
fi

exec "$LD_LOADER" --library-path "$LIB_PATH" "$REAL_BIN" "$@"

#!/bin/sh
set -e

# opencode v2 launcher: glibc bridge + exec-spawn shim, no proot.
#
# v2 starts its background service by re-executing [process.execPath, "serve", ...].
# Under an explicit loader invocation execPath is the loader itself, so that
# spawn would become `ld-linux "serve" ...` and fail with exit 127.
# execshim.so (LD_PRELOAD) rewrites it to `ld-linux $OPENCODE_BIN serve ...`.
# The shim removes itself from child environments, so bionic tools opencode
# spawns (shell, MCP servers, ...) are unaffected. See helper/execshim.c.

unset LD_PRELOAD
unset LD_LIBRARY_PATH

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LIBDIR="${PREFIX}/lib/opencode"
REAL_BIN="${LIBDIR}/opencode-bin"

if [ "$(uname -m)" = "x86_64" ]; then
    LD_LOADER="${PREFIX}/glibc/lib/ld-linux-x86-64.so.2"
else
    LD_LOADER="${PREFIX}/glibc/lib/ld-linux-aarch64.so.1"
fi

export OPENCODE_BIN="${REAL_BIN}"
export LD_PRELOAD="${LIBDIR}/execshim.so"
export SSL_CERT_FILE="${SSL_CERT_FILE:-${PREFIX}/etc/tls/cert.pem}"
# The .deb owns this install; never let upstream self-update replace it.
export OPENCODE_DISABLE_AUTOUPDATE=1
# No TUI audio backend on Termux; silences stray audio escape sequences
export OPENCODE_DISABLE_TUI_AUDIO=1

exec "$LD_LOADER" "$REAL_BIN" "$@"

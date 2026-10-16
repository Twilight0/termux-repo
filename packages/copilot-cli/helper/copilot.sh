#!/data/data/com.termux/files/usr/bin/bash
# copilot-cli: GitHub Copilot CLI launcher for Termux (glibc bridge, no proot).
#
# The real binary is the upstream glibc Node SEA, installed at
# $PREFIX/lib/copilot-cli/copilot by the package postinst and patched to use
# Termux's glibc loader (ld-linux-*.so.*). This wrapper only prepares the
# environment and execs it.
set -e

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
REAL_BIN="$PREFIX/lib/copilot-cli/copilot"

# Bionic's termux-exec preload is incompatible with glibc processes.
unset LD_PRELOAD
unset LD_LIBRARY_PATH

# glibc runtime (libc, libstdc++, libgcc_s) lives in the glibc prefix.
export LD_LIBRARY_PATH="$PREFIX/glibc/lib"

# Upstream expects a Linux trust store; point it at Termux's CA bundle.
if [ -f "$PREFIX/etc/tls/cert.pem" ]; then
    export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
    export NODE_EXTRA_CA_CERTS="$PREFIX/etc/tls/cert.pem"
fi

# Android has no /tmp and no XDG dirs by default.
export TMPDIR="${TMPDIR:-$PREFIX/tmp}"

# The .deb owns this install: never let upstream self-update replace it with a
# binary that bypasses the glibc loader patching, and never contact the update
# endpoint at session start.
export COPILOT_AUTO_UPDATE=false

if [ ! -x "$REAL_BIN" ]; then
    echo "copilot-cli: binary not found at $REAL_BIN" >&2
    echo "Reinstall the package: pkg install --reinstall copilot-cli" >&2
    exit 1
fi

exec "$REAL_BIN" "$@"

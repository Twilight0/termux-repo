#!/bin/sh
# antigravity: Launcher for Google Antigravity CLI on Termux (glibc bridge)
set -e

PREFIX="/data/data/com.termux/files/usr"
GLIBC_DIR="${PREFIX}/glibc"
LIB_DIR="${PREFIX}/lib/antigravity-cli"

# Clear Bionic preloads so glibc dynamic linker does not load incompatible libraries
unset LD_PRELOAD
unset LD_LIBRARY_PATH

# Ensure Go runtime resolves DNS properly through glibc/resolv.conf
export GODEBUG="${GODEBUG:+$GODEBUG,}netdns=cgo"

# Ensure SSL certificate bundle is discoverable
if [ -f "${PREFIX}/etc/tls/cert.pem" ]; then
    export SSL_CERT_FILE="${PREFIX}/etc/tls/cert.pem"
elif [ -f "${PREFIX}/etc/ssl/certs/ca-certificates.crt" ]; then
    export SSL_CERT_FILE="${PREFIX}/etc/ssl/certs/ca-certificates.crt"
fi

# Detect glibc dynamic linker
if [ -x "${GLIBC_DIR}/bin/ld.so" ]; then
    LD_LOADER="${GLIBC_DIR}/bin/ld.so"
elif [ -f "${GLIBC_DIR}/lib/ld-linux-aarch64.so.1" ]; then
    LD_LOADER="${GLIBC_DIR}/lib/ld-linux-aarch64.so.1"
elif [ -f "${GLIBC_DIR}/lib/ld-linux-x86-64.so.2" ]; then
    LD_LOADER="${GLIBC_DIR}/lib/ld-linux-x86-64.so.2"
else
    echo "Error: glibc loader not found. Install glibc with: pkg install glibc" >&2
    exit 1
fi

# Locate the actual binary
if [ -f "${LIB_DIR}/agy.bin" ]; then
    REAL_BIN="${LIB_DIR}/agy.bin"
elif [ -f "${LIB_DIR}/antigravity" ]; then
    REAL_BIN="${LIB_DIR}/antigravity"
elif [ -f "${LIB_DIR}/agy.va39" ]; then
    REAL_BIN="${LIB_DIR}/agy.va39"
else
    echo "Error: antigravity binary not found in ${LIB_DIR}" >&2
    exit 1
fi

exec "$LD_LOADER" --library-path "${GLIBC_DIR}/lib" "$REAL_BIN" "$@"

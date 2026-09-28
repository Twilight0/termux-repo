#!/bin/sh
# agentty is an NDK prebuilt without RUNPATH, so the dynamic loader cannot
# find Termux libraries on its own (LD_LIBRARY_PATH is empty by default).
set -e
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export LD_LIBRARY_PATH="${PREFIX}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "${PREFIX}/lib/agentty/agentty.bin" "$@"

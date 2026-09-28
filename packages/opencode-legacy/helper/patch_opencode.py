#!/usr/bin/env python3
"""
Patch ARM64 syscalls in opencode binary for Android/Termux compatibility.
Fixes faccessat2 (syscall 439 -> 48 faccessat) which causes SIGSYS (Signal 31).
"""
import sys
import shutil
import struct
import pathlib


def get(data, off):
    return struct.unpack_from("<I", data, off)[0]


def put(data, off, word):
    struct.pack_into("<I", data, off, word)


def patch(src_path, dst_path):
    shutil.copyfile(src_path, dst_path)
    data = bytearray(dst_path.read_bytes())

    patched_faccessat2 = 0
    # Patch faccessat2 (mov x8, #439 -> mov x8, #48)
    for off in range(0, len(data) - 12, 4):
        if (get(data, off) == 0xAA1F03E5
                and get(data, off + 4) == 0xAA1F03E6
                and get(data, off + 8) == 0xD28036E0
                and (get(data, off + 12) & 0xFC000000) == 0x94000000):
            put(data, off + 8, 0xD2800600)
            patched_faccessat2 += 1

    dst_path.write_bytes(data)
    print(f"Patched opencode binary: {patched_faccessat2} faccessat2 syscalls replaced.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input> <output>", file=sys.stderr)
        sys.exit(1)
    patch(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))

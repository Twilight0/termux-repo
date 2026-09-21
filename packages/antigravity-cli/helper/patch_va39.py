#!/usr/bin/env python3
"""
VA39 memory patcher for antigravity-cli on Android/Termux.

Android uses 39-bit virtual addressing (48-bit TBI), but the upstream
antigravity-cli binary assumes 48-bit VA space. This script rewrites
ARM64 instructions to fix TCMalloc page alignment, mmap parameters,
and the faccessat2 syscall number.

Based on analysis from:
- https://github.com/google-antigravity/antigravity-cli/issues/64
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
    lo, hi = 0, len(data)

    # Fix SBFM/BFM instructions with specific immr/imms values
    for off in range(lo, hi, 4):
        w = get(data, off)
        if (w & 0x7F800000) == 0x53000000:
            immr = (w >> 16) & 0x3F
            imms = (w >> 10) & 0x3F
            if immr == 42 and imms == 44:
                put(data, off, (w & ~((0x3F << 16) | (0x3F << 10))) | (35 << 16) | (37 << 10))
            elif immr == 22 and imms == 21:
                put(data, off, (w & ~((0x3F << 16) | (0x3F << 10))) | (29 << 16) | (28 << 10))

    # Fix movz+movk pairs (48-bit VA bitmask -> 39-bit)
    for off in range(lo, hi - 4, 4):
        if get(data, off) == 0x92D3800A and get(data, off + 4) == 0xF2E0000A:
            put(data, off, 0x9280000A)
            put(data, off + 4, 0xD35DFD4A)
    for off in range(lo, hi, 4):
        if get(data, off) == 0xF2E00029:
            put(data, off, 0xD3596129)

    # Word rewrites for page alignment and mmap parameters
    word_rewrites = {
        0xD2C20009: 0xD2C00409, 0xD2C2000A: 0xD2C0040A,
        0xF2C20008: 0xF2DFF408, 0xF2C20009: 0xF2DFF409,
        0xD2C10009: 0xD2C00209, 0xD2C1000A: 0xD2C0020A,
        0xF2C38008: 0xF2DFF708, 0xF2C38009: 0xF2DFF709,
        0x92560A6C: 0x925D0A6C, 0x92560A6A: 0x925D0A6A,
        0xD2C3000D: 0xD2C0060D, 0xD2C3000C: 0xD2C0060C,
        0xD2C08008: 0xD2C00108,
    }
    for off in range(lo, hi, 4):
        w = get(data, off)
        if w in word_rewrites:
            put(data, off, word_rewrites[w])

    # Fix faccessat2 syscall -> faccessat
    for off in range(0, len(data) - 12, 4):
        if (get(data, off) == 0xAA1F03E5
                and get(data, off + 4) == 0xAA1F03E6
                and get(data, off + 8) == 0xD28036E0
                and (get(data, off + 12) & 0xFC000000) == 0x94000000):
            put(data, off + 8, 0xD2800600)

    dst_path.write_bytes(data)
    print(f"Patched: {src_path} -> {dst_path}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input> <output>", file=sys.stderr)
        sys.exit(1)
    patch(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))

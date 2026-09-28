#!/usr/bin/env python3
"""Reference implementation of core/rng.lua (FNV-1a 32 and mulberry32).

The daily challenge must be identical on every phone, so the Lua generator is
checked against these values in core/test/tests.lua. Run this to print them:
    python3 tools/rng_reference.py
"""

M32 = 0xFFFFFFFF


def fnv1a(text):
    h = 2166136261
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 16777619) & M32
    return h


def mulberry32(seed):
    state = seed & M32
    while True:
        state = (state + 0x6D2B79F5) & M32
        t = ((state ^ (state >> 15)) * (1 | state)) & M32
        t = ((t + (((t ^ (t >> 7)) * (61 | t)) & M32)) & M32) ^ t
        yield ((t ^ (t >> 14)) & M32) / 4294967296


if __name__ == "__main__":
    for key in ("", "a", "yaksha:20724"):
        print("fnv1a(%r) = %d" % (key, fnv1a(key)))
    gen = mulberry32(fnv1a("yaksha:20724"))
    print("mulberry32(fnv1a('yaksha:20724')):", [round(next(gen), 12) for _ in range(5)])
    gen = mulberry32(0)
    print("mulberry32(0):", [round(next(gen), 12) for _ in range(3)])

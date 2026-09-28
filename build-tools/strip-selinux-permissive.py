#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Strip androidboot.selinux=permissive from boot.img header cmdline (make SELinux enforcing default).

usage: strip-selinux-permissive.py <boot.img> [out.img]
       (out defaults to overwriting <boot.img> atomically via .new)
"""
import struct, sys, os, shutil

def patch(path, out):
    data = bytearray(open(path, "rb").read())
    ver = struct.unpack_from("<I", data, 40)[0]
    # header: cmdline @64 (512 bytes), extra_cmdline @608 (1024 bytes) for v1+
    regions = [(64, 512)]
    if ver >= 1:
        regions.append((608, 1024))
    changed = False
    for off, ln in regions:
        raw = bytes(data[off:off+ln])
        end = raw.find(b"\x00")
        s = raw if end < 0 else raw[:end]
        text = s.decode(errors="replace")
        if "androidboot.selinux=permissive" not in text:
            continue
        args = [a for a in text.split() if a != "androidboot.selinux=permissive"]
        new = " ".join(args).encode()
        if len(new) >= ln:
            print(f"FATAL: new cmdline too long ({len(new)} > {ln})"); sys.exit(1)
        data[off:off+ln] = new + b"\x00" * (ln - len(new))
        print(f"  patched region @{off}: removed androidboot.selinux=permissive")
        print(f"  old: {text}")
        print(f"  new: {new.decode()}")
        changed = True
    if not changed:
        print("  nothing to do (no androidboot.selinux=permissive found)")
        return False
    tmp = out + ".new"
    open(tmp, "wb").write(bytes(data))
    shutil.move(tmp, out)
    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else src
    print(f"patching {src} -> {out}")
    ok = patch(src, out)
    # verify
    d = open(out, "rb").read()
    cmd = d[64:64+512].split(b"\x00")[0].decode(errors="replace")
    print(f"verify header cmdline: {cmd!r}")
    print(f"still has permissive: {'androidboot.selinux=permissive' in cmd}")

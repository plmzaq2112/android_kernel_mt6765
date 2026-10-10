#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Strip androidboot.selinux=permissive from boot.img header cmdline (make SELinux enforcing default).

usage: strip-selinux-permissive.py <boot.img> [out.img]
       (out defaults to overwriting <boot.img> atomically via .new)
"""
import sys, os, shutil

def regions_of(data):
    # boot_img_hdr_v0 就含 cmdline@64(512) 与 extra_cmdline@608(1024),
    # v0/v1/v2 布局在这两段上完全一致 —— 不存在"只有 v1+ 才有 extra_cmdline"。
    return [(64, 512), (608, 1024)]

def patch(path, out):
    data = bytearray(open(path, "rb").read())
    changed = False
    for off, ln in regions_of(data):
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
    # verify: 必须覆盖全部 cmdline 区域, 否则 extra_cmdline 里的漏网会报"已清除"
    d = open(out, "rb").read()
    left = []
    for off, ln in regions_of(d):
        raw = d[off:off+ln]
        end = raw.find(b"\x00")
        cmd = (raw if end < 0 else raw[:end]).decode(errors="replace")
        print(f"verify cmdline @{off}: {cmd!r}")
        if "androidboot.selinux=permissive" in cmd:
            left.append(off)
    print(f"still has permissive: {bool(left)}" + (f" @ {left}" if left else ""))
    sys.exit(1 if left else 0)

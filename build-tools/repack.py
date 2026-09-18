# SPDX-License-Identifier: GPL-2.0
#!/usr/bin/env python3
"""Repack boot.img: replace kernel, keep original ramdisk + dtb + header fields."""
import struct, sys

SRC = "/home/yang/项目/kernel/boot.img"
NEW_KERNEL = "/home/yang/项目/kernel/out/arch/arm64/boot/Image.gz"
OUT = sys.argv[1] if len(sys.argv) > 1 else "/home/yang/项目/kernel/boot-full.img"
BOOTDIR = "/home/yang/项目/kernel/tools/boot"

data = open(SRC, "rb").read()
kernel_gz = open(NEW_KERNEL, "rb").read()
ramdisk = open(BOOTDIR + "/ramdisk.gz", "rb").read()
dtb = open(BOOTDIR + "/dtb", "rb").read()

def u32(off): return struct.unpack_from("<I", data, off)[0]
def u64(off): return struct.unpack_from("<Q", data, off)[0]

page = u32(36)
hdr_ver = u32(40)
print(f"page_size={page} header_version={hdr_ver}")

# fields to preserve
kernel_addr = u32(12)
ramdisk_size = u32(16)
ramdisk_addr = u32(20)
second_size = u32(24)
second_addr = u32(28)
tags_addr = u32(32)
dtb_size = u32(1648)
dtb_addr = u64(1652)

assert ramdisk_size == len(ramdisk), "ramdisk mismatch!"
assert dtb_size == len(dtb), "dtb mismatch!"

hdr = bytearray(data[:page])  # first page = header
struct.pack_into("<I", hdr, 8, len(kernel_gz))  # kernel_size

# 去除 cmdline 中的 cgroup 限制项 (恢复 PSI cgroup + kmem/socket 记账)
cmd_off, cmd_len = 64, 512
cmd = hdr[cmd_off:cmd_off + cmd_len].split(b"\x00", 1)[0].decode(errors="replace")
for bad in (" cgroup_disable=pressure", " cgroup.memory=nokmem,nosocket", " kpti=off"):
    cmd = cmd.replace(bad, "")
if "secretmem.enable" not in cmd:
    cmd += " secretmem.enable=1"
new_cmd = (cmd.encode() + b"\x00" * cmd_len)[:cmd_len]
hdr[cmd_off:cmd_off + cmd_len] = new_cmd
print(f"新cmdline: {cmd}")

def pad_page(buf, off):
    p = (page - (off % page)) % page
    buf += b"\x00" * p
    return off + p

out = bytearray()
out += hdr
out += kernel_gz
off = len(out)
off = pad_page(out, off)
out += ramdisk
off = len(out)
off = pad_page(out, off)
out += dtb
off = len(out)
off = pad_page(out, off)

# pad to original size (keep partition-size consistency)
orig_size = len(data)
out += b"\x00" * (orig_size - len(out))

with open(OUT, "wb") as f:
    f.write(out)

print(f"kernel:    {len(kernel_gz)} bytes")
print(f"ramdisk:   {len(ramdisk)} bytes (unchanged)")
print(f"dtb:       {len(dtb)} bytes (unchanged)")
print(f"output:    {OUT} ({len(out)} bytes)")
#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Debug 版打包:复制自 pack_boot.py(正式工具一字不动),新增 CMDLINE_APPEND。

与 pack_boot.py 的唯一差异:
  - 通过环境变量 CMDLINE_APPEND 向 header 内 cmdline 字段(offset 68, 512B)追加参数
  - 未设置 CMDLINE_APPEND 时行为与 pack_boot.py 完全一致
  - 默认输出改为 <树根>/out-debug/boot-repacked-debug.img (不与正式输出同路径)

用法:
  KERNEL_IMG=<Image.gz> CMDLINE_APPEND="initcall_debug ignore_loglevel" \
    python3 pack_boot_debug.py <基底boot.img> [输出boot.img]

仅替换 kernel 段; ramdisk/dtb/header 原样保留(批次4 验证过的零风险策略)。
"""
import struct
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# boot header 内 cmdline 字段 (name[16]@48 之后有 4B MTK 前缀,实测有效 cmdline 起点 68)
CMDLINE_OFF = 68
CMDLINE_LEN = 512  # 68..580


def u32(data, off):
    return struct.unpack_from("<I", data, off)[0]


def align_up(x, page):
    return ((x + page - 1) // page) * page


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else \
        os.path.join(ROOT, "out-debug", "boot-repacked-debug.img")
    new_kernel = os.environ.get("KERNEL_IMG") or \
        os.path.join(ROOT, "out-debug", "arch", "arm64", "boot", "Image.gz")
    cmdline_append = os.environ.get("CMDLINE_APPEND") or ""

    if not os.path.isfile(src):
        print(f"ERROR: 基底镜像不存在: {src}")
        sys.exit(1)
    if not os.path.isfile(new_kernel):
        print(f"ERROR: 内核镜像不存在: {new_kernel}")
        print("  先跑 build-tools/build_debug.sh, 再用 KERNEL_IMG=$O/arch/arm64/boot/Image.gz 指定")
        sys.exit(1)

    data = open(src, "rb").read()
    kernel_gz = open(new_kernel, "rb").read()

    if data[:8] != b"ANDROID!":
        print(f"ERROR: {src} 不是 boot.img (magic={data[:8]!r})")
        sys.exit(1)

    out_dir = os.path.dirname(os.path.abspath(out))
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    page = u32(data, 36)
    hdr_ver = u32(data, 40)
    print(f"page_size={page} header_version={hdr_ver}")

    kernel_size = u32(data, 8)
    ramdisk_size = u32(data, 16)
    second_size = u32(data, 24)

    hdr = bytearray(data[:page])
    struct.pack_into("<I", hdr, 8, len(kernel_gz))  # kernel_size 替换

    # ---- cmdline 追加 (debug 版专属) ----
    if cmdline_append:
        field = bytes(hdr[CMDLINE_OFF:CMDLINE_OFF + CMDLINE_LEN])
        nul = field.find(b"\x00")
        cur = field[:nul if nul >= 0 else CMDLINE_LEN - 1].decode("ascii", "replace")
        new = (cur + " " + cmdline_append).strip()
        nb = new.encode("ascii")
        if len(nb) >= CMDLINE_LEN:
            print(f"ERROR: cmdline 溢出: {len(nb)} >= {CMDLINE_LEN}B")
            sys.exit(1)
        hdr[CMDLINE_OFF:CMDLINE_OFF + CMDLINE_LEN] = \
            nb + b"\x00" * (CMDLINE_LEN - len(nb))
        print(f"cmdline 旧({len(cur)}B): {cur}")
        print(f"cmdline 新({len(nb)}B): {new}")

    # 定位原 ramdisk / dtb (逐段 page 对齐)
    off = page
    off += align_up(kernel_size, page)
    ramdisk_abs = off
    off += align_up(ramdisk_size, page)
    off += align_up(second_size, page)
    dtb_abs = off
    dtb_size = u32(data, 1648) if hdr_ver >= 2 and len(data) > 1656 else 0

    ramdisk = data[ramdisk_abs:ramdisk_abs + ramdisk_size]
    dtb = data[dtb_abs:dtb_abs + dtb_size] if dtb_size else b""

    print(f"原 kernel: {kernel_size} bytes")
    print(f"ramdisk:   {len(ramdisk)} bytes @0x{ramdisk_abs:x}")
    print(f"dtb:       {len(dtb)} bytes @0x{dtb_abs:x}")

    if not ramdisk:
        print("ERROR: ramdisk 为空, layout 解析失败")
        sys.exit(1)

    out_buf = bytearray()
    out_buf += hdr
    out_buf += kernel_gz
    off = len(out_buf)
    out_buf += b"\x00" * ((page - (off % page)) % page)
    out_buf += ramdisk
    off = len(out_buf)
    out_buf += b"\x00" * ((page - (off % page)) % page)
    if dtb:
        out_buf += dtb
        off = len(out_buf)
        out_buf += b"\x00" * ((page - (off % page)) % page)

    # 保持与原 boot.img 等长(分区对齐)
    if len(out_buf) < len(data):
        out_buf += b"\x00" * (len(data) - len(out_buf))

    with open(out, "wb") as f:
        f.write(out_buf)
    print(f"kernel:    {len(kernel_gz)} bytes")
    print(f"output:    {out} ({len(out_buf)} bytes)"
          f" vs 基底 {len(data)} bytes")


if __name__ == "__main__":
    main()

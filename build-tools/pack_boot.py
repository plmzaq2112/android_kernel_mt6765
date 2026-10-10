#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""从原厂 boot.img 里提取 ramdisk/dtb 并重打包:仅替换 kernel,其余原样保留 (boot header v1/v2)。

用法:
  KERNEL_IMG=<Image.gz> python3 pack_boot.py <原厂boot.img> [输出boot.img]

默认值(均相对本脚本所在树,不再硬编码版本号/家目录):
  输出   : <树根>/out/boot-repacked.img
  内核   : <树根>/out/arch/arm64/boot/Image.gz   (可用 KERNEL_IMG 覆盖, 见 build_full.sh)
  ramdisk: 沿用原镜像                            (可用 RAMDISK_IMG 覆盖)
"""
import struct
import sys
import os

# <树根> = build-tools/ 的上一级
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def u32(data, off):
    return struct.unpack_from("<I", data, off)[0]

def u64(data, off):
    return struct.unpack_from("<Q", data, off)[0]

def align_up(x, page):
    return ((x + page - 1) // page) * page

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else \
        os.path.join(ROOT, "out", "boot-repacked.img")
    new_kernel = os.environ.get("KERNEL_IMG") or \
        os.path.join(ROOT, "out", "arch", "arm64", "boot", "Image.gz")
    new_ramdisk = os.environ.get("RAMDISK_IMG") or None

    if not os.path.isfile(src):
        print(f"ERROR: 原厂镜像不存在: {src}"); sys.exit(1)
    if not os.path.isfile(new_kernel):
        print(f"ERROR: 内核镜像不存在: {new_kernel}")
        print("  先跑 build-tools/build_full.sh, 再用 KERNEL_IMG=$O/arch/arm64/boot/Image.gz 指定,")
        print(f"  或直接 KERNEL_IMG=/path/to/Image.gz (当前 O=?)")
        sys.exit(1)

    data = open(src, "rb").read()
    kernel_gz = open(new_kernel, "rb").read()

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

    # 定位原 ramdisk / dtb (逐段 page 对齐)
    off = page
    off += align_up(kernel_size, page)
    ramdisk_abs = off
    off += align_up(ramdisk_size, page)
    off += align_up(second_size, page)
    dtb_abs = off
    dtb_size = u32(data, 1648) if hdr_ver >= 2 and len(data) > 1656 else 0

    ramdisk = data[ramdisk_abs:ramdisk_abs + ramdisk_size]
    if new_ramdisk:
        custom = open(new_ramdisk, "rb").read()
        struct.pack_into("<I", hdr, 16, len(custom))  # ramdisk_size 替换
        print(f"ramdisk:   替换为 {len(custom)} bytes (原 {ramdisk_size})")
        ramdisk = custom
    dtb = data[dtb_abs:dtb_abs + dtb_size] if dtb_size else b""

    print(f"原 kernel: {kernel_size} bytes")
    print(f"ramdisk:   {len(ramdisk)} bytes @0x{ramdisk_abs:x}")
    print(f"dtb:       {len(dtb)} bytes @0x{dtb_abs:x}")

    if not ramdisk:
        print("ERROR: ramdisk 为空, layout 解析失败")
        sys.exit(1)

    out_buf = bytearray()
    out_buf += hdr
    off = len(out_buf)
    out_buf += kernel_gz
    off += len(kernel_gz)
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
          f" vs 原 {len(data)} bytes")

if __name__ == "__main__":
    main()
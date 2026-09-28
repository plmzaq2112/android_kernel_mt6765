#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# 一键构建：生成配置 -> 断言 -> 编译 Image.gz
#
# 用法:
#   bash build-tools/build_full.sh          # 默认输出到 out/
#   O=out-test bash build-tools/build_full.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

O=${O:-out}
LOG=${LOG:-build.log}
export PATH=/usr/lib/llvm-18/bin:/usr/bin:/bin:/usr/local/bin:$PATH

MAKE_ARGS=(
    ARCH=arm64
    O="$O"
    CC=clang
    CROSS_COMPILE=aarch64-linux-gnu-
    LD=ld.lld
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    STRIP=llvm-strip
    AR=llvm-ar
)

echo "=== [1/3] generating $O/.config from blossom_defconfig ==="
make "${MAKE_ARGS[@]}" blossom_defconfig

echo "=== [2/3] asserting config ==="
bash build-tools/check_config.sh "$O/.config"

echo "=== [3/3] building Image.gz (log: $LOG) ==="
make -j"$(nproc)" "${MAKE_ARGS[@]}" Image.gz 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

echo ""
if [ "$rc" -eq 0 ]; then
    echo "=== build OK ==="
    echo "  image  : $O/arch/arm64/boot/Image.gz ($(stat -c%s "$O/arch/arm64/boot/Image.gz") bytes)"
    echo "  uts    : $(grep UTS_RELEASE "$O/include/generated/utsrelease.h" | tail -1)"
    echo "  next   : python3 build-tools/pack_boot.py <base_boot.img> <out_boot.img>"
else
    echo "=== build FAILED (rc=$rc) ==="
    grep -E 'error:' "$LOG" | head -20
    exit "$rc"
fi

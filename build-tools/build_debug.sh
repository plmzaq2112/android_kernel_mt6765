#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# Debug 内核一键构建（批0 框架）
# - 独立输出目录 out-debug/，不触碰 out/（正式版）
# - 正式 defconfig 一字不动：blossom_defconfig + build-tools/debug.config 合并
# - 保留正式版断言（check_config.sh），另加 debug 断言（check_debug.sh）
#
# 用法:
#   bash build-tools/build_debug.sh            # 默认输出到 out-debug/
#   O=out-debug2 bash build-tools/build_debug.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

O=${O:-out-debug}
LOG=${LOG:-$O/build-debug.log}
export PATH=/usr/lib/llvm-21/bin:/usr/bin:/bin:/usr/local/bin:$PATH

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

echo "=== [1/6] generating $O/.config from blossom_defconfig ==="
make "${MAKE_ARGS[@]}" blossom_defconfig

echo "=== [2/6] merging build-tools/debug.config (merge_config -m) ==="
./scripts/kconfig/merge_config.sh -O "$O" -m "$O/.config" build-tools/debug.config \
    > "$O/merge_config.log" 2>&1 || { echo "merge failed"; cat "$O/merge_config.log"; exit 1; }
grep -iE '^(CONFIG_LOCALVERSION=|CONFIG_DEBUG_FS|CONFIG_DYNAMIC_DEBUG|CONFIG_DETECT_HUNG_TASK|CONFIG_SOFTLOCKUP_DETECTOR|CONFIG_WQ_WATCHDOG)' "$O/.config" || true

echo "=== [3/6] olddefconfig (resolve deps) ==="
make "${MAKE_ARGS[@]}" olddefconfig > /dev/null

echo "=== [4/6] asserting release baseline intact (check_config.sh) ==="
bash build-tools/check_config.sh "$O/.config"

echo "=== [5/6] asserting debug additions (check_debug.sh) ==="
bash build-tools/check_debug.sh "$O/.config"

echo "=== [6/6] building Image.gz (log: $LOG) ==="
# 同 build_full.sh：tee 管道 + set -e 会吞 PIPESTATUS，临时放开
set +e
make -j"$(nproc)" "${MAKE_ARGS[@]}" Image.gz 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e
if [ $rc -ne 0 ]; then
    echo "BUILD FAILED rc=$rc (tail $LOG)"
    tail -25 "$LOG"
    exit $rc
fi

echo "=== done ==="
ls -la "$O/arch/arm64/boot/Image.gz"
echo "kernel.release: $(cat "$O/include/config/kernel.release")"

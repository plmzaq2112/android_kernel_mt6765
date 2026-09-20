#!/bin/bash
# pack-dandelion-perf.sh - Pack dandelion-perf boot.img
set -e

OUT=/home/a12bbb/android-kernel/kernel-upgrade/mtk50-port/out_dandelion_perf
RD=/home/a12bbb/android-kernel/kernel-upgrade/mtk50-port/ramdisk_work/v11_clean1-rd.gz
STOCK=/home/a12bbb/android-kernel/kernel-419/stock_boot.img
PACK=/home/a12bbb/android-kernel/kernelsu/release/scripts/pack_boot.py
WOUT=/mnt/c/Users/31806/Documents/android-kernel

export KERNEL_IMG=$OUT/arch/arm64/boot/Image.gz
export RAMDISK_IMG=$RD

echo "=== Pack boot.img ==="
python3 $PACK $STOCK $OUT/boot-dandelion-perf.img

echo "=== Copy to Windows ==="
cp $OUT/boot-dandelion-perf.img $WOUT/
ls -la $WOUT/boot-dandelion-perf.img

echo "=== Verify ==="
strings $OUT/arch/arm64/boot/Image.gz | grep -i 'kernelsu' | head -3 || echo "No KernelSU (good)"

echo "=== Done ==="
echo "Flash: fastboot flash boot boot-dandelion-perf.img"

#!/bin/bash
# build-dandelion-perf.sh - Build dandelion-perf kernel
# Combines: stock_defconfig + NR_CPUS=8 fragment + performance fragment
set -e

SRCDIR=/home/a12bbb/android-kernel/kernel-419/android_kernel_mt6765-main
OUT=/home/a12bbb/android-kernel/kernel-upgrade/mtk50-port/out_dandelion_perf
FRAG_DIR=$SRCDIR/build-tools/dandelion-perf
export PATH=/usr/lib/llvm-18/bin:/usr/bin:/bin:/usr/local/bin:$PATH

cd $SRCDIR

echo "=== Step 1: stock_defconfig ==="
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LD=ld.lld O=$OUT stock_defconfig

echo "=== Step 2: Apply NR_CPUS=8 fragment ==="
scripts/kconfig/merge_config.sh -m -O $OUT $OUT/.config \
  build-tools/stock-baseline/boot-4.19.275-perf-v2.config-fragment

echo "=== Step 3: Apply performance fragment ==="
scripts/kconfig/merge_config.sh -m -O $OUT $OUT/.config \
  build-tools/dandelion-perf/dandelion-perf.config-fragment

echo "=== Step 4: Disable KernelSU ==="
sed -i 's/CONFIG_KSU=y/# CONFIG_KSU is not set/' $OUT/.config
sed -i 's/CONFIG_KSU=m/# CONFIG_KSU is not set/' $OUT/.config

echo "=== Step 5: olddefconfig ==="
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LD=ld.lld O=$OUT olddefconfig

echo "=== Verify ==="
grep 'CONFIG_KSU' $OUT/.config || echo "KSU: disabled"
grep 'CONFIG_IOSCHED_BFQ\|CONFIG_IO_URING\|CONFIG_HZ_1000\|CONFIG_KSM\|CONFIG_PSI' $OUT/.config

echo "=== Step 6: Build ==="
make -j$(nproc) O=$OUT \
  ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
  LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
  STRIP=llvm-strip AR=llvm-ar Image.gz

echo "=== Done ==="
ls -la $OUT/arch/arm64/boot/Image.gz

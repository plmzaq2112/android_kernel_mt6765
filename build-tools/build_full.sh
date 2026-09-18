# SPDX-License-Identifier: GPL-2.0
#!/bin/bash
cd /home/yang/项目/kernel/mt6765-4.19
TC=/home/yang/项目/kernel/toolchain/bin
export PATH="$TC:/usr/bin:/bin:/usr/sbin:/sbin"
export LD_LIBRARY_PATH=/home/yang/项目/kernel/tools/xml2${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
LOG=/home/yang/项目/kernel/build-full.log
exec > "$LOG" 2>&1
echo "=== full build start $(date) ==="
make ARCH=arm64 O=/home/yang/项目/kernel/out \
    CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
    LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip AR=llvm-ar \
    KCFLAGS="-Wno-error" \
    -j10 Image.gz 2>&1
echo "=== full build end rc=$? $(date) ==="
